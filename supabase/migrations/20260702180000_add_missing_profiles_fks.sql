-- =====================================================================
--  AFOS — Add missing FK constraints on profiles.role_id / department_id
--  Both columns were added as bare `uuid` (ALTER TABLE ... ADD COLUMN)
--  with no REFERENCES clause, so PostgREST had no formal relationship
--  to use for `roles(name)`/`departments(...)` embeds. It silently fell
--  back to the only real FK between profiles/roles — the unrelated
--  reverse link roles.created_by -> profiles.id (a to-many relationship)
--  — returning an empty list instead of the expected single role,
--  which crashed the client on `j['roles']?['name']`.
-- =====================================================================

ALTER TABLE profiles
  ADD CONSTRAINT profiles_role_id_fkey
  FOREIGN KEY (role_id) REFERENCES roles(id);

ALTER TABLE profiles
  ADD CONSTRAINT profiles_department_id_fkey
  FOREIGN KEY (department_id) REFERENCES departments(id);

NOTIFY pgrst, 'reload schema';
