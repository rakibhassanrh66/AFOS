-- 1. Create Academic Tables
CREATE TABLE IF NOT EXISTS courses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  department_id uuid REFERENCES departments(id),
  code text UNIQUE NOT NULL,
  title text NOT NULL,
  credit_hours int,
  course_type text CHECK (course_type IN ('theory', 'lab'))
);

CREATE TABLE IF NOT EXISTS course_offerings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  course_id uuid REFERENCES courses(id),
  semester_id uuid REFERENCES semesters(id),
  teacher_id uuid REFERENCES teachers(profile_id),
  section text,
  UNIQUE(course_id, semester_id, section)
);

CREATE TABLE IF NOT EXISTS enrollments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id uuid REFERENCES students(profile_id),
  offering_id uuid REFERENCES course_offerings(id),
  UNIQUE(student_id, offering_id)
);

-- 2. Enable RLS
ALTER TABLE courses ENABLE ROW LEVEL SECURITY;
ALTER TABLE course_offerings ENABLE ROW LEVEL SECURITY;
ALTER TABLE enrollments ENABLE ROW LEVEL SECURITY;

-- 3. RLS Policies
-- Courses: Admin/DeptAdmin write, Everyone read
CREATE POLICY admin_write_courses ON courses FOR ALL TO authenticated USING (has_permission('courses', 'all', 'all'));
CREATE POLICY public_read_courses ON courses FOR SELECT TO authenticated USING (true);

-- Offerings: Admin/DeptAdmin write, Everyone read
CREATE POLICY admin_write_offerings ON course_offerings FOR ALL TO authenticated USING (has_permission('course_offerings', 'all', 'all'));
CREATE POLICY public_read_offerings ON course_offerings FOR SELECT TO authenticated USING (true);

-- Enrollments: Student read self, Admin/Teacher manage
CREATE POLICY student_read_enrollments ON enrollments FOR SELECT TO authenticated USING (student_id = auth.uid());
CREATE POLICY admin_write_enrollments ON enrollments FOR ALL TO authenticated USING (has_permission('enrollments', 'all', 'all'));
