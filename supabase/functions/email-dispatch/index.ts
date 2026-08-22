import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders, json } from "../_shared/identity.ts";
import { type MailTemplate, sendRendered } from "../_shared/mailer.ts";

// Drains email_outbox — the overflow lane only.
//
// This is NOT how mail normally leaves the system. register-request and
// password-reset send inline and return in about a second; a row only reaches
// this worker when the per-minute provider budget was already spent, or when
// an inline attempt failed with a retryable error. So under normal load this
// function wakes up, finds nothing, and exits.
//
// Scheduled from pg_cron via pg_net once deployed:
//   select cron.schedule('drain-email-outbox', '* * * * *', $$
//     select net.http_post(
//       url := '<project>/functions/v1/email-dispatch',
//       headers := jsonb_build_object('Authorization', 'Bearer ' || '<service-role>')
//     ) $$);
//
// Runs every minute, and each invocation loops a few batches, so a backlog
// clears in roughly (depth / provider-rate) minutes rather than waiting a full
// minute per message.

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SERVICE_ROLE_KEY")!;

const BATCH = 20;
const MAX_BATCHES_PER_RUN = 5;

/// Exponential with a ceiling: 30s, 2m, 8m, 32m, capped at ~1h. A provider
/// outage therefore costs a handful of retries over an hour rather than six in
/// the first minute, which is what turns a blip into a hard failure.
function backoffSeconds(attempts: number): number {
  return Math.min(3600, 30 * Math.pow(4, Math.max(0, attempts - 1)));
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  // AUTHORISATION: the platform's verify_jwt is the gate, and that is enough
  // here — deliberately, after getting this wrong once.
  //
  // This originally demanded the service-role key. That made it uncallable by
  // pg_cron, because the established pattern in this project
  // (announce-pending-release) posts with the PUBLISHABLE key precisely so no
  // secret has to be stored in the database. A cron job carrying the service
  // key in cron.job.command would be a plaintext superuser credential sitting
  // in a table, which is worse than anything this check was protecting.
  //
  // Dropping to any-valid-project-JWT is safe because this endpoint grants no
  // capability: it drains rows the system already decided to send, to
  // addresses already fixed in those rows. A caller cannot inject a recipient,
  // cannot cause a message that was not already queued, and cannot double-send
  // — claim_email_batch takes each row FOR UPDATE SKIP LOCKED. The worst an
  // attacker achieves is delivering the queue slightly sooner.
  const auth = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!auth) {
    return json({ error: "Missing authorization." }, 401);
  }

  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE);
  let sent = 0, failed = 0, dropped = 0, scanned = 0;

  try {
    for (let b = 0; b < MAX_BATCHES_PER_RUN; b++) {
      // Atomic claim (FOR UPDATE SKIP LOCKED) so overlapping ticks cannot
      // both grab the same row and send a code twice.
      const { data: rows, error } = await supabase.rpc("claim_email_batch", { p_limit: BATCH });
      if (error) {
        console.error("[email-dispatch] claim failed:", error.message);
        return json({ error: error.message }, 500);
      }
      if (!rows || rows.length === 0) break;
      scanned += rows.length;

      for (const row of rows) {
        const result = await sendRendered(
          row.to_email,
          row.template as MailTemplate,
          row.payload ?? {},
        );

        if (result.ok) {
          await supabase.from("email_outbox").update({
            state: "sent",
            sent_at: new Date().toISOString(),
            provider: result.provider,
            provider_message_id: result.messageId ?? null,
            last_error: null,
          }).eq("id", row.id);
          sent++;
          continue;
        }

        // Permanent rejection, or out of attempts: stop retrying. Leaving a
        // dead address to burn six attempts every hour is how a small problem
        // becomes a quota problem.
        const exhausted = row.attempts >= row.max_attempts;
        if (result.retryable === false || exhausted) {
          await supabase.from("email_outbox").update({
            state: "dropped",
            provider: result.provider,
            last_error: result.error ?? "dropped",
          }).eq("id", row.id);
          dropped++;
          console.error(`[email-dispatch] dropped ${row.template} to ${row.to_email}: ${result.error}`);
          continue;
        }

        await supabase.from("email_outbox").update({
          state: "queued",
          send_after: new Date(Date.now() + backoffSeconds(row.attempts) * 1000).toISOString(),
          provider: result.provider,
          last_error: result.error ?? "retry",
        }).eq("id", row.id);
        failed++;
      }
    }

    return json({ ok: true, scanned, sent, requeued: failed, dropped });
  } catch (err) {
    console.error("[email-dispatch]", err);
    return json({ error: (err as Error).message }, 500);
  }
});
