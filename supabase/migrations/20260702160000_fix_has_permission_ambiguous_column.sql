-- =====================================================================
--  AFOS — Fix has_permission() ambiguous column reference
--  The function's parameters (resource, action, scope) share names with
--  the `permissions` table columns they're compared against. Postgres
--  can't disambiguate an unqualified reference between a plpgsql
--  parameter and a table column, so any RLS policy calling this
--  function throws instead of evaluating — breaking every query that
--  touches a table gated by it, including the students/teachers join
--  on login.
-- =====================================================================

CREATE OR REPLACE FUNCTION has_permission(resource text, action text, scope text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM role_permissions rp
    JOIN permissions p ON rp.permission_id = p.id
    JOIN profiles pr ON pr.role_id = rp.role_id
    WHERE pr.id = auth.uid()
      AND p.resource = has_permission.resource
      AND p.action = has_permission.action
      AND p.scope = has_permission.scope
  );
END;
$$;
