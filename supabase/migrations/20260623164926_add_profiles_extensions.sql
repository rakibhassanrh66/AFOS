-- 1. Create extension tables
CREATE TABLE IF NOT EXISTS students (
  profile_id uuid PRIMARY KEY REFERENCES profiles(id) ON DELETE CASCADE,
  department_id uuid REFERENCES departments(id),
  program_id uuid REFERENCES programs(id),
  batch_id uuid REFERENCES batches(id),
  current_semester_no int DEFAULT 1,
  cgpa numeric(3,2) DEFAULT 0.00,
  status text DEFAULT 'active' CHECK (status IN ('active', 'graduated', 'dropped', 'probation'))
);

CREATE TABLE IF NOT EXISTS teachers (
  profile_id uuid PRIMARY KEY REFERENCES profiles(id) ON DELETE CASCADE,
  department_id uuid REFERENCES departments(id),
  designation text,
  joining_date date
);

-- 2. Enable RLS
ALTER TABLE students ENABLE ROW LEVEL SECURITY;
ALTER TABLE teachers ENABLE ROW LEVEL SECURITY;

-- 3. RLS Policies
-- Students: Read own, Admin/DeptAdmin read all in dept
CREATE POLICY students_read_self ON students FOR SELECT TO authenticated USING (profile_id = auth.uid());
CREATE POLICY students_read_dept ON students FOR SELECT TO authenticated USING (has_permission('students', 'select', 'department'));
CREATE POLICY students_write_admin ON students FOR ALL TO authenticated USING (has_permission('students', 'all', 'all'));

-- Teachers: Read all, Admin write
CREATE POLICY teachers_read_all ON teachers FOR SELECT TO authenticated USING (true);
CREATE POLICY teachers_write_admin ON teachers FOR ALL TO authenticated USING (has_permission('teachers', 'all', 'all'));
