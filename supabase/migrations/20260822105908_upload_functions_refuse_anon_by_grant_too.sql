-- CI (.github/scripts/check_definer_acls.py) failed on the uploads work:
-- all 7 SECURITY DEFINER upload functions were executable by `anon`.
--
-- The uploads migrations DID say `revoke all ... from anon`. That is not
-- enough: Postgres grants EXECUTE to PUBLIC on every newly created function,
-- and revoking `anon` leaves the PUBLIC grant standing -- anon is a member of
-- PUBLIC, so it keeps the privilege by another route. The grant only shows up
-- in pg_proc.proacl with grantee 0, which is easy to miss when a check joins
-- to pg_roles and drops the NULL -- that is exactly how the first review of
-- these grants read them as clean.
--
-- This is the same finding as commit 8620a72 ("Console facets refuse anon by
-- grant, not by accident"), reintroduced. Each function still checks
-- can_manage_uploads() internally, so anon could not actually have written a
-- batch -- but the audit's rule is that authorisation is a grant, not a
-- function body, and it is right.
revoke all on function can_manage_uploads() from public, anon;
revoke all on function record_upload_batch(text, text, text, uuid, text) from public, anon;
revoke all on function finalize_upload_batch(uuid, jsonb) from public, anon;
revoke all on function revert_upload_batch(uuid) from public, anon;
revoke all on function upload_batch_contents(uuid) from public, anon;
revoke all on function list_upload_batches(integer) from public, anon;
revoke all on function mark_upload_backup_generated(uuid, text) from public, anon;

grant execute on function can_manage_uploads() to authenticated;
grant execute on function record_upload_batch(text, text, text, uuid, text) to authenticated;
grant execute on function finalize_upload_batch(uuid, jsonb) to authenticated;
grant execute on function revert_upload_batch(uuid) to authenticated;
grant execute on function upload_batch_contents(uuid) to authenticated;
grant execute on function list_upload_batches(integer) to authenticated;
grant execute on function mark_upload_backup_generated(uuid, text) to authenticated;

-- Same default applies to everything added today.
revoke all on function profile_search_text(text,text,text,text,text,text,text) from public, anon;
revoke all on function profile_is_complete(profiles) from public, anon;
grant execute on function profile_search_text(text,text,text,text,text,text,text) to authenticated;
grant execute on function profile_is_complete(profiles) to authenticated;
