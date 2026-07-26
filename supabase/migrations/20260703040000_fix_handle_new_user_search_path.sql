-- =====================================================================
--  AFOS — Fix handle_new_user() failing on every real signup
--  Root cause: the GoTrue role (supabase_auth_admin) that fires triggers
--  on auth.users has search_path='auth' only — it cannot see the public
--  schema. handle_new_user() referenced profiles/roles/departments/
--  students/teachers unqualified, so under GoTrue's actual signup path
--  (not a superuser session) those names failed to resolve, causing
--  Postgres errors that GoTrue always flattens into the same opaque
--  "Database error saving new user" / unexpected_failure response.
--  Confirmed by swapping in a no-op handle_new_user() and observing
--  signup succeed immediately.
-- =====================================================================

CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
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

-- auto_confirm_email() only touches NEW.email_confirmed_at (no public-schema
-- refs), but pin its search_path too so it's not silently dependent on the
-- caller's session state either.
CREATE OR REPLACE FUNCTION auto_confirm_email()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  NEW.email_confirmed_at := COALESCE(NEW.email_confirmed_at, now());
  RETURN NEW;
END;
$$;
