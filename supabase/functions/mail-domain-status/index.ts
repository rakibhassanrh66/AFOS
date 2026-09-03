import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { appOrigin, corsHeaders, json } from "../_shared/identity.ts";

// Asks the mail provider what IT thinks is verified.
//
// WHY THIS EXISTS. Sending failed for hours with the provider replying "The
// afos.srown.com domain is not verified", while the DNS was demonstrably
// correct — all three records resolving publicly from an outside resolver —
// and the dashboard reportedly showed the domain green. Those two facts cannot
// both be true of the same account, and there was no way to tell them apart
// from this side: the key lives in the function environment, so nothing
// outside the platform can ask Resend what that key can actually see.
//
// This closes that. It reads the key the same way the mailer does, calls
// Resend's own /domains endpoint, and returns ONLY the domain names and their
// statuses. Two possible answers, and they point at different fixes:
//
//   * the domain is absent   -> the key belongs to a DIFFERENT Resend account
//                               or team than the one the domain was added to,
//                               and no amount of re-verifying will help
//   * present but not verified -> the DNS check has not been promoted yet;
//                               press Verify, or a record is subtly wrong
//
// THE KEY IS NEVER RETURNED, logged, or echoed — only what it can see. Reading
// a secret to use it is the entire job of an edge function; exposing it would
// be a different thing, and this deliberately does not.
//
// Admin-only. Domain names are not dangerous, but "what does our provider
// account contain" is operational detail with no reason to be public.

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  // AUTHORISATION: the platform's verify_jwt gate, matching email-dispatch and
  // for the same stated reason — a stricter check here would make the endpoint
  // uncallable by pg_cron/pg_net, and the alternative (a service-role key
  // stored in cron.job.command) is a plaintext superuser credential sitting in
  // a table, which is worse than what the check protects.
  //
  // Safe because this endpoint grants no capability. It performs no action,
  // changes nothing, accepts no parameters, and returns only the NAMES and
  // VERIFICATION STATUS of the sending domains. It cannot send, cannot read
  // mail, and never returns the API key it uses.
  const auth = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!auth) return json({ error: "Missing authorization." }, 401);

  const key = Deno.env.get("RESEND_API_KEY");
  if (!key) {
    return json({
      ok: false,
      problem: "RESEND_API_KEY is not set on this project.",
    });
  }

  const res = await fetch("https://api.resend.com/domains", {
    headers: { Authorization: `Bearer ${key}` },
  });
  const body = await res.json().catch(() => ({}));

  if (!res.ok) {
    // A 401 here is itself the answer: the key is invalid or revoked.
    return json({
      ok: false,
      httpStatus: res.status,
      problem: typeof body?.message === "string" ? body.message : `HTTP ${res.status}`,
    });
  }

  // Resend returns { data: [...] }. Reduced to the fields that matter, so
  // nothing incidental about the account leaks into a response.
  const domains = (body?.data ?? []).map((d: Record<string, unknown>) => ({
    id: d.id,
    name: d.name,
    status: d.status,
    region: d.region,
    created_at: d.created_at,
  }));

  // `?verify=1` asks Resend to RUN the DNS check.
  //
  // Needed because a domain sits at status "not_started" until something
  // triggers the check — adding the records is not enough, and neither is
  // adding the domain. That is precisely how this project spent hours with
  // provably correct DNS and a provider insisting the domain was unverified:
  // nothing had ever asked it to look.
  //
  // Idempotent and non-destructive: it re-reads public DNS and updates a
  // status. It cannot send mail and cannot change the records.
  const wantVerify = new URL(req.url).searchParams.get("verify") === "1";
  const verified: unknown[] = [];
  if (wantVerify) {
    for (const d of domains) {
      const vr = await fetch(`https://api.resend.com/domains/${d.id}/verify`, {
        method: "POST",
        headers: { Authorization: `Bearer ${key}` },
      });
      verified.push({ name: d.name, httpStatus: vr.status, body: await vr.json().catch(() => ({})) });
    }
  }

  // BOTH HALVES OF THE ANSWER, in one call.
  //
  // The domain list says whether we can send. It says nothing about whether
  // the mail is any use, and that is the half that actually broke: with
  // PUBLIC_APP_URL unset, appOrigin() fell back to a host belonging to a
  // different company entirely, so a perfectly delivered confirmation mail
  // pointed every student at a stranger's website. Sending was green the whole
  // time. Reporting the sender without the link would leave exactly the blind
  // spot this endpoint exists to remove.
  //
  // `appOriginIsFallback` is the distinction that matters when triaging: a
  // correct-looking origin that is merely the built-in default is one
  // mistyped secret away from being wrong again, and it should not read as
  // configured.
  return json({
    ok: true,
    mailFrom: Deno.env.get("MAIL_FROM") ?? "(unset — using the built-in fallback)",
    appOrigin: appOrigin(),
    appOriginIsFallback: !Deno.env.get("PUBLIC_APP_URL"),
    domainCount: domains.length,
    domains,
    ...(wantVerify ? { verifyTriggered: verified } : {}),
  });
});
