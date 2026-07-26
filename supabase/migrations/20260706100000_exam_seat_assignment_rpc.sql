-- Exam seat plan feature had no way for anyone to actually populate
-- exam_seat_assignments (0 rows live, despite exams already having 32 real
-- rows from routine upload) — this RPC resolves which students match a
-- given exam's department+batch+section so the new admin screen can
-- bulk-assign seats. Narrow SECURITY DEFINER read, same pattern as the
-- existing find_section_cr/list_section_students RPCs: exam_controller has
-- no direct `students` table permission (confirmed live via role_permissions
-- — only admin/dept_admin/super_admin do), but IS one of the three roles
-- already allowed to write exam_seat_assignments (see admin_seats policy),
-- so a direct table grant would be broader than this feature needs.
CREATE OR REPLACE FUNCTION public.list_exam_candidates(p_exam_id uuid)
RETURNS TABLE(profile_id uuid, full_name text, university_id text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  caller_role text;
  v_dept text; v_batch text; v_section text;
BEGIN
  SELECT role INTO caller_role FROM profiles WHERE id = auth.uid();
  IF caller_role NOT IN ('admin', 'dept_admin', 'super_admin', 'exam_controller') THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  SELECT department, batch, section INTO v_dept, v_batch, v_section
  FROM exams WHERE id = p_exam_id;

  RETURN QUERY
    SELECT s.profile_id, p.full_name, p.university_id
    FROM students s
    JOIN profiles p ON p.id = s.profile_id
    JOIN departments d ON d.id = s.department_id
    WHERE d.code = v_dept AND s.batch_label = v_batch AND s.section = v_section
    ORDER BY p.full_name;
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_exam_candidates(uuid) TO authenticated;
