-- Gender field (required going forward, editable for existing users).
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS gender text CHECK (gender IN ('male', 'female'));

-- Teacher-initials uniqueness (case-insensitive) — real-world collisions
-- (e.g. two "Mizanur Rahman"s both wanting "MR") need to be caught before
-- they silently corrupt schedule_slots.teacher_initial matching.
CREATE UNIQUE INDEX IF NOT EXISTS profiles_teacher_initial_unique
  ON profiles (upper(teacher_initial))
  WHERE teacher_initial IS NOT NULL AND teacher_initial <> '';

-- New-user approval gate. `is_verified` already existed (from 001_init.sql)
-- and was already protected by protect_profile_privileged_columns_trigger
-- (self-changes blocked), but nothing ever read or set it — grandfather
-- every account that exists as of this migration as already-approved, so
-- only accounts created after this point actually go through the new
-- pending-approval gate (handle_new_user's INSERT relies on the column's
-- existing DEFAULT FALSE, so no trigger change needed for new signups).
UPDATE profiles SET is_verified = true WHERE is_verified = false;

-- Update handle_new_user to also persist gender from signup metadata.
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
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
    role, role_id, profile_completed, gender
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
    v_completed,
    NEW.raw_user_meta_data->>'gender'
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
    role_id       = COALESCE(EXCLUDED.role_id,       profiles.role_id),
    gender        = COALESCE(EXCLUDED.gender,        profiles.gender);

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
