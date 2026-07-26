-- Needed to notify affected students after an exam seat-plan PDF upload —
-- exam_controller has no direct `students` table permission (only admin/
-- dept_admin/super_admin do), same reasoning as list_exam_candidates,
-- but that RPC was scoped to the old exam_id-based model and is no longer
-- called from anywhere now that seat plans are batch+section based.
CREATE OR REPLACE FUNCTION public.list_students_by_batch_section(p_batch text, p_section text)
RETURNS TABLE(profile_id uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  caller_role text;
BEGIN
  SELECT role INTO caller_role FROM profiles WHERE id = auth.uid();
  IF caller_role NOT IN ('admin', 'dept_admin', 'super_admin', 'exam_controller') THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  RETURN QUERY
    SELECT s.profile_id FROM students s
    WHERE s.batch_label = p_batch AND s.section = p_section;
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_students_by_batch_section(text, text) TO authenticated;
