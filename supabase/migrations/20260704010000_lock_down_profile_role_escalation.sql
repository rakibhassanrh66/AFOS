-- =====================================================================
--  AFOS — CRITICAL: close self-role-escalation hole on profiles
--
--  Confirmed exploitable: "Users can manage own profile" (ALL, USING/
--  WITH CHECK auth.uid() = id) plus base GRANTs give every authenticated
--  user UPDATE on profiles.role and profiles.role_id. RLS only guards
--  which ROW you can touch, not which COLUMNS — so any signed-up user
--  can run:
--      UPDATE profiles SET role = 'super_admin' WHERE id = auth.uid();
--  via the client SDK and instantly gain Super Admin, since has_permission()
--  and many policies trust profiles.role/role_id unconditionally.
--
--  Fix: a BEFORE UPDATE trigger blocks any change to role/role_id/
--  is_verified unless the acting session already has admin/super_admin
--  privilege, with a bootstrap exception for filling in a NULL role_id
--  (covers handle_new_user's ON CONFLICT DO UPDATE idempotency path).
--  A companion RLS policy grants admin/super_admin UPDATE access to
--  OTHER users' profiles, since no such policy existed before this —
--  meaning "approve teacher" / "assign role" via the GUI had no DB path
--  to actually work.
--
--  Also tightened: the "Allow profile creation during signup" INSERT
--  policy had WITH CHECK (true) for anon+authenticated, letting anyone
--  insert a fabricated profile row for an arbitrary id. Restricted to
--  auth.uid() = id (the trigger-based signup path is SECURITY DEFINER
--  and bypasses RLS entirely as table owner, so this doesn't affect it).
--
--  Also tightened: user_notifications "system_insert" had WITH CHECK
--  (true) for role public (anon+authenticated), letting any caller
--  inject a fake notification for any user_id. No client code in this
--  repo inserts into user_notifications directly (verified via grep),
--  so this is restricted to self-insert or admin/faculty-driven inserts
--  with no functional impact.
-- =====================================================================

CREATE OR REPLACE FUNCTION protect_profile_privileged_columns()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF (NEW.role IS DISTINCT FROM OLD.role
      OR NEW.role_id IS DISTINCT FROM OLD.role_id
      OR NEW.is_verified IS DISTINCT FROM OLD.is_verified)
     AND OLD.role_id IS NOT NULL
     AND NOT (get_my_profile_role() = ANY (ARRAY['admin', 'super_admin']))
  THEN
    RAISE EXCEPTION 'Not authorized to change role, role_id, or is_verified.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS protect_profile_privileged_columns_trigger ON profiles;
CREATE TRIGGER protect_profile_privileged_columns_trigger
  BEFORE UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION protect_profile_privileged_columns();

-- Admins/super_admins need an actual RLS path to update OTHER users'
-- profiles (approve teacher, assign role, ban, etc) — none existed.
CREATE POLICY "admin_manage_all_profiles" ON profiles FOR UPDATE
  USING (get_my_profile_role() = ANY (ARRAY['admin', 'super_admin']))
  WITH CHECK (get_my_profile_role() = ANY (ARRAY['admin', 'super_admin']));

-- Tighten the signup INSERT policy: was WITH CHECK (true).
DROP POLICY IF EXISTS "Allow profile creation during signup" ON profiles;
CREATE POLICY "Allow profile creation during signup" ON profiles
  FOR INSERT TO anon, authenticated
  WITH CHECK (auth.uid() = id);

-- Tighten user_notifications insert: was WITH CHECK (true) for public.
DROP POLICY IF EXISTS "system_insert" ON user_notifications;
CREATE POLICY "system_insert" ON user_notifications FOR INSERT
  WITH CHECK (
    auth.uid() = user_id
    OR get_my_profile_role() = ANY (ARRAY['admin', 'faculty', 'super_admin'])
  );
