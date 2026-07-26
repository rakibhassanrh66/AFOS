-- Class Representative (CR) system: one CR per department+batch+section,
-- students can only request CR for their own section, and a section can
-- never exceed 50 students.

ALTER TABLE students ADD COLUMN IF NOT EXISTS is_cr boolean NOT NULL DEFAULT false;
ALTER TABLE students ADD COLUMN IF NOT EXISTS cr_since timestamptz;

-- Only one active CR per section — approving a second request for an
-- already-represented section fails this instead of silently doubling up.
CREATE UNIQUE INDEX IF NOT EXISTS one_cr_per_section
  ON students (department_id, batch_label, section)
  WHERE is_cr = true;

-- A section already over 50 (grandfathered data) can stay over 50, but no
-- further student can be added into it — this only ever blocks growth
-- past the cap, never breaks existing enrollment.
CREATE OR REPLACE FUNCTION enforce_section_cap()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_count integer;
BEGIN
  IF NEW.batch_label IS NULL OR NEW.section IS NULL OR NEW.department_id IS NULL THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE'
     AND NEW.department_id IS NOT DISTINCT FROM OLD.department_id
     AND NEW.batch_label IS NOT DISTINCT FROM OLD.batch_label
     AND NEW.section IS NOT DISTINCT FROM OLD.section THEN
    RETURN NEW;
  END IF;
  SELECT count(*) INTO v_count FROM students
    WHERE department_id = NEW.department_id
      AND batch_label = NEW.batch_label
      AND section = NEW.section
      AND profile_id <> NEW.profile_id;
  IF v_count >= 50 THEN
    RAISE EXCEPTION 'Section % (batch %) already has 50 students.', NEW.section, NEW.batch_label;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_section_cap_trigger ON students;
CREATE TRIGGER enforce_section_cap_trigger
  BEFORE INSERT OR UPDATE OF department_id, batch_label, section ON students
  FOR EACH ROW EXECUTE FUNCTION enforce_section_cap();

CREATE TABLE cr_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  department_id uuid NOT NULL REFERENCES departments(id),
  batch_label text NOT NULL,
  section text NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  rejection_reason text,
  reviewed_by uuid REFERENCES profiles(id) ON DELETE SET NULL,
  reviewed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE cr_requests ENABLE ROW LEVEL SECURITY;

-- A student may only ever request CR for the batch/section/department
-- their own students row is actually in — never an arbitrary one.
CREATE POLICY own_cr_request_insert ON cr_requests
  FOR INSERT
  WITH CHECK (
    auth.uid() = student_id
    AND EXISTS (
      SELECT 1 FROM students s
      WHERE s.profile_id = auth.uid()
        AND s.department_id = cr_requests.department_id
        AND s.batch_label = cr_requests.batch_label
        AND s.section = cr_requests.section
    )
  );

CREATE POLICY own_cr_request_read ON cr_requests
  FOR SELECT
  USING (auth.uid() = student_id);

CREATE POLICY super_admin_manage_cr_requests ON cr_requests
  FOR ALL
  USING (get_my_profile_role() = 'super_admin')
  WITH CHECK (get_my_profile_role() = 'super_admin');
