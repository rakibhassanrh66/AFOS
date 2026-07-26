-- =====================================================================
--  AFOS — Fix: RLS infinite recursion + handle_new_user trigger
--  Applied via: supabase db query --linked --file <this-file>
-- =====================================================================

-- ── Fix 0: Add missing updated_at column (broken trigger existed) ────
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT NOW();

-- ── Fix 1: Remove the policy that causes infinite recursion ──────────
DROP POLICY IF EXISTS "admin_read_all" ON profiles;

-- SECURITY DEFINER helper — reads role without triggering RLS recursion
CREATE OR REPLACE FUNCTION get_my_profile_role()
RETURNS text LANGUAGE sql SECURITY DEFINER STABLE AS
$$ SELECT role FROM profiles WHERE id = auth.uid(); $$;

-- Recreate the policy using the helper
CREATE POLICY "admin_read_all" ON profiles FOR SELECT USING (
  auth.uid() = id
  OR get_my_profile_role() IN ('admin', 'faculty', 'super_admin')
);

-- ── Fix 2: Update trigger to save ALL registration metadata ──────────
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  student_role_id uuid;
BEGIN
  SELECT id INTO student_role_id FROM roles WHERE name = 'student';

  INSERT INTO profiles (
    id, email, full_name,
    student_id, university_id,
    department, semester,
    role, role_id
  ) VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', 'New User'),
    NEW.raw_user_meta_data->>'student_id',
    NEW.raw_user_meta_data->>'student_id',
    COALESCE(NEW.raw_user_meta_data->>'department', 'CSE'),
    COALESCE((NEW.raw_user_meta_data->>'semester')::int, 1),
    'student',
    student_role_id
  )
  ON CONFLICT (id) DO UPDATE SET
    full_name     = CASE
                      WHEN profiles.full_name = 'New User'
                      THEN COALESCE(EXCLUDED.full_name, profiles.full_name)
                      ELSE profiles.full_name
                    END,
    student_id    = COALESCE(EXCLUDED.student_id,   profiles.student_id),
    university_id = COALESCE(EXCLUDED.university_id, profiles.university_id),
    department    = COALESCE(EXCLUDED.department,    profiles.department),
    semester      = COALESCE(EXCLUDED.semester,      profiles.semester),
    role_id       = COALESCE(EXCLUDED.role_id,       profiles.role_id);

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- ── Fix 3: Patch existing profiles missing role_id ───────────────────
UPDATE profiles
SET role_id = (SELECT id FROM roles WHERE name = 'student')
WHERE role_id IS NULL AND role = 'student';
