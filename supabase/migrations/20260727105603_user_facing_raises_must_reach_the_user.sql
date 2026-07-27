-- Six deliberately-written error messages that no user has ever seen.
--
-- friendlyError() already draws the right distinction, and says so in its own
-- comment: Postgres's integrity errors are suppressed because they leak schema
-- names, but "this project's SECURITY DEFINER RPCs deliberately RAISE
-- human-written messages ... and plpgsql reports those as P0001. Those are
-- worth showing." The passthrough is `if (err.code == 'P0001') return
-- err.message;`.
--
-- P0001 is what a bare `RAISE EXCEPTION` produces. Adding `USING errcode =
-- '23514'` opts OUT of that passthrough and into the generic branch, so every
-- one of these carefully worded sentences reached the user as:
--
--     "Some of that information isn't in a valid format — please check it and
--      try again."
--
-- which is wrong for all six and actively unhelpful for most. A teacher told
-- that, after tapping Remove on a student who has been graded, learns nothing
-- and has no idea what to do next.
--
-- The 42501 raises are deliberately left alone: those map to "You don't have
-- permission to do that", which is accurate, and the specific wording is not
-- something the user can act on anyway.
--
-- Rule for this project: a RAISE whose message is written FOR the user gets no
-- USING errcode. Reach for a SQLSTATE only when the code itself has to be
-- machine-distinguishable.

-- 1. Removing a graded student. (20260727130000)
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
      COALESCE(v_code, 'this course');
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

-- 2 and 3. Claiming an unaccepted allocation, declining a claimed one, and the
--          missing decline reason. (20260726225438 + 20260727101138)
CREATE OR REPLACE FUNCTION assert_teaching_assignment_edit()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $fn$
BEGIN
  IF NEW.offering_id IS NOT NULL
     AND NEW.offering_id IS DISTINCT FROM OLD.offering_id
     AND NEW.status <> 'accepted' THEN
    RAISE EXCEPTION
      'Accept this allocation before creating its course offering (status is %)',
      NEW.status;
  END IF;

  IF NEW.status = 'declined'
     AND OLD.status IS DISTINCT FROM 'declined'
     AND NEW.offering_id IS NOT NULL THEN
    RAISE EXCEPTION
      'This allocation already has a course offering. Archive the offering first if the class is not going ahead.';
  END IF;

  IF is_module_leader(NEW.department)
     OR get_my_profile_role() IN ('admin', 'dept_admin', 'super_admin')
     OR caller_can('course_offerings', 'manage') THEN
    RETURN NEW;
  END IF;

  IF NEW.teacher_id      IS DISTINCT FROM OLD.teacher_id
     OR NEW.department   IS DISTINCT FROM OLD.department
     OR NEW.course_code  IS DISTINCT FROM OLD.course_code
     OR NEW.course_type  IS DISTINCT FROM OLD.course_type
     OR NEW.batch        IS DISTINCT FROM OLD.batch
     OR NEW.section      IS DISTINCT FROM OLD.section
     OR NEW.semester     IS DISTINCT FROM OLD.semester
     OR NEW.assigned_by  IS DISTINCT FROM OLD.assigned_by THEN
    RAISE EXCEPTION 'You may only accept or decline an allocation, not change it'
      USING errcode = '42501';
  END IF;

  IF NEW.status = 'declined' AND COALESCE(btrim(NEW.decline_reason), '') = '' THEN
    RAISE EXCEPTION 'A reason is required when declining an allocation';
  END IF;

  RETURN NEW;
END;
$fn$;

REVOKE ALL ON FUNCTION assert_teaching_assignment_edit() FROM public, anon, authenticated;

-- 4. Joining or being admitted to an ended course. (20260726231608)
CREATE OR REPLACE FUNCTION assert_offering_not_archived()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $fn$
DECLARE v_archived boolean; v_code text;
BEGIN
  SELECT co.is_archived, c.code INTO v_archived, v_code
  FROM course_offerings co
  LEFT JOIN courses c ON c.id = co.course_id
  WHERE co.id = NEW.offering_id;

  IF COALESCE(v_archived, false) THEN
    RAISE EXCEPTION
      '% has ended and is no longer accepting students. Restore it first if this was a mistake.',
      COALESCE(v_code, 'That course');
  END IF;

  RETURN NEW;
END;
$fn$;

REVOKE ALL ON FUNCTION assert_offering_not_archived() FROM public, anon, authenticated;

-- 5. Withdrawing an approval that was never granted. (20260727094328)
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
    RAISE EXCEPTION 'Only an approved offering can have its approval withdrawn (this one is %)', v_status;
  END IF;

  DELETE FROM schedule_slots WHERE course_offering_id = p_offering_id;
  GET DIAGNOSTICS v_dropped = ROW_COUNT;

  UPDATE course_offerings
     SET status            = 'rejected',
         reviewed_by       = auth.uid(),
         reviewed_at       = now(),
         rejection_reason  = NULLIF(btrim(p_reason), '')
   WHERE id = p_offering_id;

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
