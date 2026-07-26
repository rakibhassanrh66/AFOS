-- =====================================================================
--  AFOS — Pin search_path on every SECURITY DEFINER function
--  handle_new_user()/auto_confirm_email() already got this fix
--  (20260703040000) after it caused every signup to fail 500 under
--  supabase_auth_admin's search_path='auth'. The same class of bug is
--  latent in every other SECURITY DEFINER function here: today they
--  only run under roles (authenticated/anon) whose search_path happens
--  to include public, so they "work" — but that's incidental, not
--  guaranteed, and any future role/connection-pooling change or
--  Supabase platform default could silently break RLS-gated access
--  (has_permission/get_my_profile_role) or grade/GPA writes the same
--  way signup broke. Pin all of them now so this cannot recur.
-- =====================================================================

CREATE OR REPLACE FUNCTION get_my_profile_role()
RETURNS text LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public, pg_temp
AS $$ SELECT role FROM profiles WHERE id = auth.uid(); $$;

CREATE OR REPLACE FUNCTION has_permission(resource text, action text, scope text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM role_permissions rp
    JOIN permissions p ON rp.permission_id = p.id
    JOIN profiles pr ON pr.role_id = rp.role_id
    WHERE pr.id = auth.uid()
      AND p.resource = has_permission.resource
      AND p.action = has_permission.action
      AND p.scope = has_permission.scope
  );
END;
$$;

CREATE OR REPLACE FUNCTION approve_grade_change(request_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  req record;
BEGIN
  IF NOT has_permission('grade_change', 'update', 'department') THEN
    RAISE EXCEPTION 'Not authorized to approve grade change requests.';
  END IF;

  SELECT * INTO req FROM grade_change_requests WHERE id = request_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Grade change request % not found.', request_id;
  END IF;

  UPDATE marks
  SET attendance_marks = (req.new_values->>'attendance_marks')::numeric,
      quiz_marks       = (req.new_values->>'quiz_marks')::numeric,
      assignment_marks = (req.new_values->>'assignment_marks')::numeric,
      midterm_marks    = (req.new_values->>'midterm_marks')::numeric,
      final_marks      = (req.new_values->>'final_marks')::numeric
  WHERE id = req.marks_id;

  UPDATE grade_change_requests
  SET status = 'approved', reviewed_by = auth.uid(), reviewed_at = now()
  WHERE id = request_id;
END;
$$;

CREATE OR REPLACE FUNCTION calculate_semester_sgpa(p_student_id uuid, p_semester_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_sgpa numeric(3,2);
  v_total_credits int;
  v_total_quality_points numeric(10,2);
BEGIN
  SELECT
    SUM(credit_hours),
    SUM(grade_point * credit_hours)
  INTO
    v_total_credits,
    v_total_quality_points
  FROM marks m
  JOIN enrollments e ON m.enrollment_id = e.id
  JOIN course_offerings co ON e.offering_id = co.id
  JOIN courses c ON co.course_id = c.id
  WHERE e.student_id = p_student_id
    AND co.semester_id = p_semester_id;

  IF v_total_credits IS NULL OR v_total_credits = 0 THEN
    v_sgpa := 0;
  ELSE
    v_sgpa := v_total_quality_points / v_total_credits;
  END IF;

  INSERT INTO semester_results (
    student_id,
    semester_id,
    sgpa,
    total_credits,
    quality_points
  )
  VALUES (
    p_student_id,
    p_semester_id,
    v_sgpa,
    v_total_credits,
    v_total_quality_points
  )
  ON CONFLICT (student_id, semester_id)
  DO UPDATE SET
    sgpa = v_sgpa,
    total_credits = v_total_credits,
    quality_points = v_total_quality_points;
END;
$$;
