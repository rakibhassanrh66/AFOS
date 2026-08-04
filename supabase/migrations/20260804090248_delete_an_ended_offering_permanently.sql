-- Deleting an ended course for good.
--
-- "End course" archives: the offering stops appearing anywhere but the row, its
-- enrolments and its history survive, and Restore brings it back. That is the
-- right default and it is not what a teacher wants for a course created by
-- mistake — a typo'd section, a duplicate — which then sits in the Ended list
-- forever with no way to get rid of it.
--
-- WHY THIS NEEDS AN RPC RATHER THAN A DELETE FROM THE CLIENT.
-- The only DELETE policy a teacher has on course_offerings is
-- `teacher_delete_own_pending_offering`, which requires status = 'pending'. An
-- archived offering was approved, so a client-side delete matches zero rows and
-- reports success — a button that looks like it worked and did nothing.
--
-- WHAT IT REFUSES, AND WHY.
-- Deleting the row cascades to enrollments, course_offering_meetings,
-- course_messages, offering_result_submissions, schedule_slots, and
-- attendance_sessions -> attendance_records. Through enrollments it also
-- cascades to student_marks, and `marks` has no ON DELETE action at all so it
-- would abort the whole thing with a raw FK error partway.
--
-- So anything that amounts to an academic record blocks the delete outright:
-- marks of either kind, or a single attendance record. Those are the things
-- nobody can reconstruct, and a mistaken course does not have them. Enrolments
-- alone do NOT block — a course created by mistake collects sign-ups, and
-- refusing on those would defeat the point — but the count is returned so the
-- caller can say exactly how many people are being dropped before it happens.
--
-- It also refuses unless the offering is already archived. Ending it first is a
-- deliberate second step, and it means a live class with students in it can
-- never be destroyed by one tap.
--
-- ONE FK IS DELIBERATELY NOT CASCADE. `teaching_assignments.offering_id` is
-- ON DELETE SET NULL, so the module leader's allocation SURVIVES the delete and
-- goes back to being an accepted-but-unclaimed allocation. That is the outcome
-- we want: the teacher deleted a mistake, not the instruction to teach the
-- course, and they can create a fresh offering from that same allocation. A
-- cascade here would silently destroy the module leader's decision as well.

CREATE OR REPLACE FUNCTION delete_course_offering(p_offering_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_teacher_id  uuid;
  v_archived    boolean;
  v_code        text;
  v_enrolments  integer;
  v_marks       integer;
  v_attendance  integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING errcode = '42501';
  END IF;

  SELECT co.teacher_id, co.is_archived, c.code
    INTO v_teacher_id, v_archived, v_code
    FROM course_offerings co
    LEFT JOIN courses c ON c.id = co.course_id
   WHERE co.id = p_offering_id;

  IF v_teacher_id IS NULL AND v_archived IS NULL THEN
    RAISE EXCEPTION 'That course no longer exists';
  END IF;

  -- No `USING errcode` on purpose. friendlyError() replaces 42501 with the
  -- generic "You don't have permission to do that." and passes a bare RAISE
  -- (P0001) through verbatim, so attaching the SQLSTATE here would throw this
  -- sentence away and tell the user nothing about WHO can do it. Use a SQLSTATE
  -- only where the code has to be machine-distinguishable; this one does not.
  IF v_teacher_id IS DISTINCT FROM auth.uid()
     AND get_my_profile_role() NOT IN ('admin', 'dept_admin', 'super_admin')
     AND NOT caller_can('course_offerings', 'manage') THEN
    RAISE EXCEPTION 'Only the teacher who owns this course, or an admin, can delete it.';
  END IF;

  IF NOT COALESCE(v_archived, false) THEN
    RAISE EXCEPTION
      'End this course first. Only a course that has already ended can be deleted permanently.';
  END IF;

  SELECT count(*) INTO v_enrolments FROM enrollments WHERE offering_id = p_offering_id;

  SELECT (SELECT count(*) FROM student_marks sm
            JOIN enrollments e ON e.id = sm.enrollment_id
           WHERE e.offering_id = p_offering_id)
       + (SELECT count(*) FROM marks m
            JOIN enrollments e ON e.id = m.enrollment_id
           WHERE e.offering_id = p_offering_id)
    INTO v_marks;

  SELECT count(*) INTO v_attendance
    FROM attendance_records ar
    JOIN attendance_sessions s ON s.id = ar.session_id
   WHERE s.offering_id = p_offering_id;

  IF v_marks > 0 OR v_attendance > 0 THEN
    RAISE EXCEPTION
      '% has % mark(s) and % attendance record(s) against it. Deleting it would erase them for good, so it can only be left ended, not deleted.',
      COALESCE(v_code, 'This course'), v_marks, v_attendance;
  END IF;

  DELETE FROM course_offerings WHERE id = p_offering_id;

  RETURN COALESCE(v_enrolments, 0);
END;
$fn$;

REVOKE ALL ON FUNCTION delete_course_offering(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION delete_course_offering(uuid) TO authenticated;
