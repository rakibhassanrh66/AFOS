-- SEC-1: close anonymous access to RLS-bypassing SECURITY DEFINER RPCs.
--
-- Supabase's advisor flagged these as anon-executable. A role-simulated probe proved the
-- leak was real: `set local role anon; select count(*) from list_role_holders(...)` returned
-- every super_admin's profile UUID to a caller with no JWT at all, via
-- /rest/v1/rpc/list_role_holders.
--
-- The important detail is the ACL: every one of these carried `=X/postgres`, i.e. EXECUTE
-- granted to PUBLIC. Revoking from `anon` alone would have changed nothing, because anon
-- inherits EXECUTE through PUBLIC. Each revoke below therefore starts at PUBLIC.
--
-- Caller audit done before choosing what to keep (do not widen these back without redoing it):
--   list_role_holders        -> notification_service.dart:74      (authenticated)
--   list_section_students    -> grades_repository.dart:35,
--                               assignments_repository.dart:31    (authenticated)
--   find_section_cr          -> schedule_repository.dart:135      (authenticated)
--   get_hall_availability    -> hall_screen.dart:379              (authenticated)
--   calculate_semester_sgpa  -> no caller at all: no client, no cron, no edge function,
--                               no other function body references it
--   send_assignment_reminders / send_assignment_missed_notices
--                            -> pg_cron jobs 2 and 3, which run as `postgres`
--
-- So `authenticated` is retained only for the four the app actually calls; the other three
-- drop to service_role/postgres only. service_role is left untouched throughout.

-- ---------------------------------------------------------------------------
-- 1. Functions the app calls while logged in: revoke PUBLIC + anon, keep authenticated.
-- ---------------------------------------------------------------------------

revoke execute on function public.list_role_holders(text[]) from public;
revoke execute on function public.list_role_holders(text[]) from anon;

revoke execute on function public.list_section_students(text, text, text) from public;
revoke execute on function public.list_section_students(text, text, text) from anon;

revoke execute on function public.find_section_cr(text, text, text) from public;
revoke execute on function public.find_section_cr(text, text, text) from anon;

revoke execute on function public.get_hall_availability() from public;
revoke execute on function public.get_hall_availability() from anon;

-- ---------------------------------------------------------------------------
-- 2. Functions with no authenticated caller: revoke PUBLIC + anon + authenticated.
--    calculate_semester_sgpa is a WRITE (it updates SGPA), so anon reachability here was
--    worse than a read leak.
-- ---------------------------------------------------------------------------

revoke execute on function public.calculate_semester_sgpa(uuid, uuid) from public;
revoke execute on function public.calculate_semester_sgpa(uuid, uuid) from anon;
revoke execute on function public.calculate_semester_sgpa(uuid, uuid) from authenticated;

revoke execute on function public.send_assignment_reminders() from public;
revoke execute on function public.send_assignment_reminders() from anon;
revoke execute on function public.send_assignment_reminders() from authenticated;

revoke execute on function public.send_assignment_missed_notices() from public;
revoke execute on function public.send_assignment_missed_notices() from anon;
revoke execute on function public.send_assignment_missed_notices() from authenticated;

-- ---------------------------------------------------------------------------
-- 3. Defense in depth on the three PII-returning functions.
--
-- The revokes above are the actual fix, but a grant is not a durable guarantee: DROP +
-- CREATE (as opposed to CREATE OR REPLACE, which preserves the ACL) resets a function to
-- Supabase's default privileges, which include anon. An in-body guard survives that, so a
-- future migration that recreates one of these cannot silently reopen the leak.
--
-- Bodies are otherwise byte-identical to what is live today. get_hall_availability is
-- deliberately left alone: it is LANGUAGE sql and returns aggregate capacity only, so
-- converting it to plpgsql just to add a guard would be more risk than the exposure.
-- The cron-driven functions are also left unguarded on purpose -- pg_cron runs them as
-- `postgres`, where auth.uid() is null, so a guard would break the jobs.
-- ---------------------------------------------------------------------------

create or replace function public.list_role_holders(p_roles text[])
returns table(profile_id uuid)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY SELECT p.id FROM profiles p WHERE p.role = ANY(p_roles);
END;
$function$;

create or replace function public.list_section_students(
  p_department_code text, p_batch text, p_section text
)
returns table(id uuid, full_name text, university_id text)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT p.id, p.full_name, p.university_id
  FROM students s
  JOIN profiles p ON p.id = s.profile_id
  JOIN departments d ON d.id = s.department_id
  WHERE d.code = p_department_code
    AND s.batch_label = p_batch
    AND s.section = p_section
  ORDER BY p.full_name;
END;
$function$;

create or replace function public.find_section_cr(
  p_department_code text, p_batch text, p_section text
)
returns table(id uuid, full_name text)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT p.id, p.full_name
  FROM students s
  JOIN profiles p ON p.id = s.profile_id
  JOIN departments d ON d.id = s.department_id
  WHERE d.code = p_department_code
    AND s.batch_label = p_batch
    AND s.section = p_section
    AND s.is_cr = true
  LIMIT 1;
END;
$function$;

-- CREATE OR REPLACE preserves the ACL set above, but re-assert the intended grants so this
-- migration is correct regardless of the order a replay applies it in.
revoke execute on function public.list_role_holders(text[]) from public, anon;
revoke execute on function public.list_section_students(text, text, text) from public, anon;
revoke execute on function public.find_section_cr(text, text, text) from public, anon;

grant execute on function public.list_role_holders(text[]) to authenticated;
grant execute on function public.list_section_students(text, text, text) to authenticated;
grant execute on function public.find_section_cr(text, text, text) to authenticated;
