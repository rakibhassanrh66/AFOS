import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { notifyApprovers, resolveApprovers } from "../_shared/approvers.ts";
import {
  consumeRateLimit,
  corsHeaders,
  decryptSecret,
  hmac,
  json,
  normaliseEmail,
  safeEqual,
} from "../_shared/identity.ts";

// Step 2: redeem the proof and create the real account.
//
// BOTH REDEMPTION PATHS LAND HERE, on purpose — one row, one set of rules:
//   { email, code }  → the 6 digits typed into the app
//   { token }        → the link tapped in the mail
//
// The link is safe to prefetch. It opens the app at /auth/verify, which then
// POSTs here; the token is only spent by that POST. This is deliberate: the
// existing password-reset flow is link-only and GET-consumed, which is exactly
// what university mail scanners break — they fetch every URL in a message, so
// a single-use link is burned before the student ever clicks it.

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SERVICE_ROLE_KEY")!;

// Recipient resolution and delivery moved to ../_shared/approvers.ts when
// register-review-request needed the identical set. It fixes the same gap it
// always did: nothing had ever told management a new account appeared, because
// handle_new_user() writes the profile and stops and only the approve/reject
// direction was ever wired up.

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE);
    const body = await req.json().catch(() => ({}));

    const token = typeof body.token === "string" && body.token.length > 0 ? body.token : null;
    const email = normaliseEmail(body.email ?? "");
    const code = String(body.code ?? "").replace(/\D/g, "");

    if (!token && (!email || code.length !== 6)) {
      return json({ error: "Enter the 6-digit code from your email." }, 400);
    }

    // Throttles online guessing across rows, on top of the per-row attempt
    // counter below. Keyed by address for the code path, by token otherwise.
    const attemptKey = token ? await hmac(token) : email;
    if (!await consumeRateLimit(supabase, "email_verify_attempt", attemptKey)) {
      return json({ error: "Too many attempts. Wait a few minutes and try again." }, 429);
    }

    const query = supabase.from("pending_registrations").select("*").is("consumed_at", null);
    const { data: row } = token
      ? await query.eq("token_hash", await hmac(token)).maybeSingle()
      : await query.eq("email_norm", email).maybeSingle();

    // One message for "no such registration" and for "wrong code", so this
    // cannot be used to discover which addresses have a signup in flight.
    const REJECT = "That code is invalid or has expired. Request a new one.";
    if (!row) return json({ error: REJECT }, 400);

    // A code that expires or runs out of attempts is no longer a dead end. The
    // row is flagged so it surfaces in the admin review queue
    // (admin_list_stuck_registrations), which is the SECONDARY path: the code
    // settles almost everyone, and a human only looks at the ones it failed.
    // Before this, a stuck signup sat in a service-role-only table where
    // nobody could see it and the applicant had no route forward.
    const flagForReview = async (reason: string) => {
      await supabase.from("pending_registrations")
        .update({ review_state: "needs_review", review_reason: reason })
        .eq("id", row.id)
        .eq("review_state", "none");
    };

    if (new Date(row.expires_at).getTime() < Date.now()) {
      await flagForReview("Code expired before it was used");
      return json({
        error: "That code has expired. Request a new one, or ask AFOS support to approve your account manually.",
        underReview: true,
      }, 400);
    }
    if (row.attempts >= row.max_attempts) {
      await flagForReview("All code attempts used");
      return json({
        error: "Too many wrong attempts on this code. An administrator can now review and approve your account manually.",
        underReview: true,
      }, 429);
    }

    const supplied = token ? await hmac(token) : await hmac(code);
    const expected = token ? row.token_hash : row.code_hash;

    if (!safeEqual(supplied, expected)) {
      // Burning an attempt is the load-bearing brute-force defence: 5 tries
      // against a uniformly random 6-digit code is a 1-in-200,000 shot.
      const used = row.attempts + 1;
      await supabase.from("pending_registrations")
        .update({ attempts: used }).eq("id", row.id);
      const left = Math.max(0, row.max_attempts - used);
      if (left === 0) await flagForReview("All code attempts used");
      return json({
        error: left === 0
          ? "Too many wrong attempts. An administrator can now review and approve your account manually."
          : REJECT,
        attemptsLeft: left,
        underReview: left === 0,
      }, 400);
    }

    // ---- Proof accepted. Only now does a real account come into existence. ----
    const payload = row.payload ?? {};
    const { enc_password, ...metadata } = payload;
    let plainPassword: string;
    try {
      plainPassword = await decryptSecret(enc_password);
    } catch (_) {
      // AES-GCM is authenticated, so this means the ciphertext was tampered
      // with or the pepper changed. Either way the staged row is unusable.
      await supabase.from("pending_registrations").delete().eq("id", row.id);
      return json({ error: "This registration could not be completed. Please sign up again." }, 400);
    }

    const { data: created, error: createErr } = await supabase.auth.admin.createUser({
      email: row.email,
      password: plainPassword,
      // Pre-confirmed because the mailbox was just proven by this very code —
      // this is the ONLY path that may assert that.
      email_confirm: true,
      // Identical shape to what auth.signUp used to send, so handle_new_user()
      // builds profiles/students/teachers/staff exactly as before. That trigger
      // is deliberately unmodified.
      user_metadata: metadata,
    });

    if (createErr || !created?.user) {
      const msg = String(createErr?.message ?? "");
      if (/already/i.test(msg)) {
        await supabase.from("pending_registrations")
          .update({ consumed_at: new Date().toISOString() }).eq("id", row.id);
        return json({ error: "An account already exists for that address. Try signing in." }, 409);
      }
      console.error("[register-verify] createUser failed:", msg);
      return json({ error: "Could not create the account. Please try again." }, 500);
    }

    const userId = created.user.id;
    const accountType = String(metadata.account_type ?? "student");

    // Approval policy lives in app_config, not in code, so tightening
    // teacher/staff back to manual review is a one-row UPDATE.
    const { data: cfg } = await supabase
      .from("app_config").select("auto_approve_roles").eq("id", 1).maybeSingle();
    const autoRoles: string[] = cfg?.auto_approve_roles ?? ["student"];
    const autoApproved = autoRoles.includes(accountType);

    // identity_source records HOW this account was proven. It already existed
    // on profiles, defaulting to 'self', and had no writer — now it carries
    // real provenance an admin can see.
    await supabase.from("profiles").update({
      is_verified: autoApproved,
      identity_source: "diu_email",
    }).eq("id", userId);

    await supabase.from("pending_registrations")
      .update({ consumed_at: new Date().toISOString() }).eq("id", row.id);

    const name = String(metadata.full_name ?? row.email);
    await notifyApprovers(supabase, await resolveApprovers(supabase, userId), {
      title: autoApproved ? "New verified account" : "Account awaiting approval",
      body: autoApproved
        ? `${name} (${accountType}) confirmed their DIU address and can now sign in.`
        : `${name} (${accountType}) confirmed their DIU address and is waiting for approval.`,
      route: "/admin/users",
    });

    return json({
      ok: true,
      email: row.email,
      autoApproved,
      // The client signs in with the credentials it already holds rather than
      // this function minting a session — so the password is proven to work
      // before the user is told they are done.
      next: autoApproved ? "signin" : "pending_approval",
    });
  } catch (err) {
    console.error("[register-verify]", err);
    return json({ error: (err as Error).message ?? "Verification failed." }, 500);
  }
});
