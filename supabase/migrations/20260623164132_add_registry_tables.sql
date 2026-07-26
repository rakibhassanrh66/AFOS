-- 1. Registry Tables
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

-- 2. RLS Policies
ALTER TABLE faculties ENABLE ROW LEVEL SECURITY;
ALTER TABLE departments ENABLE ROW LEVEL SECURITY;
ALTER TABLE programs ENABLE ROW LEVEL SECURITY;
ALTER TABLE batches ENABLE ROW LEVEL SECURITY;

CREATE POLICY super_admin_all ON faculties FOR ALL TO authenticated USING (has_permission('faculties', 'all', 'all'));
CREATE POLICY super_admin_all ON departments FOR ALL TO authenticated USING (has_permission('departments', 'all', 'all'));
CREATE POLICY super_admin_all ON programs FOR ALL TO authenticated USING (has_permission('programs', 'all', 'all'));
CREATE POLICY super_admin_all ON batches FOR ALL TO authenticated USING (has_permission('batches', 'all', 'all'));

-- Read policies for everyone
CREATE POLICY public_read_faculties ON faculties FOR SELECT TO authenticated USING (true);
CREATE POLICY public_read_departments ON departments FOR SELECT TO authenticated USING (true);
CREATE POLICY public_read_programs ON programs FOR SELECT TO authenticated USING (true);
CREATE POLICY public_read_batches ON batches FOR SELECT TO authenticated USING (true);
