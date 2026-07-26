-- SEC-1 round 2: the first pass fixed only the 7 functions the earlier audit had
-- listed. Recomputing the set from scratch (SECURITY DEFINER, non-trigger return
-- type, anon holds EXECUTE) found 11 MORE. The earlier "28 flagged -> 8 real"
-- filter was simply incomplete; it should not be trusted again.
--
-- Two of them were worse than an exposure -- they had a guard that does not hold:
--
--   IF NOT EXISTS (... member_id = auth.uid() ... )
--      AND get_my_profile_role() <> 'super_admin' THEN RAISE ...
--
-- For anon, auth.uid() is NULL so NOT EXISTS is TRUE, and get_my_profile_role()
-- returns NULL so `NULL <> 'super_admin'` is NULL. TRUE AND NULL = NULL, and
-- `IF NULL THEN` does not fire -- so the RAISE is skipped and execution falls
-- through to the UPDATE/INSERT. Verified by probe, not inferred:
--   anon get_my_profile_role=NULL; club guard IF-expr=NULL
-- It is not exploitable this instant only because there are currently zero
-- pending club requests, so the earlier "Request not found" RAISE catches first.
-- That is the same "empty data hides the defect" trap the original audit called
-- out for list_section_students -- absence of data is not a control.
--
-- approve_grade_change was checked the same way and is genuinely safe:
-- has_permission() returns false (not NULL) for anon, so `NOT false` fires the
-- RAISE. It is still revoked below on principle -- anon has no business reaching
-- a write path at all.
--
-- A scan for the same null-unsafe comparison across every function body found
-- exactly these two; the pattern is not more widespread.

-- ---------------------------------------------------------------------------
-- 1. Revoke PUBLIC + anon. Note PUBLIC first: `=X/postgres` in the ACL means
--    EXECUTE is granted to PUBLIC, which anon inherits, so revoking anon alone
--    is a no-op. Same trap as round 1.
--    `authenticated` is retained -- every one of these has a real logged-in
--    caller (clubs_screen, manage_exam_seats_screen, vr_id_screen,
--    grade_change_repository) or is an RLS helper used by policies.
-- ---------------------------------------------------------------------------

revoke execute on function public.approve_club_membership_request(uuid) from public, anon;
revoke execute on function public.reject_club_membership_request(uuid, text) from public, anon;
revoke execute on function public.approve_grade_change(uuid) from public, anon;
revoke execute on function public.caller_can(text, text, uuid) from public, anon;
revoke execute on function public.has_permission(text, text, text) from public, anon;
revoke execute on function public.list_exam_candidates(uuid) from public, anon;
revoke execute on function public.list_students_by_batch_section(text, text) from public, anon;
revoke execute on function public.my_capabilities() from public, anon;
revoke execute on function public.verify_vr_id_scan(uuid, text, bigint) from public, anon;

-- log_audit has no client caller and no authenticated caller: its only caller is
-- handle_new_user, which is SECURITY DEFINER, so the call is privilege-checked
-- against the function OWNER (postgres), not the invoking role. Dropping it to
-- owner/service_role only therefore cannot break signup. Left reachable by anon
-- it let an unauthenticated caller forge audit_log rows with a NULL changed_by.
revoke execute on function
  public.log_audit(text, uuid, text, jsonb, jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. DELIBERATELY NOT TOUCHED: get_my_profile_role()
--
-- It is referenced by 32 RLS policies, 27 of which are reachable by anon. A
-- policy expression is privilege-checked against the querying role, so revoking
-- anon's EXECUTE would make those policies error out and break anonymous reads
-- app-wide. The security gain would be zero: for anon the function returns NULL
-- (proven by probe) and it only ever reports the CALLER's own role, so there is
-- nothing to leak. Left exactly as it is, on purpose.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 3. Repair the fail-open guard.
--
-- `IS DISTINCT FROM` is the null-safe comparison: NULL IS DISTINCT FROM
-- 'super_admin' is TRUE, so a caller with no resolvable role now takes the
-- RAISE branch instead of falling through it. An explicit auth.uid() check is
-- added first so the failure is unambiguous rather than depending on the
-- three-valued logic reading correctly.
--
-- Bodies are otherwise identical to what is live.
-- ---------------------------------------------------------------------------

create or replace function public.approve_club_membership_request(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
DECLARE
  v_club_id uuid;
  v_student_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT club_id, student_id INTO v_club_id, v_student_id
  FROM club_membership_requests WHERE id = p_request_id AND status = 'pending';

  IF v_club_id IS NULL THEN
    RAISE EXCEPTION 'Request not found or already reviewed';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM club_members
                 WHERE club_id = v_club_id AND member_id = auth.uid() AND role = 'president')
     AND get_my_profile_role() IS DISTINCT FROM 'super_admin' THEN
    RAISE EXCEPTION 'Only the club president or super_admin can approve this request';
  END IF;

  UPDATE club_membership_requests
    SET status = 'approved', reviewed_by = auth.uid(), reviewed_at = now()
    WHERE id = p_request_id;

  INSERT INTO club_members (club_id, member_id, role)
    VALUES (v_club_id, v_student_id, 'member')
    ON CONFLICT (club_id, member_id) DO NOTHING;
END;
$function$;

create or replace function public.reject_club_membership_request(
  p_request_id uuid, p_reason text default null::text
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
DECLARE
  v_club_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT club_id INTO v_club_id
  FROM club_membership_requests WHERE id = p_request_id AND status = 'pending';

  IF v_club_id IS NULL THEN
    RAISE EXCEPTION 'Request not found or already reviewed';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM club_members
                 WHERE club_id = v_club_id AND member_id = auth.uid() AND role = 'president')
     AND get_my_profile_role() IS DISTINCT FROM 'super_admin' THEN
    RAISE EXCEPTION 'Only the club president or super_admin can reject this request';
  END IF;

  UPDATE club_membership_requests
    SET status = 'rejected', rejection_reason = p_reason, reviewed_by = auth.uid(), reviewed_at = now()
    WHERE id = p_request_id;
END;
$function$;

-- CREATE OR REPLACE preserves the ACL, but re-assert so a replay in any order
-- lands in the intended state.
revoke execute on function public.approve_club_membership_request(uuid) from public, anon;
revoke execute on function public.reject_club_membership_request(uuid, text) from public, anon;
grant execute on function public.approve_club_membership_request(uuid) to authenticated;
grant execute on function public.reject_club_membership_request(uuid, text) to authenticated;
