-- =====================================================================
--  Take anon back off the advising functions.
--
--  `revoke all ... from public` does NOT remove anon's access here, which is
--  the trap: Supabase's default privileges grant EXECUTE to `anon` and
--  `authenticated` EXPLICITLY, so revoking the `public` pseudo-role leaves the
--  explicit grant standing and the function stays reachable at
--  /rest/v1/rpc/<name> with no session at all.
--
--  Caught by the security advisor rather than by reading the grants: before
--  this migration the project reported six anon_security_definer_function_
--  executable notices and all six were functions the previous migration had
--  just added. After it, one remains — `get_my_profile_role()`, which predates
--  this work and is left alone here rather than fixed in passing.
--
--  Signed out, nobody should be able to resolve a teacher initial: that call
--  answers "does this initial exist, and who is it" and would be a faculty
--  directory enumeration endpoint.
-- =====================================================================

revoke all on function public.resolve_teacher_initial(text) from anon;
revoke all on function public.student_profile_for_link(uuid) from anon;
revoke all on function public.request_teacher_link(text, text) from anon;
revoke all on function public.decide_teacher_link(uuid, boolean, text) from anon;

-- A trigger function is invoked by its trigger, never called over the API, so
-- it needs no EXECUTE grant to any client role at all.
revoke all on function public.tg_teacher_links_guard() from anon;
revoke all on function public.tg_teacher_links_guard() from authenticated;
revoke all on function public.tg_teacher_links_guard() from public;
