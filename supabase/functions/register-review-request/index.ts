import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { notifyApprovers, resolveApprovers } from "../_shared/approvers.ts";
import {
  clientIp,
  consumeRateLimit,
  corsHeaders,
  hmac,
  json,
  normaliseEmail,
} from "../_shared/identity.ts";

// THE APPLICANT RAISES THEIR OWN HAND.
//
// The manual-approval path already existed, but it could only be ENTERED BY
// FAILING AT THE CODE — register-verify flags a row 'needs_review' when the
// code expires or burns all five attempts. Someone who never received a mail
// at all can do neither: you cannot exhaust attempts on a code you do not
// have. They waited out the ten minutes and had no route forward and no
// presence in any queue, so no administrator could even know they existed.
//
// That is the common case right now, not the edge case: MAIL_FROM is still
// Resend's sandbox sender, which delivers only to the Resend account owner.
//
// This endpoint writes NOTHING but review_state on an already-staged row. It
// creates no account, grants nothing, and cannot approve anybody — approval
// stays in register-admin-approve behind can_browse_users(). All this does is
// make a stuck applicant visible to the people who can decide.

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SERVICE_ROLE_KEY")!;

const REASON = "Applicant reported the email never arrived";

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE);
    const body = await req.json().catch(() => ({}));
    const email = normaliseEmail(body.email ?? "");

    if (!email) return json({ error: "Enter the email address you signed up with." }, 400);

    // select("*") rather than naming the column: this function is deployable
    // before 20260817120000 is applied, and PostgREST errors on a column that
    // does not exist yet. Missing column reads as "fallback available", which
    // is the safe default — the worst case is offering a button that raises a
    // row nobody looks at, versus hiding the only route a stuck person has.
    const { data: cfg } = await supabase
      .from("app_config").select("*").eq("id", 1).maybeSingle();
    if (cfg?.manual_approval_fallback === false) {
      return json({
        error: "Manual approval isn't available right now. Ask for a new code and check your spam folder.",
      }, 503);
    }

    // The address bucket does not exist until the migration lands, and
    // consume_rate_limit() ALLOWS an unknown bucket. That is why the IP check
    // below uses email_verify_ip, which already exists — so this endpoint is
    // rate-limited on at least one axis from the moment it is deployed.
    if (!await consumeRateLimit(supabase, "registration_review_request", email)) {
      return json({
        error: "You've already asked for manual approval. Someone will look at it — asking again won't make it faster.",
      }, 429);
    }
    if (!await consumeRateLimit(supabase, "email_verify_ip", await hmac(clientIp(req)))) {
      return json({ error: "Too many requests from this device. Try again later." }, 429);
    }

    // NOT filtered on expires_at. An expired code is the single most likely
    // reason someone is here, so refusing expired rows would reject almost
    // everyone this exists for.
    const { data: row } = await supabase
      .from("pending_registrations")
      .select("id, email, review_state, payload")
      .eq("email_norm", email)
      .is("consumed_at", null)
      .maybeSingle();

    // ANTI-ENUMERATION. Identical success shape whether or not a signup is in
    // flight, exactly as register-request and password-reset do. Otherwise
    // this becomes a cheap oracle for "which DIU addresses have a signup
    // pending", and it is reachable without a session.
    const OK = json({ ok: true });
    if (!row) return OK;

    // A declined applicant does not get to re-queue themselves by pressing a
    // button; a decision was made by a named person. Registering again is the
    // route, and that path is unaffected.
    if (row.review_state === "rejected") return OK;

    // Idempotent: pressing twice must not produce two queue entries or two
    // notifications. The guard is the WHERE on review_state, not a read —
    // concurrent presses would both pass a read.
    const { data: updated } = await supabase
      .from("pending_registrations")
      .update({ review_state: "needs_review", review_reason: REASON })
      .eq("id", row.id)
      .eq("review_state", "none")
      .select("id");

    if (!updated || updated.length === 0) return OK;

    const payload = row.payload ?? {};
    const name = String(payload.full_name ?? row.email);
    const role = String(payload.account_type ?? "student");

    const ids = await resolveApprovers(supabase);
    await notifyApprovers(supabase, ids, {
      title: "Someone can't receive their code",
      // Says plainly what the approver is being asked to judge. They are NOT
      // being told this person is verified — nobody has proved anything here,
      // and the review screen repeats that before they can act.
      body: `${name} (${role}) signed up as ${row.email} but never received the email. They've asked for manual approval.`,
      route: "/admin/users",
    });

    return OK;
  } catch (err) {
    console.error("[register-review-request]", err);
    return json({ error: (err as Error).message ?? "Could not send that request." }, 500);
  }
});
