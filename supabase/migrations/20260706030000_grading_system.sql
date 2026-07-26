-- Grading system: teacher uploads (draft), department-tier roles publish,
-- students only ever see published results for themselves. courses/
-- course_offerings are still empty (never populated by any flow), so this
-- reuses the same teacher_initial+batch+section convention schedule_slots
-- already has real data for, rather than building on dormant tables.

CREATE TABLE grades (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  teacher_id uuid REFERENCES profiles(id) ON DELETE SET NULL,
  department_id uuid REFERENCES departments(id),
  course_code text NOT NULL,
  course_title text,
  semester int NOT NULL,
  batch text,
  section text,
  grade_letter text NOT NULL,
  marks numeric,
  is_published boolean NOT NULL DEFAULT false,
  published_by uuid REFERENCES profiles(id) ON DELETE SET NULL,
  published_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (student_id, course_code, semester)
);

ALTER TABLE grades ENABLE ROW LEVEL SECURITY;

-- A teacher can only write their own uploads, and only before publish —
-- once a department-tier role publishes it, the teacher can no longer
-- quietly edit a result students may already be viewing.
CREATE POLICY teacher_upload_grades ON grades
  FOR INSERT
  WITH CHECK (auth.uid() = teacher_id AND is_published = false);

CREATE POLICY teacher_update_own_draft_grades ON grades
  FOR UPDATE
  USING (auth.uid() = teacher_id AND is_published = false)
  WITH CHECK (auth.uid() = teacher_id);

CREATE POLICY teacher_read_own_uploads ON grades
  FOR SELECT
  USING (auth.uid() = teacher_id);

CREATE POLICY student_read_own_published_grades ON grades
  FOR SELECT
  USING (auth.uid() = student_id AND is_published = true);

CREATE POLICY department_tier_manage_grades ON grades
  FOR ALL
  USING (get_my_profile_role() = ANY (ARRAY['admin', 'dept_admin', 'super_admin', 'exam_controller']))
  WITH CHECK (get_my_profile_role() = ANY (ARRAY['admin', 'dept_admin', 'super_admin', 'exam_controller']));

-- Same narrow-grant pattern as find_section_cr — a teacher has no RLS read
-- path on `students` at all, so this returns just enough (id/name/
-- university_id) to build a grading roster for a section they actually
-- teach, without exposing cgpa/status/etc.
CREATE OR REPLACE FUNCTION list_section_students(p_department_code text, p_batch text, p_section text)
RETURNS TABLE (id uuid, full_name text, university_id text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN QUERY
  SELECT p.id, p.full_name, p.university_id
  FROM students s
  JOIN profiles p ON p.id = s.profile_id
  JOIN departments d ON d.id = s.department_id
  WHERE d.code = p_department_code
    AND s.batch_label = p_batch
    AND s.section = p_section
  ORDER BY p.full_name;
END;
$$;

GRANT EXECUTE ON FUNCTION list_section_students(text, text, text) TO authenticated;
