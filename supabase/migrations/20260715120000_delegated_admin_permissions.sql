-- =====================================================================
--  AFOS — Delegated admin: capability-scoped per-user grants + hardening
--  (Workstream 1)
--
--  Builds on the EXISTING RBAC rails (permissions / role_permissions /
--  has_permission / get_my_profile_role) rather than replacing them. All
--  additive: one new table, new permission rows, two new read-only
--  functions, a recreate of handle_new_user (behaviour-preserving except
--  the account_type whitelist), and additive OR-branches on four existing
--  write policies. Nothing existing is removed.
--
--  Verified live before writing (2026-07-15):
--   * super_admin role exists; all admin/teacher/super_admin accounts are
--     is_verified=true, so the new is_verified conjunct locks out nobody.
--   * audit_log already has RLS ENABLED with zero policies (deny-all) —
--     we only add a super_admin SELECT policy; writes go through the
--     SECURITY DEFINER helper which bypasses RLS.
--   * user_permissions and profiles.identity_source do not yet exist.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Per-user capability grants
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_permissions (
  user_id       uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  permission_id uuid NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
  granted_by    uuid REFERENCES profiles(id) ON DELETE SET NULL,
  granted_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, permission_id)
);

ALTER TABLE user_permissions ENABLE ROW LEVEL SECURITY;

-- Only super_admin may grant/revoke. A delegated admin can never widen
-- anyone's powers (including their own) — the whole anti-misuse guarantee
-- rests on this being the single write path.
DROP POLICY IF EXISTS "super_admin_manage_user_permissions" ON user_permissions;
CREATE POLICY "super_admin_manage_user_permissions" ON user_permissions
  FOR ALL TO authenticated
  USING (get_my_profile_role() = 'super_admin')
  WITH CHECK (get_my_profile_role() = 'super_admin');

-- A user may see their own grants; super_admin sees all.
DROP POLICY IF EXISTS "read_own_or_super_admin_user_permissions" ON user_permissions;
CREATE POLICY "read_own_or_super_admin_user_permissions" ON user_permissions
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR get_my_profile_role() = 'super_admin');

-- ---------------------------------------------------------------------
-- 2. Operational permission rows (the delegatable capabilities).
--    resource.action pairs; scope 'all'. Seed + grant to super_admin's
--    role so caller_can/my_capabilities are self-consistent for it
--    (super_admin already passes every role-array check, so no existing
--    behaviour depends on this — belt and suspenders).
-- ---------------------------------------------------------------------
INSERT INTO permissions (resource, action, scope) VALUES
  ('routine',    'upload',  'all'),
  ('exam_seat',  'upload',  'all'),
  ('transport',  'upload',  'all'),
  ('notice',     'publish', 'all'),
  ('library',    'manage',  'all'),
  ('hall',       'manage',  'all'),
  ('sos',        'manage',  'all'),
  ('conference', 'manage',  'all')
ON CONFLICT DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT (SELECT id FROM roles WHERE name = 'super_admin'), p.id
FROM permissions p
WHERE (p.resource, p.action, p.scope) IN (
  ('routine','upload','all'), ('exam_seat','upload','all'),
  ('transport','upload','all'), ('notice','publish','all'),
  ('library','manage','all'), ('hall','manage','all'),
  ('sos','manage','all'), ('conference','manage','all')
)
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------
-- 3. caller_can(resource, action[, user_id]) — the enforcement primitive.
--    True if the user holds the capability via their ROLE (role_permissions)
--    OR a direct per-user grant (user_permissions). Params are p_-prefixed
--    to avoid the column-shadowing bug that broke has_permission (see
--    20260702160000). p_user_id defaults to auth.uid() so RLS policies call
--    it with no third arg; edge functions (service-role client, where
--    auth.uid() is null) pass the JWT-resolved user id explicitly.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION caller_can(p_resource text, p_action text, p_user_id uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM permissions p
    WHERE p.resource = p_resource
      AND p.action = p_action
      AND (
        EXISTS (
          SELECT 1 FROM role_permissions rp
          JOIN profiles pr ON pr.role_id = rp.role_id
          WHERE pr.id = p_user_id AND rp.permission_id = p.id
        )
        OR EXISTS (
          SELECT 1 FROM user_permissions up
          WHERE up.user_id = p_user_id AND up.permission_id = p.id
        )
      )
  );
$$;

-- ---------------------------------------------------------------------
-- 4. my_capabilities() — 'resource.action' strings the caller holds,
--    unioned across role and per-user grants. Backs the client UI gating.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION my_capabilities()
RETURNS text[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT coalesce(array_agg(DISTINCT p.resource || '.' || p.action), ARRAY[]::text[])
  FROM permissions p
  WHERE EXISTS (
      SELECT 1 FROM role_permissions rp
      JOIN profiles pr ON pr.role_id = rp.role_id
      WHERE pr.id = auth.uid() AND rp.permission_id = p.id
    )
    OR EXISTS (
      SELECT 1 FROM user_permissions up
      WHERE up.user_id = auth.uid() AND up.permission_id = p.id
    );
$$;

-- ---------------------------------------------------------------------
-- 5. Append-only audit helper. audit_log already exists with matching
--    columns and RLS enabled (deny-all). Writes flow ONLY through this
--    SECURITY DEFINER function (bypasses RLS); no INSERT policy is added,
--    so nothing else can forge or alter rows.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION log_audit(
  p_table text, p_record_id uuid, p_action text,
  p_old jsonb DEFAULT NULL, p_new jsonb DEFAULT NULL)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  INSERT INTO audit_log (table_name, record_id, action, old_data, new_data, changed_by)
  VALUES (p_table, p_record_id, p_action, p_old, p_new, auth.uid());
$$;

-- super_admin may read the trail; nobody gets INSERT/UPDATE/DELETE (the
-- helper above is the only writer). Append-only accountability.
DROP POLICY IF EXISTS "super_admin_read_audit_log" ON audit_log;
CREATE POLICY "super_admin_read_audit_log" ON audit_log
  FOR SELECT TO authenticated
  USING (get_my_profile_role() = 'super_admin');

-- ---------------------------------------------------------------------
-- 6. handle_new_user() — recreate with an account_type WHITELIST.
--    THE LINCHPIN: this trigger is SECURITY DEFINER and fires on INSERT,
--    which the UPDATE-only protect_profile_privileged_columns trigger does
--    not cover — so a crafted signup with account_type:'super_admin'
--    currently mints a real super_admin. Fail CLOSED on identity: any
--    account_type outside student|teacher|staff collapses to 'student',
--    and the rejection is logged. Everything else is byte-for-byte the
--    prior behaviour (20260708015913).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_requested_type text := coalesce(new.raw_user_meta_data->>'account_type', 'student');
  v_account_type   text;
  v_role_id        uuid;
  v_department_id  uuid;
  v_program_id     uuid;
  v_completed      boolean;
begin
  -- Whitelist: only self-service account types may be self-assigned at
  -- signup. Anything else (super_admin/admin/dept_admin/exam_controller or
  -- a garbage value) is forced to 'student' and recorded.
  if v_requested_type in ('student', 'teacher', 'staff') then
    v_account_type := v_requested_type;
  else
    v_account_type := 'student';
    perform log_audit('auth.users', new.id, 'signup_role_rejected',
      jsonb_build_object('requested_account_type', v_requested_type), NULL);
  end if;

  select id into v_role_id from roles where name = v_account_type;

  select id into v_department_id from departments
    where code = new.raw_user_meta_data->>'department';

  if v_account_type = 'student' and new.raw_user_meta_data->>'program_id' is not null then
    v_program_id := (new.raw_user_meta_data->>'program_id')::uuid;
  end if;

  v_completed := new.raw_user_meta_data->>'full_name' is not null
    and new.raw_user_meta_data->>'department' is not null
    and new.raw_user_meta_data->>'semester' is not null;

  insert into profiles (
    id, email, full_name,
    student_id, university_id,
    department, department_id, semester,
    role, role_id, profile_completed, gender
  ) values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', 'New User'),
    new.raw_user_meta_data->>'university_id',
    new.raw_user_meta_data->>'university_id',
    coalesce(new.raw_user_meta_data->>'department', 'CSE'),
    v_department_id,
    coalesce((new.raw_user_meta_data->>'semester')::int, 1),
    v_account_type,
    v_role_id,
    v_completed,
    new.raw_user_meta_data->>'gender'
  )
  on conflict (id) do update set
    full_name     = case
                      when profiles.full_name = 'New User'
                      then coalesce(excluded.full_name, profiles.full_name)
                      else profiles.full_name
                    end,
    student_id    = coalesce(excluded.student_id,    profiles.student_id),
    university_id = coalesce(excluded.university_id, profiles.university_id),
    department    = coalesce(excluded.department,    profiles.department),
    department_id = coalesce(excluded.department_id, profiles.department_id),
    semester      = coalesce(excluded.semester,      profiles.semester),
    role_id       = coalesce(excluded.role_id,       profiles.role_id),
    gender        = coalesce(excluded.gender,        profiles.gender);

  if v_account_type = 'teacher' then
    insert into teachers (profile_id, department_id, designation)
    values (new.id, v_department_id, new.raw_user_meta_data->>'designation')
    on conflict (profile_id) do update set
      department_id = coalesce(excluded.department_id, teachers.department_id),
      designation   = coalesce(excluded.designation,   teachers.designation);
  elsif v_account_type = 'staff' then
    insert into staff (profile_id, department_id, designation, category)
    values (new.id, v_department_id, new.raw_user_meta_data->>'designation',
            new.raw_user_meta_data->>'staff_category')
    on conflict (profile_id) do update set
      department_id = coalesce(excluded.department_id, staff.department_id),
      designation   = coalesce(excluded.designation,   staff.designation),
      category      = coalesce(excluded.category,      staff.category);
  else
    insert into students (profile_id, department_id, program_id, batch_label, section, current_semester_no, status)
    values (
      new.id, v_department_id, v_program_id,
      new.raw_user_meta_data->>'batch',
      new.raw_user_meta_data->>'section',
      coalesce((new.raw_user_meta_data->>'semester')::int, 1),
      'active'
    )
    on conflict (profile_id) do update set
      department_id        = coalesce(excluded.department_id, students.department_id),
      program_id           = coalesce(excluded.program_id, students.program_id),
      batch_label           = coalesce(excluded.batch_label, students.batch_label),
      section               = coalesce(excluded.section, students.section),
      current_semester_no   = coalesce(excluded.current_semester_no, students.current_semester_no);
  end if;

  return new;
end;
$function$;

-- ---------------------------------------------------------------------
-- 7. Extend the four operational write gates: existing role-array OR the
--    matching capability, AND the writer must be a verified account. The
--    OR keeps every current admin/teacher/dept_admin/exam_controller path
--    working; the caller_can branch enables delegated grantees; the
--    is_verified conjunct blocks an unverified account from writing even
--    via a hand-crafted request. All confirmed verified-safe in Phase 0.
-- ---------------------------------------------------------------------

-- 7a. schedule_slots (routine.upload)
DROP POLICY IF EXISTS "admin_write_schedule" ON schedule_slots;
CREATE POLICY "admin_write_schedule" ON schedule_slots FOR ALL TO authenticated USING (
  EXISTS (SELECT 1 FROM profiles
          WHERE profiles.id = auth.uid()
            AND profiles.is_verified
            AND (profiles.role = ANY (ARRAY['admin','teacher','dept_admin','super_admin'])
                 OR caller_can('routine','upload')))
);

-- 7b. transport_routes (transport.upload)
DROP POLICY IF EXISTS "admin_write_routes" ON transport_routes;
CREATE POLICY "admin_write_routes" ON transport_routes FOR ALL TO authenticated USING (
  EXISTS (SELECT 1 FROM profiles
          WHERE profiles.id = auth.uid()
            AND profiles.is_verified
            AND (profiles.role = ANY (ARRAY['admin','teacher','dept_admin','super_admin'])
                 OR caller_can('transport','upload')))
);

-- 7c. notices INSERT (notice.publish)
DROP POLICY IF EXISTS "admin_write_notices" ON notices;
CREATE POLICY "admin_write_notices" ON notices FOR INSERT TO authenticated WITH CHECK (
  EXISTS (SELECT 1 FROM profiles
          WHERE profiles.id = auth.uid()
            AND profiles.is_verified
            AND (profiles.role = ANY (ARRAY['admin','teacher','dept_admin','super_admin'])
                 OR caller_can('notice','publish')))
);

-- 7d. exam_seat_assignments (exam_seat.upload)
DROP POLICY IF EXISTS "admin_seats" ON exam_seat_assignments;
CREATE POLICY "admin_seats" ON exam_seat_assignments FOR ALL TO authenticated USING (
  EXISTS (SELECT 1 FROM profiles
          WHERE profiles.id = auth.uid()
            AND profiles.is_verified
            AND (profiles.role = ANY (ARRAY['admin','super_admin','exam_controller'])
                 OR caller_can('exam_seat','upload')))
);

-- 7e. exam_room_allocations (exam_seat.upload) — the other exam write path
DROP POLICY IF EXISTS "admin_write_exam_room_allocations" ON exam_room_allocations;
CREATE POLICY "admin_write_exam_room_allocations" ON exam_room_allocations FOR ALL TO authenticated USING (
  EXISTS (SELECT 1 FROM profiles
          WHERE profiles.id = auth.uid()
            AND profiles.is_verified
            AND (profiles.role = ANY (ARRAY['admin','dept_admin','super_admin','exam_controller'])
                 OR caller_can('exam_seat','upload')))
);

-- ---------------------------------------------------------------------
-- 8. DIU-SSO seam (design only — no flow built; blocked on DIU providing
--    an identity API). Lets a future SSO map each account to a real
--    university identity, ending self-declared roles entirely.
-- ---------------------------------------------------------------------
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS identity_source text NOT NULL DEFAULT 'self';
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS external_uid text;
COMMENT ON COLUMN profiles.identity_source IS
  'How this account was authenticated: ''self'' (self-signup, current) or a future SSO provider key (e.g. ''diu_sso''). Reserved for university identity integration.';
COMMENT ON COLUMN profiles.external_uid IS
  'Stable university-side identifier for this account when identity_source is an SSO provider; NULL for self-signup. Reserved for university identity integration.';
