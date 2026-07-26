-- Archiving a course offering was a one-way trapdoor.
--
-- archive_course_offering() sets is_archived = true, and ELEVEN queries across
-- the app filter on is_archived = false: the teacher's class list for Results,
-- Attendance and Assignments, My Course Offerings, the student browse list,
-- course groups, the dashboard counts. So one tap on "End course" removes the
-- course from everywhere at once.
--
-- There was no way back. No restore RPC existed, and although
-- fetchMyArchivedOfferings() was written, no screen ever called it -- so an
-- archived offering became invisible with no trace and no undo, and the only
-- symptom was "the teacher can't see any of their courses" with nothing on
-- screen to explain why.
--
-- Live consequence that prompted this: both offerings on this project were
-- archived 70 seconds apart while someone was exploring the screen, and every
-- teacher- and student-facing list has been empty ever since.
--
-- Authorization mirrors archive_course_offering() exactly: the offering's own
-- teacher, an admin tier, or an explicit course_offerings:manage grant. If you
-- were allowed to end it, you are allowed to bring it back.
--
-- Verified live under SET LOCAL ROLE authenticated: a different teacher is
-- refused with insufficient_privilege, the owning teacher succeeds, and a
-- second call is a no-op rather than an error.

CREATE OR REPLACE FUNCTION restore_course_offering(p_offering_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE v_teacher_id uuid; v_archived boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING errcode='42501';
  END IF;

  SELECT teacher_id, is_archived INTO v_teacher_id, v_archived
  FROM course_offerings WHERE id = p_offering_id;

  IF v_teacher_id IS NULL AND v_archived IS NULL THEN
    RAISE EXCEPTION 'Offering not found';
  END IF;

  IF v_teacher_id IS DISTINCT FROM auth.uid()
     AND get_my_profile_role() NOT IN ('admin','dept_admin','super_admin')
     AND NOT caller_can('course_offerings','manage') THEN
    RAISE EXCEPTION 'Only the offering''s teacher or an admin can restore it'
      USING errcode='42501';
  END IF;

  -- Idempotent: restoring an already-live offering is a no-op rather than an
  -- error, so a double tap cannot surface as a failure.
  UPDATE course_offerings
     SET is_archived = false, archived_at = NULL
   WHERE id = p_offering_id AND is_archived = true;

  -- Deliberately does NOT recreate schedule_slots, which archive_course_
  -- offering() deleted. Offerings no longer carry meeting times at all (the
  -- class itself is the meeting), so approve_course_offering() generates zero
  -- slots for anything created since that change -- there is nothing to put
  -- back, and inventing slots here would publish times nobody entered.
END;
$fn$;

REVOKE ALL ON FUNCTION restore_course_offering(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION restore_course_offering(uuid) TO authenticated;
