-- Approving an offering must pin it onto everyone already enrolled in it.
--
-- approve_course_offering() generated the schedule_slots rows and stopped
-- there. Pinning was done only by approve_course_join(), one student at a time,
-- at the moment THEY were admitted. That leaves two ways to end up with an
-- 'approved' enrolment in a course that is missing from the student's routine:
--
--   1. A teacher admits a student BEFORE the admin approves the offering.
--      approve_course_join() checks that the caller owns the offering and that
--      the request is pending; it never required the offering itself to be
--      approved. So it pins whatever slots exist, which at that point is none,
--      and nothing ever goes back to fix it. Pre-existing.
--
--   2. An admin withdraws an approval and later grants it again.
--      revoke_course_offering() drops the slots, and user_pinned_slots cascades
--      with them (correctly — the classes really are gone). Re-approving then
--      built fresh slots that nobody was pinned to. Introduced by
--      20260727094328, whose own comment promised "approving it again restores
--      them". It did not. Caught by running the full
--      approve -> pin -> revoke -> re-approve cycle against real slots: 2 slots
--      regenerated, 0 students re-pinned.
--
-- Both are the same missing rule, so this fixes them in one place: approval
-- pins the offering onto every student whose enrolment is already approved.
-- ON CONFLICT DO NOTHING makes it idempotent and makes the ordinary
-- first-approval case a no-op, since nobody is enrolled yet.
--
-- Everything else in this function is unchanged from 20260724143117.

CREATE OR REPLACE FUNCTION approve_course_offering(p_offering_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE o record; m record; v_slot_id uuid; v_created integer := 0;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'authentication required' USING errcode='42501'; END IF;
  IF get_my_profile_role() NOT IN ('admin','dept_admin','super_admin')
     AND NOT caller_can('course_offerings','manage') THEN
    RAISE EXCEPTION 'Only an admin can approve a course offering' USING errcode='42501';
  END IF;

  SELECT co.*, c.code AS course_code, c.title AS course_title, c.credit_hours, c.course_type,
         p.full_name AS teacher_name, p.avatar_url AS teacher_avatar, p.teacher_initial
    INTO o
  FROM course_offerings co
  LEFT JOIN courses c ON c.id = co.course_id
  LEFT JOIN profiles p ON p.id = co.teacher_id
  WHERE co.id = p_offering_id AND co.status = 'pending';

  IF o.id IS NULL THEN RAISE EXCEPTION 'Offering not found or already reviewed'; END IF;
  IF o.department IS NULL THEN
    RAISE EXCEPTION 'Offering has no department set and cannot be published to a routine';
  END IF;

  UPDATE course_offerings SET status='approved', reviewed_by=auth.uid(), reviewed_at=now()
   WHERE id = p_offering_id;

  FOR m IN SELECT * FROM course_offering_meetings WHERE offering_id = p_offering_id
           ORDER BY day_of_week, start_time, lab_subgroup
  LOOP
    INSERT INTO schedule_slots (
      subject, subject_code, credit_hours, teacher_name, teacher_avatar, teacher_initial,
      room_number, building, start_time, end_time, day_of_week,
      department, semester, batch, section, course_offering_id, is_lab, lab_subgroup, room_type
    ) VALUES (
      COALESCE(o.course_title,'Untitled Course'), o.course_code, COALESCE(o.credit_hours,3),
      o.teacher_name, o.teacher_avatar, o.teacher_initial,
      m.room_number, m.building, m.start_time, m.end_time, m.day_of_week,
      o.department, COALESCE(o.semester,1), o.batch, o.section,
      p_offering_id, (m.class_type='lab'), m.lab_subgroup,
      CASE WHEN m.class_type='lab' THEN 'LAB' ELSE NULL END
    ) RETURNING id INTO v_slot_id;
    UPDATE course_offering_meetings SET schedule_slot_id = v_slot_id WHERE id = m.id;
    v_created := v_created + 1;
  END LOOP;

  -- The new rule. Anyone already admitted gets the freshly published classes on
  -- their routine, whether they were admitted early or lost their pins to a
  -- withdrawn approval.
  INSERT INTO user_pinned_slots (user_id, schedule_slot_id)
  SELECT e.student_id, ss.id
    FROM enrollments e
    JOIN schedule_slots ss ON ss.course_offering_id = p_offering_id
   WHERE e.offering_id = p_offering_id
     AND e.status = 'approved'
  ON CONFLICT (user_id, schedule_slot_id) DO NOTHING;

  RETURN v_created;
END; $function$;
