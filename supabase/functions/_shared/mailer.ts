// Transactional mail dispatch.
//
// THE LOAD PROBLEM, AND WHY THIS IS SHAPED THE WAY IT IS
// ------------------------------------------------------
// Supabase's built-in mailer is capped in the single digits per hour and is
// explicitly not for production, so it is replaced outright rather than worked
// around. But swapping in a bigger provider only raises a ceiling — it does
// nothing about the shape of the load, which at a university is not a steady
// trickle. It is ~nothing for months and then every first-year in the faculty
// registering inside the same 48 hours.
//
// Three mechanisms, in the order they do the most good:
//
//  1. CUT THE VOLUME. `dedupeKey` collapses repeat sends for the same address
//     and purpose inside a time window, so five rage-taps on "Resend" cost one
//     email, not five. Nothing else in the system is allowed to send mail at
//     all — every other notification goes out over OneSignal push, which has
//     no such cap. Mail is reserved for exactly two jobs: prove a mailbox, and
//     recover a password.
//
//  2. TWO LANES, NOT A QUEUE. A plain queue would add latency to every user in
//     order to survive a burst that happens twice a year. Instead the hot lane
//     sends inline and returns (~1s), and only when the per-minute provider
//     budget is already spent does the message divert to email_outbox for a
//     worker to drain. The common case never touches the queue; the burst case
//     degrades into a short wait instead of a failure.
//
//  3. FAIL SOFT, NEVER SILENTLY. If the provider errors, the message is
//     enqueued with backoff rather than dropped, and the caller is still told
//     the send was accepted — because from the user's side it was, and it will
//     arrive. What is never done is telling them it was sent when it was lost.

import {
  accountExistsEmail,
  passwordResetEmail,
  type RenderedMail,
  verificationEmail,
} from "./email_templates.ts";

export type MailTemplate = "verify_account" | "reset_password" | "account_exists";

export interface MailPayload {
  fullName?: string | null;
  code?: string;
  actionUrl?: string;
  loginUrl?: string;
  expiresMinutes?: number;
}

export function renderTemplate(template: MailTemplate, p: MailPayload): RenderedMail {
  switch (template) {
    case "verify_account":
      return verificationEmail({
        fullName: p.fullName,
        code: p.code!,
        actionUrl: p.actionUrl!,
        expiresMinutes: p.expiresMinutes ?? 10,
      });
    case "reset_password":
      return passwordResetEmail({
        fullName: p.fullName,
        code: p.code!,
        actionUrl: p.actionUrl!,
        expiresMinutes: p.expiresMinutes ?? 10,
      });
    case "account_exists":
      return accountExistsEmail({ fullName: p.fullName, loginUrl: p.loginUrl! });
  }
}

function mailFrom(): string {
  // Must be an address on a domain verified with the provider, or every
  // message is rejected at the API. Kept in env so changing the sending domain
  // never needs a redeploy.
  return Deno.env.get("MAIL_FROM") ?? "AFOS <no-reply@afos.app>";
}

export interface ProviderResult {
  ok: boolean;
  provider: string;
  messageId?: string;
  error?: string;
  /// True when retrying later could plausibly succeed (5xx, network, 429).
  /// A 4xx for a malformed address is NOT retryable and must not sit in the
  /// outbox burning attempts forever.
  retryable?: boolean;
}

/// Resend adapter. Deliberately behind this interface so SES or Brevo can be
/// added as a second lane later without touching any caller — the failover
/// story is "more legitimately-held provider budget", not "evade a limit".
async function sendViaResend(to: string, mail: RenderedMail): Promise<ProviderResult> {
  const key = Deno.env.get("RESEND_API_KEY");
  if (!key) {
    return {
      ok: false,
      provider: "resend",
      error: "RESEND_API_KEY not set — run: supabase secrets set RESEND_API_KEY=...",
      retryable: true,
    };
  }
  try {
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { "Authorization": `Bearer ${key}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        from: mailFrom(),
        to: [to],
        subject: mail.subject,
        html: mail.html,
        text: mail.text,
      }),
    });
    const body = await res.json().catch(() => ({}));
    if (res.ok) return { ok: true, provider: "resend", messageId: body?.id };
    return {
      ok: false,
      provider: "resend",
      error: typeof body?.message === "string" ? body.message : `HTTP ${res.status}`,
      retryable: res.status === 429 || res.status >= 500,
    };
  } catch (e) {
    return { ok: false, provider: "resend", error: String(e), retryable: true };
  }
}

export interface DispatchInput {
  to: string;
  template: MailTemplate;
  payload: MailPayload;
  /// Collapses duplicate sends. Omit only for mail that must always go.
  dedupeKey?: string;
  priority?: number;
}

export type DispatchLane = "inline" | "queued" | "deduped";

/// Enqueue without attempting an inline send. Used by the overflow path and by
/// callers that explicitly want the worker to own delivery.
// deno-lint-ignore no-explicit-any
async function enqueue(supabase: any, i: DispatchInput, sendAfter = new Date()): Promise<DispatchLane> {
  const { error } = await supabase.from("email_outbox").insert({
    to_email: i.to,
    template: i.template,
    payload: i.payload,
    dedupe_key: i.dedupeKey ?? null,
    priority: i.priority ?? 5,
    send_after: sendAfter.toISOString(),
  });
  // 23505 = unique violation on email_outbox_dedupe_idx: an identical message
  // is already queued. That is a success, not an error — it is the dedupe
  // doing its job.
  if (error && error.code === "23505") return "deduped";
  if (error) throw new Error(`Could not queue mail: ${error.message}`);
  return "queued";
}

/// The hot path. Returns which lane carried the message so the caller can
/// adjust the copy it shows ("check your inbox" vs "we'll ping you when it
/// lands"), but never fails the user's request over a provider hiccup.
// deno-lint-ignore no-explicit-any
export async function dispatch(supabase: any, i: DispatchInput): Promise<DispatchLane> {
  // Provider budget is itself a token bucket, keyed globally rather than per
  // user — it models "how many can Resend take from us this minute", which is
  // a property of the account, not of the caller.
  const { data: hasBudget, error: budgetErr } = await supabase.rpc("consume_rate_limit", {
    p_bucket: "email_provider_resend",
    p_key: "global",
    p_cost: 1,
  });

  // Budget spent (or the limiter is unavailable) → straight to the queue.
  if (budgetErr || hasBudget === false) return await enqueue(supabase, i);

  const mail = renderTemplate(i.template, i.payload);
  const result = await sendViaResend(i.to, mail);
  if (result.ok) return "inline";

  console.error(`[mailer] inline send failed (${result.error}) — queueing`);
  if (result.retryable === false) {
    // Permanent rejection. Queueing would just burn six attempts against an
    // address the provider will never accept.
    throw new Error(`That address was rejected by the mail provider: ${result.error}`);
  }
  return await enqueue(supabase, i, new Date(Date.now() + 5_000));
}

/// Used by the drain worker. Separate from dispatch() because the worker has
/// already claimed the row and must not re-check the budget through the same
/// path (it paces itself by batch size instead).
export async function sendRendered(to: string, template: MailTemplate, payload: MailPayload) {
  return await sendViaResend(to, renderTemplate(template, payload));
}
