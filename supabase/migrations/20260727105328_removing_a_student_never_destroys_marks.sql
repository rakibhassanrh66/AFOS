-- Removing a student must never quietly delete work that was graded.
--
-- remove_course_enrollment() (20260727094328) DELETEs the enrolment row. Two
-- tables point at it, and they disagree about what that means:
--
--   student_marks.enrollment_id  ON DELETE CASCADE  -> per-component marks are
--                                                      silently destroyed.
--   marks.enrollment_id          (no action)        -> the delete fails with a
--                                                      raw FK violation, which
--                                                      friendlyError renders as
--                                                      "something it depends on
--                                                      is missing".
--
-- So the behaviour of "Remove" depended on which of the two tables happened to
-- hold rows: silent data loss, or an incomprehensible error. Both tables are
-- empty on this project today, which is exactly why the original verification
-- passed and proved nothing — this only bites once real marks exist.
--
-- Made deterministic and non-destructive: if anything has been graded, the
-- removal is refused and says so. The teacher's way through is to clear the
-- marks first, which is a deliberate act, or to archive the whole course. That
-- is a better default than either destroying a grade or emitting a FK error,
-- and it cannot be got wrong by accident.
--
-- Attendance is deliberately NOT touched and deliberately NOT blocking:
-- attendance_records is keyed by (session_id, student_id), not enrollment_id,
-- so it neither cascades nor blocks. It is the register — a factual record of
-- who was in the room — and it correctly outlives an enrolment. Note the
-- consequence: a student removed and later re-admitted keeps their earlier
-- attendance, and sync_attendance_marks() will count it again.

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
  v_graded      integer;
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

  SELECT (SELECT count(*) FROM student_marks sm WHERE sm.enrollment_id = p_enrollment_id)
       + (SELECT count(*) FROM marks m WHERE m.enrollment_id = p_enrollment_id)
    INTO v_graded;

  IF v_graded > 0 THEN
    RAISE EXCEPTION
      'This student has marks recorded for % — clear their marks first, or end the course instead. Removing them would delete graded work.',
      COALESCE(v_code, 'this course')
      USING errcode = '23514';
  END IF;

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
