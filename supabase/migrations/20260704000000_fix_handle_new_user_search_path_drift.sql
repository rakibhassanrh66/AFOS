-- =====================================================================
--  AFOS — Re-fix handle_new_user()/get_my_profile_role() search_path
--
--  Root cause (confirmed by querying the live DB, not by assumption):
--  supabase_auth_admin (the role GoTrue uses to fire triggers on
--  auth.users) has search_path='auth' only. handle_new_user() and
--  get_my_profile_role() reference public-schema tables unqualified,
--  so under that role those names fail to resolve -> Postgres error
--  -> GoTrue flattens it into "Database error saving new user" (500)
--  on every signup.
--
--  This was already fixed once in 20260703040000_fix_handle_new_user_
--  search_path.sql and 20260703060000_pin_search_path_all_security_
--  definer.sql, and supabase migration list confirms both are marked
--  applied on remote. But pulling the live pg_proc definitions showed
--  handle_new_user() and get_my_profile_role() had reverted to their
--  pre-fix bodies (no SET search_path) while their sibling functions
--  from the same migration files (auto_confirm_email, has_permission,
--  approve_grade_change, calculate_semester_sgpa) kept the fix. A
--  migration transaction cannot partially apply, so these two were
--  almost certainly overwritten afterwards by ad-hoc SQL run outside
--  the migration system (e.g. the Supabase Dashboard SQL Editor).
--
--  ACTION ITEM (process, not SQL): stop making schema/function changes
--  via the Dashboard SQL Editor directly against production. Every
--  change must go through a migration file + `supabase db push`, or
--  the migration history will keep lying about what's actually live.
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
      department_id       = COALESCE(EXCLUDED.department_id, students.department_id),
      program_id           = COALESCE(EXCLUDED.program_id, students.program_id),
      batch_label           = COALESCE(EXCLUDED.batch_label, students.batch_label),
      section               = COALESCE(EXCLUDED.section, students.section),
      current_semester_no   = COALESCE(EXCLUDED.current_semester_no, students.current_semester_no);
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION get_my_profile_role()
RETURNS text LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public, pg_temp
AS $$ SELECT role FROM profiles WHERE id = auth.uid(); $$;

-- Verification: fail the migration loudly if either function still
-- lacks a pinned search_path after this runs, instead of silently
-- drifting again.
DO $$
DECLARE
  missing text;
BEGIN
  SELECT string_agg(p.proname, ', ') INTO missing
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname IN ('handle_new_user', 'get_my_profile_role')
    AND p.proconfig IS NULL;

  IF missing IS NOT NULL THEN
    RAISE EXCEPTION 'search_path pin failed to apply to: %', missing;
  END IF;
END;
$$;
