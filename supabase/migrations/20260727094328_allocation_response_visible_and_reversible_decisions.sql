-- Three decisions that could be made but never unmade, and one that was made
-- invisible by a view nobody updated.
--
-- =====================================================================
-- 1. teaching_assignment_overview never learned about accept/decline.
-- =====================================================================
-- 20260726214619 added status / decline_reason / responded_at to the TABLE and
-- left the VIEW the module-leader screen actually reads untouched. So
-- `row['status']` came back NULL for every allocation, the Dart `?? 'pending'`
-- default swallowed it, and the leader's screen showed AWAITING TEACHER
-- forever -- for allocations that had been accepted, and for ones that had been
-- refused. The decline reason panel and the "this class is free, reassign it"
-- hint were unreachable code: they are gated on a value the view does not
-- return. The teacher's answer was written correctly every time and simply had
-- nowhere to arrive.
--
-- Confirmed against live data before writing this: the single CSE allocation
-- sits at status='pending' in the table, and `SELECT * FROM
-- teaching_assignment_overview` as the module leader returns no status column
-- at all.
--
-- Appended, not reordered: CREATE OR REPLACE VIEW requires the existing columns
-- keep their names, types and positions, and it preserves the grants that a
-- DROP/CREATE would silently discard.
CREATE OR REPLACE VIEW teaching_assignment_overview
WITH (security_invoker = true) AS
  SELECT ta.id,
         ta.department,
         ta.teacher_id,
         ta.course_code,
         ta.course_title,
         ta.course_type,
         ta.batch,
         ta.section,
         ta.semester,
         ta.note,
         ta.assigned_by,
         ta.assigned_at,
         ta.offering_id,
         p.full_name       AS teacher_name,
         p.teacher_initial,
         co.status         AS offering_status,
         -- everything below here is new
         ta.status,
         ta.decline_reason,
         ta.responded_at,
         co.is_archived    AS offering_is_archived,
         p.email           AS teacher_email
    FROM teaching_assignments ta
    JOIN profiles p ON p.id = ta.teacher_id
    LEFT JOIN course_offerings co ON co.id = ta.offering_id;

COMMENT ON VIEW teaching_assignment_overview IS
  'Module-leader view of a department''s teaching load. MUST expose every column the allocation card renders -- it silently lost status/decline_reason once already, and a missing column reads as a null default rather than an error, so the screen looks fine while showing the wrong state.';

-- =====================================================================
-- 2. A teacher could admit a student and never undo it.
-- =====================================================================
-- approve_course_join() pins every one of the offering's schedule_slots into
-- the student's routine. Nothing anywhere removed them again: enrollments has a
-- DELETE policy for the STUDENT withdrawing a pending request and one for
-- admins, and none at all for the teacher who owns the course. So admitting the
-- wrong person -- someone from another section, a duplicate request, a student
-- who dropped -- was permanent from the teacher's side, and the pinned classes
-- stayed on that student's routine for the rest of the term.
--
-- Deletes rather than introducing a 'removed' status: the enrolments status is
-- read by attendance, marks and the course group, and a fourth value would have
-- to be filtered out of every one of them. Deleting also leaves the student free
-- to apply again, which is the correct affordance when a removal was itself a
-- mistake. The student is told either way.
CREATE OR REPLACE FUNCTION remove_course_enrollment(
  p_enrollment_id uuid,
  p_reason text DEFAULT ''
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_student_id  uuid;
  v_offering_id uuid;
  v_teacher_id  uuid;
  v_code        text;
  v_section     text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING errcode = '42501';
  END IF;

  SELECT e.student_id, e.offering_id, co.teacher_id, c.code, co.section
    INTO v_student_id, v_offering_id, v_teacher_id, v_code, v_section
    FROM enrollments e
    JOIN course_offerings co ON co.id = e.offering_id
    LEFT JOIN courses c ON c.id = co.course_id
   WHERE e.id = p_enrollment_id;

  IF v_student_id IS NULL THEN
    RAISE EXCEPTION 'That enrolment no longer exists';
  END IF;

  IF v_teacher_id IS DISTINCT FROM auth.uid()
     AND get_my_profile_role() NOT IN ('admin', 'dept_admin', 'super_admin')
     AND NOT caller_can('enrollments', 'manage') THEN
    RAISE EXCEPTION 'Only the offering''s teacher or an admin can remove a student'
      USING errcode = '42501';
  END IF;

  -- The pins are the half that outlives the enrolment row. Scoped to this
  -- offering's slots and this student, so a student enrolled in several courses
  -- keeps the rest of their routine.
  DELETE FROM user_pinned_slots up
   USING schedule_slots ss
   WHERE up.schedule_slot_id = ss.id
     AND ss.course_offering_id = v_offering_id
     AND up.user_id = v_student_id;

  DELETE FROM enrollments WHERE id = p_enrollment_id;

  INSERT INTO user_notifications (user_id, title, body, category, deep_link_route)
  VALUES (
    v_student_id,
    'Removed from a course',
    COALESCE(v_code, 'A course') || ' (Section ' || COALESCE(v_section, '?') || ')'
      || ' — your teacher removed you from this class'
      || CASE WHEN COALESCE(btrim(p_reason), '') = ''
              THEN '. Ask them if you think this is a mistake.'
              ELSE ': ' || btrim(p_reason) END,
    'course_offering',
    '/schedule/browse-courses'
  );
END;
$fn$;

REVOKE ALL ON FUNCTION remove_course_enrollment(uuid, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION remove_course_enrollment(uuid, text) TO authenticated;

-- =====================================================================
-- 3. An admin could approve an offering and never take it back.
-- =====================================================================
-- Approving publishes schedule_slots and notifies a whole batch+section. The
-- admin screen's Reviewed tab was deliberately read-only because undoing it
-- means unpicking those generated rows -- but that left a mistaken approval
-- with no remedy at all except asking the teacher to archive their own course,
-- which is a different thing and reads to them as their fault.
--
-- This is the un-approval: it drops the generated routine rows (cascading every
-- enrolled student's pins the same way archive_course_offering does), returns
-- the offering to 'rejected' with a reason, and tells the teacher AND everyone
-- already enrolled -- who would otherwise just watch the course vanish.
--
-- Enrolment rows are kept. They are the record of who had joined, and restoring
-- the offering by approving it again makes them meaningful rather than needing
-- a data repair.
CREATE OR REPLACE FUNCTION revoke_course_offering(
  p_offering_id uuid,
  p_reason text DEFAULT ''
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_teacher_id uuid;
  v_status     text;
  v_code       text;
  v_section    text;
  v_dropped    integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING errcode = '42501';
  END IF;

  IF get_my_profile_role() NOT IN ('admin', 'dept_admin', 'super_admin')
     AND NOT caller_can('course_offerings', 'manage') THEN
    RAISE EXCEPTION 'Only an admin can withdraw an approval' USING errcode = '42501';
  END IF;

  SELECT co.teacher_id, co.status, c.code, co.section
    INTO v_teacher_id, v_status, v_code, v_section
    FROM course_offerings co
    LEFT JOIN courses c ON c.id = co.course_id
   WHERE co.id = p_offering_id;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Offering not found';
  END IF;
  IF v_status <> 'approved' THEN
    RAISE EXCEPTION 'Only an approved offering can have its approval withdrawn (this one is %)', v_status
      USING errcode = '23514';
  END IF;

  DELETE FROM schedule_slots WHERE course_offering_id = p_offering_id;
  GET DIAGNOSTICS v_dropped = ROW_COUNT;

  UPDATE course_offerings
     SET status            = 'rejected',
         reviewed_by       = auth.uid(),
         reviewed_at       = now(),
         rejection_reason  = NULLIF(btrim(p_reason), '')
   WHERE id = p_offering_id;

  -- The teacher, then everyone who had already been admitted. Both need to know:
  -- the course disappears from the routine for all of them at the same instant.
  INSERT INTO user_notifications (user_id, title, body, category, deep_link_route)
  VALUES (
    v_teacher_id,
    'Course offering approval withdrawn',
    COALESCE(v_code, 'Your course') || ' (Section ' || COALESCE(v_section, '?') || ')'
      || ' has been taken off the schedule by an admin'
      || CASE WHEN COALESCE(btrim(p_reason), '') = '' THEN '.' ELSE ': ' || btrim(p_reason) END,
    'course_offering',
    '/schedule/my-offerings'
  );

  INSERT INTO user_notifications (user_id, title, body, category, deep_link_route)
  SELECT e.student_id,
         'A course was withdrawn',
         COALESCE(v_code, 'A course') || ' (Section ' || COALESCE(v_section, '?') || ')'
           || ' is no longer running and has been removed from your routine.',
         'course_offering',
         '/schedule/browse-courses'
    FROM enrollments e
   WHERE e.offering_id = p_offering_id
     AND e.status = 'approved';

  RETURN v_dropped;
END;
$fn$;

REVOKE ALL ON FUNCTION revoke_course_offering(uuid, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION revoke_course_offering(uuid, text) TO authenticated;
