-- Teachers have no RLS read path on `students` at all (only admin-tier
-- roles do, department-scoped) — rather than widening that grant just for
-- this lookup (which would expose every student's cgpa/status to any
-- teacher), a narrow SECURITY DEFINER function returns only the CR's id
-- and name for a given department+batch+section, nothing else.
CREATE OR REPLACE FUNCTION find_section_cr(p_department_code text, p_batch text, p_section text)
RETURNS TABLE (id uuid, full_name text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN QUERY
  SELECT p.id, p.full_name
  FROM students s
  JOIN profiles p ON p.id = s.profile_id
  JOIN departments d ON d.id = s.department_id
  WHERE d.code = p_department_code
    AND s.batch_label = p_batch
    AND s.section = p_section
    AND s.is_cr = true
  LIMIT 1;
END;
$$;

GRANT EXECUTE ON FUNCTION find_section_cr(text, text, text) TO authenticated;
