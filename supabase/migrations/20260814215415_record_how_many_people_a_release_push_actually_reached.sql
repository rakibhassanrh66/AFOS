-- Make "did the release push actually reach anyone?" an answerable question.
--
-- WHY THIS EXISTS. `announce-release` already computes exactly the number
-- worth knowing -- it accumulates `targeted` from OneSignal's `recipients`,
-- and sets a `noSubscribers` flag when OneSignal recognised none of the
-- external_ids we sent. It then returns both in its HTTP response body.
--
-- Nobody ever reads that body. The function is invoked by `net.http_post`
-- from a trigger, so the response lands in pg_net's `net._http_response`
-- table, which is purged on a timer. Confirmed live while writing this: that
-- table is empty, and the outcome of the v2.7.8 push -- ten days old -- is
-- simply gone.
--
-- The cost of that is not hypothetical. `push_sent_at` records only that we
-- TRIED. Two states that matter enormously are indistinguishable through it:
--
--   * the push went to real devices, or
--   * OneSignal had no registered subscriber at all and it went nowhere
--
-- and the only difference between them is a number that gets deleted. So
-- "does push work?" has been answered from memory and guesswork rather than
-- from data, and answered inconsistently.
--
-- WHY A SEPARATE NULLABLE COLUMN RATHER THAN OVERLOADING push_sent_at.
-- Three states need distinguishing, not two:
--
--   push_recipients IS NULL  -- never recorded. Every release before this
--                               migration, plus any where the function has
--                               not run yet. Says nothing either way.
--   push_recipients = 0      -- it RAN, and confirmed nobody was subscribed.
--                               This is the state that should stop someone
--                               debugging the notification code for an hour.
--   push_recipients > 0      -- delivered, to this many devices.
--
-- Collapsing "unknown" into "zero" would be the same silent-failure shape
-- this column exists to remove.
--
-- The write is its own SECURITY DEFINER function rather than a direct UPDATE
-- so the edge function needs no table-level grant on app_releases, matching
-- claim_release_announcement and release_announcement_failed. Its ACL is
-- copied from those two exactly: service_role only, nothing for anon or
-- authenticated.

alter table public.app_releases
  add column if not exists push_recipients integer;

comment on column public.app_releases.push_recipients is
  'How many devices OneSignal reported the release push was delivered to. '
  'NULL = never recorded (pre-2026-08-15 releases, or the function has not run). '
  '0 = ran and confirmed nobody was subscribed. Distinguishing those two is the '
  'entire point of the column.';

create or replace function public.release_announcement_result(p_id uuid, p_recipients integer)
returns void
language sql
security definer
set search_path to 'public', 'pg_temp'
as $function$
  update public.app_releases
     set push_recipients = greatest(coalesce(p_recipients, 0), 0)
   where id = p_id;
$function$;

revoke all on function public.release_announcement_result(uuid, integer) from public;
revoke all on function public.release_announcement_result(uuid, integer) from anon;
revoke all on function public.release_announcement_result(uuid, integer) from authenticated;
grant execute on function public.release_announcement_result(uuid, integer) to service_role;
