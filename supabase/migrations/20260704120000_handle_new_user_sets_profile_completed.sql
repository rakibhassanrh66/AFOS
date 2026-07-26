-- =====================================================================
--  AFOS — handle_new_user() sets profile_completed based on real data
--
--  profile_completed should reflect whether the signup actually supplied
--  full_name/department/semester (the current 3-step register form
--  requires all of these), not the COALESCE-defaulted fallback values —
--  otherwise every fresh signup would be force-gated into the completion
--  screen for no reason. Grandfathered/incomplete accounts (missing this
--  metadata, e.g. from an older signup path) correctly stay incomplete.
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
  v_completed      boolean;
BEGIN
  SELECT id INTO v_role_id FROM roles WHERE name = v_account_type;

  SELECT id INTO v_department_id FROM departments
    WHERE code = NEW.raw_user_meta_data->>'department';

  IF v_account_type = 'student' AND NEW.raw_user_meta_data->>'program_id' IS NOT NULL THEN
    v_program_id := (NEW.raw_user_meta_data->>'program_id')::uuid;
  END IF;

  v_completed := NEW.raw_user_meta_data->>'full_name' IS NOT NULL
    AND NEW.raw_user_meta_data->>'department' IS NOT NULL
    AND NEW.raw_user_meta_data->>'semester' IS NOT NULL;

  INSERT INTO profiles (
    id, email, full_name,
    student_id, university_id,
    department, department_id, semester,
    role, role_id, profile_completed
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
    v_role_id,
    v_completed
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
      program_id           = COALESCE(EXCLUDED.program_id, students.program_id),
      batch_label           = COALESCE(EXCLUDED.batch_label, students.batch_label),
      section               = COALESCE(EXCLUDED.section, students.section),
      current_semester_no   = COALESCE(EXCLUDED.current_semester_no, students.current_semester_no);
  END IF;

  RETURN NEW;
END;
$$;
