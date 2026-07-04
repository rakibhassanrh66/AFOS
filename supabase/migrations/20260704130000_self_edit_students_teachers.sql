-- =====================================================================
--  AFOS — Let users self-edit their own students/teachers row
--
--  Found by testing the profile-completion save flow live: neither table
--  had ANY self-service UPDATE policy — only has_permission-gated admin
--  writes existed. A student/teacher editing their own department,
--  batch, section, or designation silently matched zero rows (200 OK,
--  empty result) rather than erroring, which would have made the save
--  flow look like it worked while quietly doing nothing.
--
--  status/cgpa on students are administrative/computed fields and must
--  stay out of self-service reach — a trigger blocks changes to them
--  unless the caller already has admin-level students permission.
-- =====================================================================

CREATE POLICY "own_student_update" ON students FOR UPDATE
  USING (profile_id = auth.uid())
  WITH CHECK (profile_id = auth.uid());

CREATE POLICY "own_teacher_update" ON teachers FOR UPDATE
  USING (profile_id = auth.uid())
  WITH CHECK (profile_id = auth.uid());

CREATE OR REPLACE FUNCTION protect_student_admin_columns()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF (NEW.status IS DISTINCT FROM OLD.status OR NEW.cgpa IS DISTINCT FROM OLD.cgpa)
     AND NOT has_permission('students', 'all', 'all')
  THEN
    RAISE EXCEPTION 'Not authorized to change status or cgpa.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS protect_student_admin_columns_trigger ON students;
CREATE TRIGGER protect_student_admin_columns_trigger
  BEFORE UPDATE ON students
  FOR EACH ROW EXECUTE FUNCTION protect_student_admin_columns();
