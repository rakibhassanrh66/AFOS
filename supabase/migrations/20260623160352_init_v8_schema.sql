-- 1. Helper function for RLS
CREATE OR REPLACE FUNCTION has_permission(resource text, action text, scope text)
RETURNS boolean AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM role_permissions rp
    JOIN permissions p ON rp.permission_id = p.id
    JOIN profiles pr ON pr.role_id = rp.role_id
    WHERE pr.id = auth.uid()
      AND p.resource = resource
      AND p.action = action
      AND p.scope = scope
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Modify existing profiles
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS role_id uuid;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS department_id uuid;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS university_id text UNIQUE;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS phone text;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS photo_url text;

-- 3. Create new tables
CREATE TABLE IF NOT EXISTS roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text UNIQUE NOT NULL,
  description text,
  is_system boolean DEFAULT false,
  created_by uuid REFERENCES profiles(id)
);

CREATE TABLE IF NOT EXISTS permissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  resource text NOT NULL,
  action text NOT NULL,
  scope text NOT NULL,
  UNIQUE(resource, action, scope)
);

CREATE TABLE IF NOT EXISTS role_permissions (
  role_id uuid REFERENCES roles(id) ON DELETE CASCADE,
  permission_id uuid REFERENCES permissions(id) ON DELETE CASCADE,
  PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE IF NOT EXISTS faculties (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  code text UNIQUE NOT NULL,
  dean_id uuid REFERENCES profiles(id)
);

CREATE TABLE IF NOT EXISTS departments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  faculty_id uuid REFERENCES faculties(id),
  name text NOT NULL,
  code text UNIQUE NOT NULL,
  head_id uuid REFERENCES profiles(id)
);

CREATE TABLE IF NOT EXISTS programs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  department_id uuid REFERENCES departments(id),
  name text NOT NULL,
  degree_type text CHECK (degree_type IN ('Bachelor', 'Master')),
  total_credits int
);

CREATE TABLE IF NOT EXISTS batches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  program_id uuid REFERENCES programs(id),
  name text NOT NULL,
  start_year int
);

CREATE TABLE IF NOT EXISTS students (
  profile_id uuid PRIMARY KEY REFERENCES profiles(id),
  department_id uuid REFERENCES departments(id),
  program_id uuid REFERENCES programs(id),
  batch_id uuid REFERENCES batches(id),
  current_semester_no int,
  cgpa numeric(3,2),
  status text CHECK (status IN ('active', 'graduated', 'dropped', 'probation'))
);

CREATE TABLE IF NOT EXISTS teachers (
  profile_id uuid PRIMARY KEY REFERENCES profiles(id),
  department_id uuid REFERENCES departments(id),
  designation text,
  joining_date date
);

CREATE TABLE IF NOT EXISTS semesters (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  start_date date,
  end_date date,
  is_active boolean DEFAULT false
);

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

CREATE TABLE IF NOT EXISTS grading_scale (
  min_marks numeric(5,2),
  max_marks numeric(5,2),
  letter_grade text,
  grade_point numeric(3,2)
);

CREATE TABLE IF NOT EXISTS marks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  enrollment_id uuid UNIQUE REFERENCES enrollments(id),
  attendance_marks numeric(5,2),
  quiz_marks numeric(5,2),
  assignment_marks numeric(5,2),
  midterm_marks numeric(5,2),
  final_marks numeric(5,2),
  total_marks numeric(5,2) GENERATED ALWAYS AS (attendance_marks + quiz_marks + assignment_marks + midterm_marks + final_marks) STORED,
  letter_grade text,
  grade_point numeric(3,2),
  is_published boolean DEFAULT false,
  entered_by uuid REFERENCES teachers(profile_id)
);

-- 4. Enable RLS and add basic policies
ALTER TABLE roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE students ENABLE ROW LEVEL SECURITY;
ALTER TABLE marks ENABLE ROW LEVEL SECURITY;

CREATE POLICY students_self_select ON students FOR SELECT USING (profile_id = auth.uid());
CREATE POLICY marks_student_read ON marks FOR SELECT USING (is_published = true AND EXISTS (SELECT 1 FROM enrollments e WHERE e.id = marks.enrollment_id AND e.student_id = auth.uid()));

-- Forbidden query example for tests:
-- SELECT * FROM students WHERE profile_id != auth.uid(); -- This will return 0 rows for a student role.
