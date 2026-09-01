-- Actually drain email_outbox. Nothing ever did.
--
-- THE BUG. Verification codes were never arriving, while registration reported
-- success. Both halves of that are working as designed, and together they lose
-- the mail:
--
--   1. mailer.ts fails SOFT. When the provider errors — including the plain
--      case of RESEND_API_KEY not being set, which returns
--      `ok:false, error:"RESEND_API_KEY not set"` — the message is written to
--      email_outbox instead of being dropped, and the caller is still told the
--      send was accepted. Its own comment says why: "from the user's side it
--      was, and it will arrive."
--
--   2. It did not arrive, because nothing drained the queue. The
--      email-dispatch function exists and is written for exactly this, and its
--      docstring even carries the schedule to install "once deployed" — that
--      step was never taken. Every other periodic job in this project is
--      scheduled (assignment reminders, club message expiry, rate-limit
--      pruning, avatar deadlines, release push). This one was not.
--
-- So every message that hit the overflow lane sat in a table forever, and a
-- user who could not receive their code had no way to know why.
--
-- AUTHORISATION: the PUBLISHABLE key, matching announce-pending-release
-- (20260804180927). email-dispatch documents this choice at length — a cron
-- job carrying the service-role key would put a plaintext superuser credential
-- in cron.job.command, which is worse than what the check would protect. The
-- endpoint grants no capability: it delivers rows the system already decided
-- to send, to addresses already fixed in those rows.
--
-- GUARDED, so this is one cheap index probe and NO HTTP call on the ~99.9% of
-- ticks with an empty queue — the same shape as the release job beside it.
-- Every minute rather than every five: this is someone standing on a
-- registration screen waiting for a code, not a background announcement.

-- Index the exact predicate the guard and the worker both use, so a growing
-- `sent` history never makes the every-minute probe expensive.
CREATE INDEX IF NOT EXISTS email_outbox_due_idx
  ON email_outbox (send_after)
  WHERE state = 'queued';

SELECT cron.unschedule('drain-email-outbox')
  WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'drain-email-outbox');

SELECT cron.schedule(
  'drain-email-outbox',
  '* * * * *',
  $cron$
  SELECT net.http_post(
    url := 'https://dtsptjallznnvattadlu.supabase.co/functions/v1/email-dispatch',
    body := '{}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer sb_publishable_x92WJ4FXzEVBTTY_9IKN5Q_0qK9qyuc'
    ),
    timeout_milliseconds := 20000
  )
  WHERE EXISTS (
    SELECT 1 FROM public.email_outbox
     WHERE state = 'queued'
       AND send_after <= now()
     LIMIT 1
  );
  $cron$
);

-- NOTE FOR WHOEVER READS THIS NEXT. Scheduling the drain makes queued mail
-- leave the building, but it does NOT fix a missing provider key: with no
-- RESEND_API_KEY the worker will fail each row, back off, and eventually mark
-- it 'failed' after max_attempts. If codes are still not arriving after this,
-- check in this order:
--   select state, count(*) from email_outbox group by state;
--   select to_email, state, attempts, last_error from email_outbox
--     order by created_at desc limit 20;
-- `last_error` names the cause directly. A row stuck at attempts = 0 in
-- 'queued' means the drain is not running; rows climbing attempts with a
-- provider error in last_error mean the key or the sending domain is the
-- problem, not this schedule.
