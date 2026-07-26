-- 1. Create Grading Scale
CREATE TABLE IF NOT EXISTS grading_scale (
  min_marks numeric(5,2) PRIMARY KEY,
  max_marks numeric(5,2),
  letter_grade text,
  grade_point numeric(3,2)
);

-- Seed Grading Scale
INSERT INTO grading_scale (min_marks, max_marks, letter_grade, grade_point) VALUES
(80, 100, 'A+', 4.00), (75, 79.99, 'A', 3.75), (70, 74.99, 'A-', 3.50),
(65, 69.99, 'B+', 3.25), (60, 64.99, 'B', 3.00), (55, 59.99, 'B-', 2.75),
(50, 54.99, 'C+', 2.50), (45, 49.99, 'C', 2.25), (40, 44.99, 'D', 2.00),
(0, 39.99, 'F', 0.00) ON CONFLICT DO NOTHING;

-- 2. Create Marks Table
CREATE TABLE IF NOT EXISTS marks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  enrollment_id uuid UNIQUE REFERENCES enrollments(id) ON DELETE CASCADE,
  attendance_marks numeric(5,2) DEFAULT 0,
  quiz_marks numeric(5,2) DEFAULT 0,
  assignment_marks numeric(5,2) DEFAULT 0,
  midterm_marks numeric(5,2) DEFAULT 0,
  final_marks numeric(5,2) DEFAULT 0,
  total_marks numeric(5,2) GENERATED ALWAYS AS (attendance_marks + quiz_marks + assignment_marks + midterm_marks + final_marks) STORED,
  letter_grade text,
  grade_point numeric(3,2),
  is_published boolean DEFAULT false,
  entered_by uuid REFERENCES teachers(profile_id)
);

-- 3. Audit Log Table
CREATE TABLE IF NOT EXISTS audit_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  table_name text,
  record_id uuid,
  action text,
  old_data jsonb,
  new_data jsonb,
  changed_by uuid REFERENCES profiles(id),
  changed_at timestamp with time zone DEFAULT now()
);

-- 4. Triggers
-- Function: Auto-calculate grade
CREATE OR REPLACE FUNCTION calculate_grade()
RETURNS trigger AS $$
DECLARE
  scale record;
BEGIN
  SELECT * INTO scale FROM grading_scale 
  WHERE NEW.total_marks BETWEEN min_marks AND max_marks LIMIT 1;
  
  NEW.letter_grade := scale.letter_grade;
  NEW.grade_point := scale.grade_point;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_calculate_grade
BEFORE INSERT OR UPDATE ON marks
FOR EACH ROW EXECUTE PROCEDURE calculate_grade();

-- Function: Immutability Lock
CREATE OR REPLACE FUNCTION prevent_published_marks_edit()
RETURNS trigger AS $$
BEGIN
  IF OLD.is_published = true THEN
    RAISE EXCEPTION 'Published marks cannot be modified. Use grade_change_requests.';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_edit
BEFORE UPDATE ON marks
FOR EACH ROW EXECUTE PROCEDURE prevent_published_marks_edit();
