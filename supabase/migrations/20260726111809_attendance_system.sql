-- Attendance.
--
-- Greenfield: before this migration the word "attendance" existed in exactly
-- one place in the whole system, `marks.attendance_marks`, an unconstrained
-- numeric that nothing ever wrote. There was no session, no record, no roster.
--
-- Shape of the problem:
--   * A theory course is taken for the whole section (~50 students, already
--     enforced by enforce_section_cap()).
--   * A lab is taken for one half at a time -- two groups of ~25. The routine
--     side has modelled this for a while (schedule_slots.lab_subgroup,
--     course_offering_meetings.lab_subgroup, both CHECK IN (1,2)), and
--     parse-routine already splits "M1" into section 'M' + subgroup 1. What
--     was missing is the other half of the mapping: nothing said WHICH half a
--     given student is in. enrollments.lab_subgroup below is that piece.
--   * Group labels are batch||section||subgroup, so batch 63 section M gives
--     lab groups 63M1 and 63M2. Derived for display, never stored.

-- ---------------------------------------------------------------- lab groups

ALTER TABLE enrollments ADD COLUMN IF NOT EXISTS lab_subgroup smallint;
ALTER TABLE enrollments DROP CONSTRAINT IF EXISTS enrollments_lab_subgroup_check;
ALTER TABLE enrollments ADD CONSTRAINT enrollments_lab_subgroup_check
  CHECK (lab_subgroup IS NULL OR lab_subgroup IN (1, 2));

COMMENT ON COLUMN enrollments.lab_subgroup IS
  'Which half of a lab section this student sits in (1 or 2). NULL for theory '
  'offerings, and for lab enrolments not yet split into groups.';

-- ----------------------------------------------------------------- sessions

CREATE TABLE IF NOT EXISTS attendance_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  offering_id uuid NOT NULL REFERENCES course_offerings(id) ON DELETE CASCADE,
  session_date date NOT NULL DEFAULT CURRENT_DATE,
  -- NULL = the whole section (theory). 1/2 = one lab group.
  lab_subgroup smallint,
  topic text,
  taken_by uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT attendance_sessions_lab_subgroup_check
    CHECK (lab_subgroup IS NULL OR lab_subgroup IN (1, 2)),
  CONSTRAINT attendance_sessions_topic_len CHECK (topic IS NULL OR length(topic) <= 200)
);

-- COALESCE, not a plain UNIQUE: two NULL lab_subgroups do NOT collide in a
-- unique constraint, so a plain one would happily allow two theory sessions
-- for the same offering on the same day -- which is exactly the double-entry
-- this is meant to stop.
CREATE UNIQUE INDEX IF NOT EXISTS attendance_sessions_unique_slot
  ON attendance_sessions (offering_id, session_date, COALESCE(lab_subgroup, 0));

CREATE INDEX IF NOT EXISTS attendance_sessions_offering_date_idx
  ON attendance_sessions (offering_id, session_date DESC);

-- ------------------------------------------------------------------ records

CREATE TABLE IF NOT EXISTS attendance_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id uuid NOT NULL REFERENCES attendance_sessions(id) ON DELETE CASCADE,
  student_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'present'
    CHECK (status IN ('present', 'absent', 'late', 'excused')),
  -- Reward/bonus attendance credit, e.g. for answering in class. Capped so a
  -- slip of the finger can't hand out an unbounded score; it is a bonus on top
  -- of presence, not a substitute for it.
  bonus numeric(4, 2) NOT NULL DEFAULT 0 CHECK (bonus >= 0 AND bonus <= 5),
  note text,
  marked_by uuid REFERENCES profiles(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT attendance_records_note_len CHECK (note IS NULL OR length(note) <= 200),
  UNIQUE (session_id, student_id)
);

CREATE INDEX IF NOT EXISTS attendance_records_student_idx
  ON attendance_records (student_id);

-- --------------------------------------------------------------- updated_at
--
-- Attendance is explicitly editable after the fact (a teacher marking the
-- wrong row is the normal case this has to survive), so knowing when a row was
-- last touched is part of the audit story rather than decoration.

CREATE OR REPLACE FUNCTION touch_attendance_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $fn$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_touch_attendance_sessions ON attendance_sessions;
CREATE TRIGGER trg_touch_attendance_sessions
  BEFORE UPDATE ON attendance_sessions
  FOR EACH ROW EXECUTE FUNCTION touch_attendance_updated_at();

DROP TRIGGER IF EXISTS trg_touch_attendance_records ON attendance_records;
CREATE TRIGGER trg_touch_attendance_records
  BEFORE UPDATE ON attendance_records
  FOR EACH ROW EXECUTE FUNCTION touch_attendance_updated_at();

-- ---------------------------------------------------------------------- RLS

ALTER TABLE attendance_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance_records ENABLE ROW LEVEL SECURITY;

-- Ownership flows from the offering, never from taken_by: a teacher must not
-- be able to keep editing a session after the offering moves on, and must not
-- be able to create one against someone else's course by writing their own id
-- into taken_by.
DROP POLICY IF EXISTS teacher_manage_own_attendance_sessions ON attendance_sessions;
CREATE POLICY teacher_manage_own_attendance_sessions ON attendance_sessions
  FOR ALL
  USING (EXISTS (
    SELECT 1 FROM course_offerings co
    WHERE co.id = attendance_sessions.offering_id AND co.teacher_id = auth.uid()))
  WITH CHECK (EXISTS (
    SELECT 1 FROM course_offerings co
    WHERE co.id = attendance_sessions.offering_id AND co.teacher_id = auth.uid()));

DROP POLICY IF EXISTS student_read_own_attendance_sessions ON attendance_sessions;
CREATE POLICY student_read_own_attendance_sessions ON attendance_sessions
  FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM enrollments e
    WHERE e.offering_id = attendance_sessions.offering_id
      AND e.student_id = auth.uid()
      AND e.status = 'approved'));

DROP POLICY IF EXISTS admin_observe_attendance_sessions ON attendance_sessions;
CREATE POLICY admin_observe_attendance_sessions ON attendance_sessions
  FOR SELECT
  USING (get_my_profile_role() IN ('admin', 'dept_admin', 'super_admin', 'exam_controller'));

DROP POLICY IF EXISTS teacher_manage_own_attendance_records ON attendance_records;
CREATE POLICY teacher_manage_own_attendance_records ON attendance_records
  FOR ALL
  USING (EXISTS (
    SELECT 1 FROM attendance_sessions s
    JOIN course_offerings co ON co.id = s.offering_id
    WHERE s.id = attendance_records.session_id AND co.teacher_id = auth.uid()))
  WITH CHECK (EXISTS (
    SELECT 1 FROM attendance_sessions s
    JOIN course_offerings co ON co.id = s.offering_id
    WHERE s.id = attendance_records.session_id AND co.teacher_id = auth.uid()));

-- Read-only for the student: they can see their own attendance but cannot
-- mark themselves present.
DROP POLICY IF EXISTS student_read_own_attendance_records ON attendance_records;
CREATE POLICY student_read_own_attendance_records ON attendance_records
  FOR SELECT
  USING (student_id = auth.uid());

DROP POLICY IF EXISTS admin_observe_attendance_records ON attendance_records;
CREATE POLICY admin_observe_attendance_records ON attendance_records
  FOR SELECT
  USING (get_my_profile_role() IN ('admin', 'dept_admin', 'super_admin', 'exam_controller'));

-- ------------------------------------------------------- lab group splitting
--
-- Splits an offering's approved enrolments into two lab groups. Alternating by
-- name keeps the halves stable and roughly equal (25/25 at a full section of
-- 50) and, unlike a random split, produces the same answer if it is ever
-- re-run. Students already assigned are left alone so re-running after a late
-- enrolment tops up rather than reshuffling everyone.

CREATE OR REPLACE FUNCTION assign_lab_groups(p_offering_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_assigned integer;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM course_offerings co
    WHERE co.id = p_offering_id AND co.teacher_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Not your course offering';
  END IF;

  WITH ranked AS (
    SELECT e.id,
           row_number() OVER (ORDER BY p.full_name, p.id) AS rn
    FROM enrollments e
    JOIN profiles p ON p.id = e.student_id
    WHERE e.offering_id = p_offering_id
      AND e.status = 'approved'
      AND e.lab_subgroup IS NULL
  )
  UPDATE enrollments e
  SET lab_subgroup = CASE WHEN r.rn % 2 = 1 THEN 1 ELSE 2 END
  FROM ranked r
  WHERE e.id = r.id;

  GET DIAGNOSTICS v_assigned = ROW_COUNT;
  RETURN v_assigned;
END;
$fn$;

REVOKE ALL ON FUNCTION assign_lab_groups(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION assign_lab_groups(uuid) TO authenticated;
