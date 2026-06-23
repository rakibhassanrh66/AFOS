-- 1. Semester Results Table (Cached SGPA)
CREATE TABLE IF NOT EXISTS semester_results (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id uuid REFERENCES students(profile_id),
  semester_id uuid REFERENCES semesters(id),
  sgpa numeric(3,2),
  total_credits int,
  quality_points numeric(10,2),
  UNIQUE(student_id, semester_id)
);

-- 2. CGPA Discrepancies (for nightly reconciliation)
CREATE TABLE IF NOT EXISTS cgpa_discrepancies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id uuid REFERENCES students(profile_id),
  cached_cgpa numeric(3,2),
  recomputed_cgpa numeric(3,2),
  detected_at timestamp with time zone DEFAULT now(),
  resolved boolean DEFAULT false
);

-- 3. RLS Policies
ALTER TABLE semester_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE cgpa_discrepancies ENABLE ROW LEVEL SECURITY;

CREATE POLICY student_read_results ON semester_results FOR SELECT TO authenticated USING (student_id = auth.uid());
CREATE POLICY admin_read_results ON semester_results FOR SELECT TO authenticated USING (has_permission('results', 'select', 'all'));

-- 4. CGPA Calculation Function
CREATE OR REPLACE FUNCTION calculate_semester_sgpa(p_student_id uuid, p_semester_id uuid)
RETURNS void AS $$
DECLARE
  v_sgpa numeric(3,2);
  v_total_credits int;
  v_total_quality_points numeric(10,2);
BEGIN
  SELECT SUM(credit_hours), SUM(grade_point * credit_hours)
  INTO v_total_credits, v_total_quality_points
  FROM marks m
  JOIN enrollments e ON m.enrollment_id = e.id
  JOIN course_offerings co ON e.offering_id = co.id
  JOIN courses c ON co.course_id = c.id
  WHERE e.student_id = p_student_id AND co.semester_id = p_semester_id;

  v_sgpa := v_total_quality_points / v_total_credits;

  INSERT INTO semester_results (student_id, semester_id, sgpa, total_credits, quality_points)
  VALUES (p_student_id, p_semester_id, v_sgpa, v_total_credits, v_total_quality_points)
  ON CONFLICT (student_id, semester_id) 
  DO UPDATE SET sgpa = v_sgpa, total_credits = v_total_credits, quality_points = v_total_quality_points;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
