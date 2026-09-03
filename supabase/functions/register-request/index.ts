import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  appOrigin,
  clientIp,
  consumeRateLimit,
  corsHeaders,
  encryptSecret,
  generateCode,
  generateToken,
  hmac,
  isEligibleAddress,
  json,
  normaliseEmail,
} from "../_shared/identity.ts";
import { alertStuckApplicant } from "../_shared/approvers.ts";
import { dispatch } from "../_shared/mailer.ts";

// Step 1 of proving a DIU mailbox.
//
// Replaces the client's direct auth.signUp() call. Nothing is written to
// auth.users, profiles, students, teachers or staff here — the signup is held
// in pending_registrations until the emailed code or link comes back, and only
// register-verify creates the real account.
//
// WHY THE FLOW HAD TO INVERT. enforce_email_domain proved an address ENDS IN
// @diu.edu.bd; auto_confirm_email then stamped email_confirmed_at on every
// insert. Measured on the live project 2026-08-16, all 12 auth.users rows had
// conf_mail_sent=false. So the system proved the format of a string and never
// proved control of the mailbox, and anyone who knew DIU's address pattern
// could register as a student they had never met.

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SERVICE_ROLE_KEY")!;

// Thirty minutes, not ten.
//
// Ten was the original guess and two of the three signups still open in
// pending_registrations died on it -- one of them flagged in so many words,
// "Code expired before it was used". University mailboxes are not instant:
// the send is queued behind a provider rate limit, then a campus mail server
// greylists it, and the applicant is often not sitting on the screen when it
// finally lands.
//
// It costs almost nothing. The code is six digits against a bucket of 8
// attempts refilling at 0.25/min, so a thirty-minute window allows about 15
// guesses instead of 10 -- against a million possibilities. The attempt
// counter is the defence here, not the clock.
const EXPIRES_MINUTES = 30;

// Where an applicant is told to go when we cannot mail them. Env-overridable
// so support contacts can change without shipping an app release — the phone
// renders whatever the response carries.
const SUPPORT_EMAIL = Deno.env.get("SUPPORT_EMAIL") ?? "rakibhassan.rh66@protonmail.com";
const SUPPORT_TELEGRAM = Deno.env.get("SUPPORT_TELEGRAM") ?? "@deadbrat";
const ACCOUNT_TYPES = ["student", "teacher", "staff"];

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE);
    const body = await req.json().catch(() => ({}));

    const email = normaliseEmail(body.email);
    const password = String(body.password ?? "");
    const fullName = String(body.fullName ?? "").trim();

    if (!email || !password || !fullName) {
      return json({ error: "Name, email and password are all required." }, 400);
    }
    if (password.length < 8) {
      return json({ error: "Password must be at least 8 characters." }, 400);
    }

    const accountType = ACCOUNT_TYPES.includes(body.accountType) ? body.accountType : "student";

    // Registration can be closed centrally (semester rollover, incident
    // response) without a redeploy.
    //
    // select("*") rather than naming columns: manual_approval_fallback does
    // not exist until 20260817120000 is applied, and PostgREST errors on a
    // named column that is missing — which would take registration itself
    // down rather than just hiding a button. Reads as ON when absent.
    const { data: cfg } = await supabase
      .from("app_config").select("*").eq("id", 1).maybeSingle();
    if (cfg && cfg.registration_open === false) {
      return json({ error: "Registration is closed right now. Please try again later." }, 503);
    }
    // Whether to offer the applicant the "I never got the email" escape hatch.
    // Sent on BOTH return paths below — an answer that appeared on only one of
    // them would reintroduce the enumeration oracle the identical shapes exist
    // to close.
    const manualFallback = cfg?.manual_approval_fallback !== false;

    if (!await isEligibleAddress(supabase, email)) {
      return json({ error: "Only DIU (@diu.edu.bd) email addresses can register." }, 400);
    }

    // Both limits are checked BEFORE any mail work. Without them the mail
    // budget is the denial-of-service surface: a loop on one address would
    // both exhaust the provider quota and mail-bomb a real student.
    const ip = clientIp(req);
    if (!await consumeRateLimit(supabase, "email_verify_addr", email)) {
      return json({
        error: "A code was just sent to that address. Check your inbox, or wait a few minutes before asking for another.",
      }, 429);
    }
    if (!await consumeRateLimit(supabase, "email_verify_ip", await hmac(ip))) {
      return json({ error: "Too many registration attempts from this device. Try again later." }, 429);
    }

    const expiresAt = new Date(Date.now() + EXPIRES_MINUTES * 60_000);

    // ANTI-ENUMERATION. If the address already has an account we tell the real
    // owner (so a genuine mistake is recoverable) but return the IDENTICAL
    // response shape to the caller. A probe therefore cannot learn which DIU
    // addresses are registered — which matters, because a list of confirmed
    // student accounts is itself worth stealing.
    const { data: existing } = await supabase
      .from("profiles").select("id, full_name").eq("email", email).maybeSingle();

    if (existing) {
      // The lane is REPORTED, not discarded. It used to be swallowed here
      // while the real path returned it, so under mail-queue pressure the two
      // responses could be told apart by the presence of that one field —
      // which is the enumeration oracle these identical shapes exist to close.
      // Mirrors the real path's shape EXACTLY, mailFailed included. Reporting
      // it on only one branch would reintroduce the enumeration oracle these
      // identical responses exist to close — and it leaks nothing, because
      // whether the provider accepts an address does not depend on whether we
      // hold an account for it.
      let lane = "inline";
      let mailFailed = false;
      let mailReason: "quota" | "provider" | null = null;
      try {
        lane = await dispatch(supabase, {
          to: email,
          template: "account_exists",
          payload: { fullName: existing.full_name, loginUrl: `${appOrigin()}/#/auth/login` },
          dedupeKey: `exists:${email}:${Math.floor(Date.now() / 900_000)}`,
          priority: 4,
        });
      } catch (e) {
        console.error("[register-request] account_exists dispatch failed:", e);
        mailFailed = true;
        mailReason = "provider";
        lane = "failed";
      }

      // EVERY KEY THE REAL BRANCH SENDS, or this is an enumeration oracle.
      //
      // The comment above promises this "mirrors the real path's shape
      // EXACTLY". It did not: mailReason, supportEmail and supportTelegram
      // were sent only on the real branch. Three keys present in one response
      // and absent in the other distinguishes a registered DIU address from an
      // unregistered one on a single unauthenticated POST — which is precisely
      // the oracle the identical shapes exist to close, left open by the code
      // asserting it was closed.
      //
      // Keep this object and the one at the end of the handler key-for-key
      // identical. If you add a field there, add it here in the same commit.
      return json({
        ok: true,
        lane,
        mailFailed,
        mailReason,
        manualFallback,
        supportEmail: SUPPORT_EMAIL,
        supportTelegram: SUPPORT_TELEGRAM,
        expiresInSeconds: EXPIRES_MINUTES * 60,
        resendAfterSeconds: 60,
      });
    }

    const code = generateCode();
    // A 32-byte token for the link, never the 6-digit code: a six-digit value
    // in a URL is trivially enumerated by anything that can walk query strings.
    const token = generateToken();

    // One live registration per address. Clearing first rather than upserting
    // because the uniqueness is enforced by a PARTIAL index
    // (WHERE consumed_at IS NULL), which ON CONFLICT cannot infer.
    await supabase.from("pending_registrations")
      .delete().eq("email_norm", email).is("consumed_at", null);

    const { error: insErr } = await supabase.from("pending_registrations").insert({
      email,
      // The password is encrypted, never stored plainly — see encryptSecret().
      // Everything else here is exactly the metadata auth.signUp used to send,
      // so handle_new_user() builds the profile identically and that trigger
      // needs no change.
      payload: {
        full_name: fullName,
        university_id: body.universityId ?? null,
        department: body.department ?? null,
        semester: body.semester ?? 1,
        account_type: accountType,
        gender: body.gender ?? null,
        program_id: body.programId ?? null,
        batch: body.batch ?? null,
        section: body.section ?? null,
        designation: body.designation ?? null,
        staff_category: body.staffCategory ?? null,
        office: body.office ?? null,
        enc_password: await encryptSecret(password),
      },
      code_hash: await hmac(code),
      token_hash: await hmac(token),
      expires_at: expiresAt.toISOString(),
      last_sent_at: new Date().toISOString(),
      ip_hash: await hmac(ip),
    });
    if (insErr) {
      console.error("[register-request] staging insert failed:", insErr.message);
      return json({ error: "Could not start registration. Please try again." }, 500);
    }

    // The link is deliberately SAFE TO PREFETCH. It opens the app at a route
    // that renders a confirm screen; the token is only spent when the app
    // POSTs to register-verify. This is the specific defect that breaks
    // password reset today: university mail runs link scanners which fetch
    // every URL in a message, and a GET that consumes a single-use token is
    // burned before the student ever clicks it.
    const confirmUrl = `${appOrigin()}/#/auth/verify?token=${encodeURIComponent(token)}`;

    // A MAIL FAILURE MUST NOT DESTROY THE SIGNUP.
    //
    // dispatch() throws on a permanent provider rejection, which is correct in
    // isolation — queueing an address the provider will never accept just
    // burns six attempts. But letting that throw escape HERE was severe:
    // the staged row above already exists, so the applicant's signup is
    // genuinely saved, and yet they got a 500 and never reached /auth/verify.
    // That is the one screen carrying the manual-approval escape hatch, so a
    // mail outage locked people out of the very route built for a mail outage.
    //
    // Measured 2026-08-17 against the live project: register-request returned
    // HTTP 500 with Resend's "You can only send testing emails to your own
    // email address" for every address but the account owner's. While
    // MAIL_FROM is the sandbox sender that is EVERY applicant, so this is the
    // normal path today, not an edge case.
    //
    // Now the response says the registration is staged and the mail is not
    // coming, and the client leads with the fallback instead of telling
    // someone to check an inbox nothing was sent to.
    let lane = "inline";
    let mailFailed = false;
    let mailReason: "quota" | "provider" | null = null;

    // ASK BEFORE PROMISING. The provider has a DAILY ceiling the app previously
    // knew nothing about, so it would send confidently past it and the
    // applicant would be told to check an inbox nothing could reach. Checking
    // first turns an invisible failure into a stated one, and the same call
    // raises the admin alert — deliberately one call, so the alert cannot be
    // forgotten by a caller that only wanted the boolean.
    const { data: budget } = await supabase.rpc("mail_check_and_alert");
    const canSend = !budget || budget[0]?.can_send !== false;

    if (!canSend) {
      mailFailed = true;
      mailReason = "quota";
      lane = "quota_exhausted";
      // Staged for a human instead of silently stranded. This is the same
      // queue register-review-request feeds, so the applicant appears in the
      // admin's existing review list rather than in a new place nobody checks.
      await supabase.from("pending_registrations")
        .update({
          review_state: "needs_review",
          review_reason: "Email quota exhausted — code could not be sent",
        })
        // `email`, matching the delete at the top of this handler — the value
        // is already normalised by the time it reaches here, and email_norm is
        // what the table keys on.
        .eq("email_norm", email)
        .is("consumed_at", null);
      console.error("[register-request] daily mail quota exhausted; staged for manual approval");
      // Staging without telling anyone is the same as not staging. See
      // alertStuckApplicant — this exact branch put a real applicant into a
      // queue nobody knew to open.
      await alertStuckApplicant(supabase, {
        email,
        name: fullName,
        role: accountType,
        reason: "The daily email limit was reached, so their code could not be sent.",
      });
    }

    // Skipped entirely when the quota is gone — not attempted and caught,
    // because there is nothing to attempt and a thrown-and-caught "error" would
    // report the wrong reason to the applicant.
    if (canSend) {
      try {
        lane = await dispatch(supabase, {
          to: email,
          template: "verify_account",
          payload: { fullName, code, actionUrl: confirmUrl, expiresMinutes: EXPIRES_MINUTES },
          // Collapses rage-taps inside the same 10-minute window into one send.
          dedupeKey: `verify:${email}:${Math.floor(Date.now() / 600_000)}`,
          priority: 1,
        });
      } catch (e) {
        console.error("[register-request] verification mail failed permanently:", e);
        mailFailed = true;
        mailReason = "provider";
        lane = "failed";
        // STAGE THEM, exactly as the quota path does.
        //
        // This was missing, and it stranded a real applicant. When the
        // provider rejects — an unverified sending domain, a refused address —
        // the signup is saved but the code can never arrive, and leaving
        // review_state at 'none' keeps them OUT of the admin queue, which
        // selects on 'needs_review'. So they were invisible: no mail, no
        // listing, and nothing to tell an admin they existed. The only way in
        // was for the applicant to notice the fallback and press it
        // themselves, which is a lot to ask of someone who has just been told
        // to check an inbox.
        //
        // Whether mail failed because of OUR quota or the PROVIDER makes no
        // difference to the person waiting; both mean a human has to finish
        // it. Only the copy they are shown differs.
        await supabase.from("pending_registrations")
          .update({
            review_state: "needs_review",
            review_reason: "Verification email was rejected by the mail provider",
          })
          .eq("email_norm", email)
          .is("consumed_at", null);
        // THE BRANCH THAT STRANDED A REAL PERSON. It staged her correctly and
        // then told nobody, and the "ask an administrator" button she pressed
        // afterwards was silently swallowed too. Both halves are fixed; this
        // is the half that should have fired first, without her having to do
        // anything at all.
        await alertStuckApplicant(supabase, {
          email,
          name: fullName,
          role: accountType,
          reason: "The mail provider rejected their verification email, so no code could be sent.",
        });
      }
    }

    return json({
      ok: true,
      lane,
      mailFailed,
      // WHY the mail is missing, not just THAT it is. The two cases need
      // different copy: a quota is ours and temporary ("we are sorry, this is
      // our end"), a provider rejection may be the address itself. Telling an
      // applicant to re-check their spelling when our allowance ran out is the
      // kind of small wrongness that makes people give up.
      mailReason,
      manualFallback,
      // Sent with the response rather than hardcoded in the app, so support
      // contacts can change without shipping a release to every phone.
      supportEmail: SUPPORT_EMAIL,
      supportTelegram: SUPPORT_TELEGRAM,
      expiresInSeconds: EXPIRES_MINUTES * 60,
      resendAfterSeconds: 60,
    });
  } catch (err) {
    console.error("[register-request]", err);
    return json({ error: (err as Error).message ?? "Registration failed." }, 500);
  }
});
