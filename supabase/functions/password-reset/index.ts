import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  appOrigin,
  clientIp,
  consumeRateLimit,
  corsHeaders,
  generateCode,
  generateToken,
  hmac,
  json,
  normaliseEmail,
  safeEqual,
} from "../_shared/identity.ts";
import { dispatch } from "../_shared/mailer.ts";

// Password reset, rebuilt on the same rails as registration.
//
// THE TWO DEFECTS THIS FIXES, both confirmed against the live project:
//
//  1. It went through auth.resetPasswordForEmail, i.e. Supabase's built-in
//     mailer — capped in the single digits per hour and explicitly not for
//     production. During a rush, resets silently stop arriving.
//
//  2. It was LINK-ONLY and the link is GET-consumed. Institutional mail
//     (DIU included) runs link scanners that fetch every URL in a message to
//     check it for malware. That fetch spends the single-use recovery token,
//     so the student clicks and is told "link expired" on their FIRST attempt,
//     with no way to tell why. A typed code cannot be consumed by a scanner,
//     and the link here is only spent by an explicit POST from the app — a
//     prefetch just renders a screen.
//
//  POST { action: "request", email }
//  POST { action: "verify",  email, code, newPassword }
//  POST { action: "verify",  token, newPassword }

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SERVICE_ROLE_KEY")!;

const EXPIRES_MINUTES = 10;

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE);
    const body = await req.json().catch(() => ({}));
    const action = body.action === "verify" ? "verify" : "request";

    // ---------------------------------------------------------------- request
    if (action === "request") {
      const email = normaliseEmail(body.email);
      if (!email) return json({ error: "Enter your email address." }, 400);

      const ip = clientIp(req);
      if (!await consumeRateLimit(supabase, "email_verify_addr", email)) {
        return json({
          error: "A reset code was just sent to that address. Check your inbox before requesting another.",
        }, 429);
      }
      if (!await consumeRateLimit(supabase, "email_verify_ip", await hmac(ip))) {
        return json({ error: "Too many reset attempts from this device. Try again later." }, 429);
      }

      const { data: profile } = await supabase
        .from("profiles").select("id, full_name").eq("email", email).maybeSingle();

      // Same response whether or not the account exists. "No account with that
      // email" is a free membership oracle for anyone probing DIU addresses.
      const GENERIC = {
        ok: true,
        expiresInSeconds: EXPIRES_MINUTES * 60,
        resendAfterSeconds: 60,
      };
      if (!profile) return json(GENERIC);

      const code = generateCode();
      const token = generateToken();

      await supabase.from("pending_password_resets")
        .delete().eq("email_norm", email).is("consumed_at", null);

      const { error: insErr } = await supabase.from("pending_password_resets").insert({
        user_id: profile.id,
        email,
        code_hash: await hmac(code),
        token_hash: await hmac(token),
        expires_at: new Date(Date.now() + EXPIRES_MINUTES * 60_000).toISOString(),
        last_sent_at: new Date().toISOString(),
        ip_hash: await hmac(ip),
      });
      if (insErr) {
        console.error("[password-reset] staging failed:", insErr.message);
        return json(GENERIC); // still generic — never leak via error shape
      }

      // ASK BEFORE SENDING — the half of this that CAN be fixed here.
      //
      // register-request has checked the daily allowance since 20260902070000;
      // this endpoint never did, so a reset requested with the day's mail gone
      // sent nothing, told nobody, and alerted nobody. The applicant path at
      // least stages a human; this one had no equivalent.
      //
      // What cannot change: the caller still gets GENERIC either way. That
      // response is load-bearing anti-enumeration — it must be byte-identical
      // whether or not the account exists — so it cannot carry a "we couldn't
      // mail you" the way register-request's can. What CAN change is that
      // mail_check_and_alert() also raises the admin alert, and that half
      // leaks nothing at all.
      //
      // Returning instead of queueing is deliberate. dispatch() would now park
      // this in the outbox, but the daily bucket refills at capacity/1440 per
      // minute — about one token every fourteen minutes — while the code dies
      // in EXPIRES_MINUTES (10). A queued reset code therefore arrives already
      // expired, which is worse than not arriving: it looks like the system
      // works and wastes the one send it was saving up for.
      const { data: budget } = await supabase.rpc("mail_check_and_alert");
      if (budget?.[0]?.can_send === false) {
        console.error("[password-reset] daily mail allowance exhausted; reset code not sent");
        return json(GENERIC);
      }

      await dispatch(supabase, {
        to: email,
        template: "reset_password",
        payload: {
          fullName: profile.full_name,
          code,
          actionUrl: `${appOrigin()}/#/auth/reset?token=${encodeURIComponent(token)}`,
          expiresMinutes: EXPIRES_MINUTES,
        },
        dedupeKey: `reset:${email}:${Math.floor(Date.now() / 600_000)}`,
        priority: 1,
      }).catch((e) => console.error("[password-reset] dispatch failed:", e));

      return json(GENERIC);
    }

    // ----------------------------------------------------------------- verify
    const token = typeof body.token === "string" && body.token.length > 0 ? body.token : null;
    const email = normaliseEmail(body.email ?? "");
    const code = String(body.code ?? "").replace(/\D/g, "");
    const newPassword = String(body.newPassword ?? "");

    if (newPassword.length < 8) {
      return json({ error: "Password must be at least 8 characters." }, 400);
    }
    if (!token && (!email || code.length !== 6)) {
      return json({ error: "Enter the 6-digit code from your email." }, 400);
    }

    const attemptKey = token ? await hmac(token) : email;
    if (!await consumeRateLimit(supabase, "email_verify_attempt", attemptKey)) {
      return json({ error: "Too many attempts. Wait a few minutes and try again." }, 429);
    }

    const q = supabase.from("pending_password_resets").select("*").is("consumed_at", null);
    const { data: row } = token
      ? await q.eq("token_hash", await hmac(token)).maybeSingle()
      : await q.eq("email_norm", email).maybeSingle();

    const REJECT = "That code is invalid or has expired. Request a new one.";
    if (!row) return json({ error: REJECT }, 400);
    if (new Date(row.expires_at).getTime() < Date.now()) {
      return json({ error: "That code has expired. Request a new one." }, 400);
    }
    if (row.attempts >= row.max_attempts) {
      return json({ error: "Too many wrong attempts on this code. Request a new one." }, 429);
    }

    const supplied = token ? await hmac(token) : await hmac(code);
    const expected = token ? row.token_hash : row.code_hash;

    if (!safeEqual(supplied, expected)) {
      await supabase.from("pending_password_resets")
        .update({ attempts: row.attempts + 1 }).eq("id", row.id);
      return json({ error: REJECT, attemptsLeft: Math.max(0, row.max_attempts - row.attempts - 1) }, 400);
    }

    const { error: updErr } = await supabase.auth.admin.updateUserById(row.user_id, {
      password: newPassword,
    });
    if (updErr) {
      console.error("[password-reset] updateUserById failed:", updErr.message);
      return json({ error: "Could not update the password. Please try again." }, 500);
    }

    await supabase.from("pending_password_resets")
      .update({ consumed_at: new Date().toISOString() }).eq("id", row.id);

    // NOTE — session revocation. The old flow ran signOut(scope: global) from
    // the user's own recovery session, which killed sessions signed in with the
    // OLD password. That is not reproducible from here: the admin API has no
    // documented "revoke all refresh tokens for this user" call in supabase-js
    // v2, and GoTrue's own behaviour on an admin password change is not
    // something to assert without testing. Treat this as verified-open: after
    // deploying, change a password on a test account that is signed in
    // elsewhere and confirm the other session dies. If it does not, the fix is
    // a small SQL function that deletes that user's rows from auth.refresh_tokens.
    return json({ ok: true, email: row.email });
  } catch (err) {
    console.error("[password-reset]", err);
    return json({ error: (err as Error).message ?? "Reset failed." }, 500);
  }
});
