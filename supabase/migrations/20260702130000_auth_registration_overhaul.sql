-- =====================================================================
--  AFOS — Auth/Registration overhaul
--  Seeds roles, adds program/student columns, enforces edu.bd email
--  domain (with allowlist), and makes handle_new_user() role-aware.
-- =====================================================================

-- ── 1. Seed roles (never seeded by any prior migration) ──────────────
INSERT INTO roles (name, description, is_system) VALUES
  ('student',     'Enrolled student',                 true),
  ('teacher',     'Teaching staff / faculty',          true),
  ('admin',       'Department or module administrator', true),
  ('super_admin', 'Full system access',                true)
ON CONFLICT (name) DO NOTHING;

-- ── 1b. Seed a default faculty + departments + one program each ──────
-- (departments/programs are never seeded elsewhere; without this the
--  new DB-driven registration dropdowns would be empty. total_semesters
--  / semester_system are left NULL — real DIU per-program figures need
--  to be entered by an admin; see plan notes.)
INSERT INTO faculties (name, code) VALUES
  ('Daffodil International University', 'DIU')
ON CONFLICT (code) DO NOTHING;

INSERT INTO departments (faculty_id, name, code)
SELECT f.id, d.name, d.code
FROM (VALUES
  ('Computer Science and Engineering', 'CSE'),
  ('Electrical and Electronic Engineering', 'EEE'),
  ('Business Administration', 'BBA'),
  ('English', 'English'),
  ('Law', 'Law'),
  ('Architecture', 'Architecture'),
  ('Pharmacy', 'Pharmacy'),
  ('Textile Engineering', 'Textile'),
  ('Civil Engineering', 'Civil'),
  ('Information and Communication Engineering', 'ICE'),
  ('Multimedia and Creative Technology', 'MCJ'),
  ('Mathematics', 'Mathematics')
) AS d(name, code)
CROSS JOIN (SELECT id FROM faculties WHERE code = 'DIU') f
ON CONFLICT (code) DO NOTHING;

INSERT INTO programs (department_id, name, degree_type, total_credits)
SELECT d.id, d.name || ' (Bachelor)', 'Bachelor', NULL
FROM departments d
WHERE NOT EXISTS (SELECT 1 FROM programs p WHERE p.department_id = d.id);

-- ── 2. Schema additions ───────────────────────────────────────────────
ALTER TABLE programs ADD COLUMN IF NOT EXISTS total_semesters int;
ALTER TABLE programs ADD COLUMN IF NOT EXISTS semester_system text
  CHECK (semester_system IN ('bi','tri'));

ALTER TABLE students ADD COLUMN IF NOT EXISTS batch_label text;
ALTER TABLE students ADD COLUMN IF NOT EXISTS section text;

-- ── 3. Email domain enforcement ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS auth_email_domain_allowlist (
  email text PRIMARY KEY
);
INSERT INTO auth_email_domain_allowlist (email)
VALUES ('rakibhassan.rh68@gmail.com')
ON CONFLICT (email) DO NOTHING;

CREATE OR REPLACE FUNCTION enforce_email_domain()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NEW.email NOT ILIKE '%edu.bd' AND NOT EXISTS (
    SELECT 1 FROM auth_email_domain_allowlist WHERE email = NEW.email
  ) THEN
    RAISE EXCEPTION 'Registration is restricted to university (edu.bd) email addresses.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_email_domain_trigger ON auth.users;
CREATE TRIGGER enforce_email_domain_trigger
  BEFORE INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION enforce_email_domain();

-- ── 4. Rewrite handle_new_user() to be role/account-type aware ───────
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_account_type   text := COALESCE(NEW.raw_user_meta_data->>'account_type', 'student');
  v_role_id        uuid;
  v_department_id  uuid;
  v_program_id     uuid;
BEGIN
  SELECT id INTO v_role_id FROM roles WHERE name = v_account_type;

  SELECT id INTO v_department_id FROM departments
    WHERE code = NEW.raw_user_meta_data->>'department';

  IF v_account_type = 'student' AND NEW.raw_user_meta_data->>'program_id' IS NOT NULL THEN
    v_program_id := (NEW.raw_user_meta_data->>'program_id')::uuid;
  END IF;

  INSERT INTO profiles (
    id, email, full_name,
    student_id, university_id,
    department, department_id, semester,
    role, role_id
  ) VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', 'New User'),
    NEW.raw_user_meta_data->>'university_id',
    NEW.raw_user_meta_data->>'university_id',
    COALESCE(NEW.raw_user_meta_data->>'department', 'CSE'),
    v_department_id,
    COALESCE((NEW.raw_user_meta_data->>'semester')::int, 1),
    v_account_type,
    v_role_id
  )
  ON CONFLICT (id) DO UPDATE SET
    full_name     = CASE
                      WHEN profiles.full_name = 'New User'
                      THEN COALESCE(EXCLUDED.full_name, profiles.full_name)
                      ELSE profiles.full_name
                    END,
    student_id    = COALESCE(EXCLUDED.student_id,    profiles.student_id),
    university_id = COALESCE(EXCLUDED.university_id, profiles.university_id),
    department    = COALESCE(EXCLUDED.department,    profiles.department),
    department_id = COALESCE(EXCLUDED.department_id, profiles.department_id),
    semester      = COALESCE(EXCLUDED.semester,      profiles.semester),
    role_id       = COALESCE(EXCLUDED.role_id,       profiles.role_id);

  IF v_account_type = 'teacher' THEN
    INSERT INTO teachers (profile_id, department_id, designation)
    VALUES (NEW.id, v_department_id, NEW.raw_user_meta_data->>'designation')
    ON CONFLICT (profile_id) DO UPDATE SET
      department_id = COALESCE(EXCLUDED.department_id, teachers.department_id),
      designation   = COALESCE(EXCLUDED.designation,   teachers.designation);
  ELSE
    INSERT INTO students (profile_id, department_id, program_id, batch_label, section, current_semester_no, status)
    VALUES (
      NEW.id, v_department_id, v_program_id,
      NEW.raw_user_meta_data->>'batch',
      NEW.raw_user_meta_data->>'section',
      COALESCE((NEW.raw_user_meta_data->>'semester')::int, 1),
      'active'
    )
    ON CONFLICT (profile_id) DO UPDATE SET
      department_id        = COALESCE(EXCLUDED.department_id, students.department_id),
      program_id            = COALESCE(EXCLUDED.program_id, students.program_id),
      batch_label            = COALESCE(EXCLUDED.batch_label, students.batch_label),
      section                = COALESCE(EXCLUDED.section, students.section),
      current_semester_no    = COALESCE(EXCLUDED.current_semester_no, students.current_semester_no);
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- ── 5. Patch existing profiles missing role_id ────────────────────────
UPDATE profiles
SET role_id = (SELECT id FROM roles WHERE name = 'student')
WHERE role_id IS NULL AND role = 'student';
