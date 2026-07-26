-- =====================================================================
--  AFOS — Server-side operations for the curriculum system.
--
--  Three of these replace or repair multi-step client-side logic:
--
--  1. approve_course_offering — approval was three separate client writes
--     (update status, insert ONE schedule_slots row, notify). With
--     multi-meeting offerings it must fan out one slot per meeting, and a
--     half-applied approval (status flipped but slots missing) leaves an
--     offering that students can join but that never appears on a routine.
--     Doing it in one function makes it atomic and lets it read the
--     teacher/course fields it needs without three extra round-trips.
--
--  2. approve_course_join — had `select id into v_slot_id from
--     schedule_slots where course_offering_id = v_offering_id LIMIT 1`,
--     which was fine when an offering meant exactly one slot. A course
--     meeting twice a week, or a lab split across two sessions, now
--     produces several -- so an approved student got pinned to only the
--     first one and the rest silently never appeared on their routine.
--     Now pins every slot belonging to the offering.
--
--  3. archive_course_offering — semester rollover. A teacher cannot UPDATE
--     an approved offering at all (teacher_update_own_pending_offering is
--     scoped to status='pending'), so ending a course needed a definer
--     path. Removes the generated slots (which cascades the students'
--     user_pinned_slots rows) but KEEPS the offering and its enrollments
--     as the historical record of who took the course.
--
--  4. list_offering_audience — resolves "everyone in this offering's
--     batch+section", so an approved offering can notify the students it
--     is actually for. Mirrors list_section_students (20260706030000).
-- =====================================================================


-- ---------------------------------------------------------------
-- 1. Who should hear about this offering
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.list_offering_audience(p_offering_id uuid)
RETURNS TABLE(profile_id uuid)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_department text;
  v_batch      text;
  v_section    text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING errcode = '42501';
  END IF;

  SELECT co.department, co.batch, co.section
    INTO v_department, v_batch, v_section
  FROM course_offerings co WHERE co.id = p_offering_id;

  IF v_department IS NULL THEN
    RETURN;
  END IF;

  -- Deliberately returns ONLY profile ids, never names or university ids:
  -- its single job is addressing notifications, so it should not become a
  -- second, less-guarded copy of list_section_students.
  RETURN QUERY
  SELECT p.id
  FROM students s
  JOIN profiles p ON p.id = s.profile_id
  LEFT JOIN departments d ON d.id = s.department_id
  WHERE COALESCE(d.code, p.department) = v_department
    AND s.batch_label = v_batch
    AND s.section = v_section;
END;
$$;


-- ---------------------------------------------------------------
-- 2. Approve an offering and publish all of its meetings
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.approve_course_offering(p_offering_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  o           record;
  m           record;
  v_slot_id   uuid;
  v_created   integer := 0;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING errcode = '42501';
  END IF;

  IF get_my_profile_role() NOT IN ('admin','dept_admin','super_admin')
     AND NOT caller_can('course_offerings','manage') THEN
    RAISE EXCEPTION 'Only an admin can approve a course offering' USING errcode = '42501';
  END IF;

  SELECT co.*, c.code AS course_code, c.title AS course_title,
         c.credit_hours, c.course_type,
         p.full_name AS teacher_name, p.avatar_url AS teacher_avatar,
         p.teacher_initial
    INTO o
  FROM course_offerings co
  LEFT JOIN courses  c ON c.id = co.course_id
  LEFT JOIN profiles p ON p.id = co.teacher_id
  WHERE co.id = p_offering_id AND co.status = 'pending';

  IF o.id IS NULL THEN
    RAISE EXCEPTION 'Offering not found or already reviewed';
  END IF;
  IF o.department IS NULL THEN
    RAISE EXCEPTION 'Offering has no department set and cannot be published to a routine';
  END IF;

  UPDATE course_offerings
     SET status = 'approved', reviewed_by = auth.uid(), reviewed_at = now()
   WHERE id = p_offering_id;

  -- One schedule_slots row per declared meeting. is_lab/lab_subgroup/
  -- room_type now come from the meeting itself, so a lab offering finally
  -- lands as a lab instead of an ordinary theory row (the old client-side
  -- approval never set any of the three, even when courses.course_type
  -- said 'lab').
  FOR m IN SELECT * FROM course_offering_meetings WHERE offering_id = p_offering_id
           ORDER BY day_of_week, start_time, lab_subgroup
  LOOP
    INSERT INTO schedule_slots (
      subject, subject_code, credit_hours,
      teacher_name, teacher_avatar, teacher_initial,
      room_number, building, start_time, end_time, day_of_week,
      department, semester, batch, section,
      course_offering_id, is_lab, lab_subgroup, room_type
    ) VALUES (
      COALESCE(o.course_title, 'Untitled Course'), o.course_code,
      COALESCE(o.credit_hours, 3),
      o.teacher_name, o.teacher_avatar, o.teacher_initial,
      m.room_number, m.building, m.start_time, m.end_time, m.day_of_week,
      o.department, COALESCE(o.semester, 1), o.batch, o.section,
      p_offering_id,
      (m.class_type = 'lab'), m.lab_subgroup,
      CASE WHEN m.class_type = 'lab' THEN 'LAB' ELSE NULL END
    )
    RETURNING id INTO v_slot_id;

    UPDATE course_offering_meetings SET schedule_slot_id = v_slot_id WHERE id = m.id;
    v_created := v_created + 1;
  END LOOP;

  RETURN v_created;
END;
$$;


-- ---------------------------------------------------------------
-- 3. Approve a join request -- pin EVERY slot, not just the first
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.approve_course_join(p_enrollment_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_student_id  uuid;
  v_offering_id uuid;
  v_teacher_id  uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING errcode = '42501';
  END IF;

  SELECT e.student_id, e.offering_id, co.teacher_id
    INTO v_student_id, v_offering_id, v_teacher_id
  FROM enrollments e
  JOIN course_offerings co ON co.id = e.offering_id
  WHERE e.id = p_enrollment_id AND e.status = 'pending';

  IF v_student_id IS NULL THEN
    RAISE EXCEPTION 'Join request not found or already reviewed';
  END IF;

  IF v_teacher_id IS DISTINCT FROM auth.uid()
     AND get_my_profile_role() NOT IN ('admin','dept_admin','super_admin')
     AND NOT caller_can('enrollments','manage') THEN
    RAISE EXCEPTION 'Only the offering''s teacher or an admin can approve this request';
  END IF;

  UPDATE enrollments SET status = 'approved' WHERE id = p_enrollment_id;

  -- Every slot the offering generated, not LIMIT 1.
  INSERT INTO user_pinned_slots (user_id, schedule_slot_id)
  SELECT v_student_id, ss.id
  FROM schedule_slots ss
  WHERE ss.course_offering_id = v_offering_id
  ON CONFLICT (user_id, schedule_slot_id) DO NOTHING;
END;
$$;


-- ---------------------------------------------------------------
-- 4. Semester rollover
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.archive_course_offering(p_offering_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_teacher_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING errcode = '42501';
  END IF;

  SELECT teacher_id INTO v_teacher_id FROM course_offerings WHERE id = p_offering_id;
  IF v_teacher_id IS NULL AND NOT EXISTS (SELECT 1 FROM course_offerings WHERE id = p_offering_id) THEN
    RAISE EXCEPTION 'Offering not found';
  END IF;

  IF v_teacher_id IS DISTINCT FROM auth.uid()
     AND get_my_profile_role() NOT IN ('admin','dept_admin','super_admin')
     AND NOT caller_can('course_offerings','manage') THEN
    RAISE EXCEPTION 'Only the offering''s teacher or an admin can archive it' USING errcode = '42501';
  END IF;

  -- Deleting the generated slots cascades user_pinned_slots, so the course
  -- disappears from every enrolled student's routine. Enrollments are kept:
  -- they are the record of who took the course, which is exactly what a
  -- past semester should retain.
  DELETE FROM schedule_slots WHERE course_offering_id = p_offering_id;

  UPDATE course_offerings
     SET is_archived = true, archived_at = now()
   WHERE id = p_offering_id;
END;
$$;


-- Same ACL discipline as 20260721194633 / 20260725130000.
REVOKE ALL ON FUNCTION public.list_offering_audience(uuid)    FROM public, anon;
REVOKE ALL ON FUNCTION public.approve_course_offering(uuid)   FROM public, anon;
REVOKE ALL ON FUNCTION public.approve_course_join(uuid)       FROM public, anon;
REVOKE ALL ON FUNCTION public.archive_course_offering(uuid)   FROM public, anon;

GRANT EXECUTE ON FUNCTION public.list_offering_audience(uuid)  TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_course_offering(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_course_join(uuid)     TO authenticated;
GRANT EXECUTE ON FUNCTION public.archive_course_offering(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
