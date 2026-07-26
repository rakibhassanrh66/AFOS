-- =====================================================================
--  AFOS — Authorization audit fixes (authenticated-role gaps found when
--  auditing RLS beyond the 2026-07-02 signup/login fix chain).
--
--  Confirmed gaps (each traced to a live client call that RLS silently
--  blocks today):
--   1. permissions/role_permissions were declared but never seeded, so
--      has_permission() always returns false for every role — this
--      blocks every admin-gated write policy across faculties,
--      departments, programs, batches, students, teachers, courses,
--      course_offerings, enrollments, grade_change_requests and
--      semester_results.
--   2. enrollments has no student self-insert policy, but
--      academic_repository.dart calls
--      `_client.from('enrollments').insert(...)` as the student.
--   3. marks has zero write policy for the entering teacher, but
--      marks_repository.dart calls
--      `_client.from('marks').update(...)` as the teacher.
--   4. approve_grade_change() is SECURITY DEFINER with no authorization
--      check — any authenticated user (including the requester) can
--      approve any grade-change request.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Seed permissions + role_permissions so has_permission() is usable.
-- ---------------------------------------------------------------------
INSERT INTO permissions (resource, action, scope) VALUES
  ('faculties','all','all'), ('departments','all','all'), ('programs','all','all'),
  ('batches','all','all'),
  ('students','all','all'), ('students','select','department'),
  ('teachers','all','all'),
  ('courses','all','all'), ('course_offerings','all','all'),
  ('enrollments','all','all'),
  ('grade_change','select','department'), ('grade_change','update','department'),
  ('results','select','all')
ON CONFLICT (resource, action, scope) DO NOTHING;

-- super_admin gets every permission.
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r CROSS JOIN permissions p
WHERE r.name = 'super_admin'
ON CONFLICT DO NOTHING;

-- admin gets department-scoped reads + grade-change approval (conservative
-- default — widen later if super_admin-only was intended for org-wide
-- writes like faculties/departments/programs/batches).
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r CROSS JOIN permissions p
WHERE r.name = 'admin'
  AND (p.resource, p.action, p.scope) IN (
    ('students','select','department'),
    ('grade_change','select','department'),
    ('grade_change','update','department'),
    ('results','select','all')
  )
ON CONFLICT DO NOTHING;

-- dept_head mirrors admin's department-scoped grade-change approval rights.
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r CROSS JOIN permissions p
WHERE r.name = 'dept_head'
  AND (p.resource, p.action, p.scope) IN (
    ('students','select','department'),
    ('grade_change','select','department'),
    ('grade_change','update','department')
  )
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------
-- 2. Students may self-enroll (own row only).
-- ---------------------------------------------------------------------
DROP POLICY IF EXISTS "student_insert_own_enrollment" ON enrollments;
CREATE POLICY "student_insert_own_enrollment" ON enrollments
  FOR INSERT TO authenticated WITH CHECK (student_id = auth.uid());

-- ---------------------------------------------------------------------
-- 3. Teachers may write marks rows they entered.
-- ---------------------------------------------------------------------
DROP POLICY IF EXISTS "teacher_write_own_marks" ON marks;
CREATE POLICY "teacher_write_own_marks" ON marks
  FOR UPDATE TO authenticated USING (entered_by = auth.uid()) WITH CHECK (entered_by = auth.uid());

DROP POLICY IF EXISTS "teacher_insert_own_marks" ON marks;
CREATE POLICY "teacher_insert_own_marks" ON marks
  FOR INSERT TO authenticated WITH CHECK (entered_by = auth.uid());

-- ---------------------------------------------------------------------
-- 4. Guard approve_grade_change() against unauthorized callers.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION approve_grade_change(request_id uuid)
RETURNS void AS $$
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
$$ LANGUAGE plpgsql SECURITY DEFINER;
