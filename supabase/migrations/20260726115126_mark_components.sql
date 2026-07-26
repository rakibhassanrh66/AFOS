-- DIU mark distribution, as components rather than fixed columns.
--
-- WHY NOT THE EXISTING `marks` TABLE. It has five hard-coded columns
-- (attendance/quiz/assignment/midterm/final) with a generated total. That
-- shape cannot express the DIU scheme: theory needs a sixth component
-- (Presentation) and lab needs four entirely different ones (Project, Viva,
-- Daily Report, Lab Attendance) with no written exam at all. Widening it would
-- give every row four permanently-NULL columns and a generated total that is
-- wrong for one of the two course types. `marks` is dead anyway -- zero rows,
-- zero Dart references -- so this supersedes it rather than fighting it.
--
--   Theory (100): Final 40, Mid-Term 25, Quizzes 15, Presentation 8,
--                 Attendance 7, Assignment 5
--   Lab    (100): Project & Report 40, Viva-Voce 25, Daily Report & Code 25,
--                 Lab Attendance 10
--
-- Totals are DERIVED (see enrollment_results), never stored, so a component
-- edit cannot leave a stale total behind.

-- -------------------------------------------------------------- catalogue

CREATE TABLE IF NOT EXISTS mark_components (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  course_type text NOT NULL CHECK (course_type IN ('theory', 'lab')),
  code text NOT NULL,
  label text NOT NULL,
  max_marks numeric(5, 2) NOT NULL CHECK (max_marks > 0 AND max_marks <= 100),
  sort_order integer NOT NULL DEFAULT 0,
  -- Filled from the attendance registers rather than typed by hand.
  is_auto boolean NOT NULL DEFAULT false,
  UNIQUE (course_type, code)
);

INSERT INTO mark_components (course_type, code, label, max_marks, sort_order, is_auto) VALUES
  ('theory', 'final_exam',     'Final Written Exam',       40, 1, false),
  ('theory', 'midterm',        'Mid-Term Written Exam',    25, 2, false),
  ('theory', 'quiz',           'Class Tests / Quizzes',    15, 3, false),
  ('theory', 'presentation',   'Presentation',              8, 4, false),
  ('theory', 'attendance',     'Attendance',                7, 5, true),
  ('theory', 'assignment',     'Assignment',                5, 6, false),
  ('lab',    'lab_project',    'Main Lab Project & Report',40, 1, false),
  ('lab',    'viva',           'Central Viva-Voce',        25, 2, false),
  ('lab',    'lab_report',     'Daily Lab Report & Code',  25, 3, false),
  ('lab',    'lab_attendance', 'Lab Attendance',           10, 4, true)
ON CONFLICT (course_type, code) DO UPDATE
  SET label = EXCLUDED.label,
      max_marks = EXCLUDED.max_marks,
      sort_order = EXCLUDED.sort_order,
      is_auto = EXCLUDED.is_auto;

-- Each course type must add up to exactly 100. A constraint trigger rather
-- than a CHECK because the rule spans rows; deferred so the seed above can
-- insert them one at a time without tripping on a partial total.
CREATE OR REPLACE FUNCTION assert_mark_components_total_100()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_type text;
  v_total numeric;
BEGIN
  FOR v_type, v_total IN
    SELECT course_type, SUM(max_marks) FROM mark_components GROUP BY course_type
  LOOP
    IF v_total <> 100 THEN
      RAISE EXCEPTION '% components total %, must be exactly 100', v_type, v_total;
    END IF;
  END LOOP;
  RETURN NULL;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_mark_components_total_100 ON mark_components;
CREATE CONSTRAINT TRIGGER trg_mark_components_total_100
  AFTER INSERT OR UPDATE OR DELETE ON mark_components
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION assert_mark_components_total_100();

ALTER TABLE mark_components ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS read_mark_components ON mark_components;
CREATE POLICY read_mark_components ON mark_components FOR SELECT TO authenticated USING (true);

-- ------------------------------------------------------------ student marks

CREATE TABLE IF NOT EXISTS student_marks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  enrollment_id uuid NOT NULL REFERENCES enrollments(id) ON DELETE CASCADE,
  component_id uuid NOT NULL REFERENCES mark_components(id) ON DELETE RESTRICT,
  marks numeric(5, 2) NOT NULL DEFAULT 0 CHECK (marks >= 0),
  updated_by uuid REFERENCES profiles(id) ON DELETE SET NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (enrollment_id, component_id)
);

CREATE INDEX IF NOT EXISTS student_marks_enrollment_idx ON student_marks (enrollment_id);

-- Upper bound is cross-table (the component's own max), so it cannot be a
-- CHECK. Also refuses a component belonging to the other course type, which
-- would otherwise quietly inflate a total past 100.
CREATE OR REPLACE FUNCTION assert_student_mark_within_component()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_max numeric;
  v_component_type text;
  v_course_type text;
BEGIN
  SELECT mc.max_marks, mc.course_type INTO v_max, v_component_type
  FROM mark_components mc WHERE mc.id = NEW.component_id;

  SELECT COALESCE(c.course_type, 'theory') INTO v_course_type
  FROM enrollments e
  JOIN course_offerings co ON co.id = e.offering_id
  JOIN courses c ON c.id = co.course_id
  WHERE e.id = NEW.enrollment_id;

  IF v_component_type IS DISTINCT FROM v_course_type THEN
    RAISE EXCEPTION 'Component is for a % course, but this enrolment is %',
      v_component_type, v_course_type;
  END IF;

  IF NEW.marks > v_max THEN
    RAISE EXCEPTION 'Marks % exceed the maximum % for this component', NEW.marks, v_max;
  END IF;

  NEW.updated_at := now();
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_student_marks_within_component ON student_marks;
CREATE TRIGGER trg_student_marks_within_component
  BEFORE INSERT OR UPDATE ON student_marks
  FOR EACH ROW EXECUTE FUNCTION assert_student_mark_within_component();

-- ------------------------------------------------------- result submissions
--
-- The teacher's one-click "send it all in", and the admin gate in front of
-- publication. Per offering, not per student: results are released for a
-- whole class at once.

CREATE TABLE IF NOT EXISTS offering_result_submissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  offering_id uuid NOT NULL UNIQUE REFERENCES course_offerings(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'rejected')),
  submitted_by uuid REFERENCES profiles(id) ON DELETE SET NULL,
  submitted_at timestamptz NOT NULL DEFAULT now(),
  reviewed_by uuid REFERENCES profiles(id) ON DELETE SET NULL,
  reviewed_at timestamptz,
  rejection_reason text,
  CONSTRAINT offering_result_submissions_reason_len
    CHECK (rejection_reason IS NULL OR length(rejection_reason) <= 500)
);

-- ------------------------------------------------------------------ results
--
-- Total, letter and grade point, derived from the components every time.
--
-- The grade lookup is `total >= min_marks ORDER BY min_marks DESC LIMIT 1`,
-- NOT a BETWEEN on grading_scale's min/max. The seeded bands stop at 79.99,
-- 74.99 and so on, so a BETWEEN leaves a hole for 79.995 and would return no
-- grade at all. (The old calculate_grade() has exactly that bug, plus a
-- LIMIT 1 with no ORDER BY.)

CREATE OR REPLACE VIEW enrollment_results
WITH (security_invoker = true) AS
SELECT
  e.id                AS enrollment_id,
  e.offering_id,
  e.student_id,
  COALESCE(c.course_type, 'theory') AS course_type,
  c.credit_hours,
  COALESCE(SUM(sm.marks), 0)::numeric(5, 2) AS total_marks,
  gs.letter_grade,
  gs.grade_point,
  ors.status          AS publication_status
FROM enrollments e
JOIN course_offerings co ON co.id = e.offering_id
LEFT JOIN courses c ON c.id = co.course_id
LEFT JOIN student_marks sm ON sm.enrollment_id = e.id
LEFT JOIN offering_result_submissions ors ON ors.offering_id = e.offering_id
LEFT JOIN LATERAL (
  SELECT g.letter_grade, g.grade_point
  FROM grading_scale g
  WHERE g.min_marks <= COALESCE((SELECT SUM(sm2.marks) FROM student_marks sm2
                                 WHERE sm2.enrollment_id = e.id), 0)
  ORDER BY g.min_marks DESC
  LIMIT 1
) gs ON true
WHERE e.status = 'approved'
GROUP BY e.id, e.offering_id, e.student_id, c.course_type, c.credit_hours,
         gs.letter_grade, gs.grade_point, ors.status;

-- ---------------------------------------------------------------------- RLS

ALTER TABLE student_marks ENABLE ROW LEVEL SECURITY;
ALTER TABLE offering_result_submissions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS teacher_manage_own_student_marks ON student_marks;
CREATE POLICY teacher_manage_own_student_marks ON student_marks
  FOR ALL
  USING (EXISTS (
    SELECT 1 FROM enrollments e
    JOIN course_offerings co ON co.id = e.offering_id
    WHERE e.id = student_marks.enrollment_id AND co.teacher_id = auth.uid()))
  WITH CHECK (EXISTS (
    SELECT 1 FROM enrollments e
    JOIN course_offerings co ON co.id = e.offering_id
    WHERE e.id = student_marks.enrollment_id AND co.teacher_id = auth.uid()));

-- A student sees their marks only once the offering's results are approved.
-- Before that the numbers are a work in progress and must not leak.
DROP POLICY IF EXISTS student_read_published_marks ON student_marks;
CREATE POLICY student_read_published_marks ON student_marks
  FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM enrollments e
    JOIN offering_result_submissions ors ON ors.offering_id = e.offering_id
    WHERE e.id = student_marks.enrollment_id
      AND e.student_id = auth.uid()
      AND ors.status = 'approved'));

DROP POLICY IF EXISTS admin_observe_student_marks ON student_marks;
CREATE POLICY admin_observe_student_marks ON student_marks
  FOR SELECT
  USING (get_my_profile_role() IN ('admin', 'dept_admin', 'super_admin', 'exam_controller'));

DROP POLICY IF EXISTS teacher_submit_own_results ON offering_result_submissions;
CREATE POLICY teacher_submit_own_results ON offering_result_submissions
  FOR ALL
  USING (EXISTS (
    SELECT 1 FROM course_offerings co
    WHERE co.id = offering_result_submissions.offering_id AND co.teacher_id = auth.uid()))
  WITH CHECK (EXISTS (
    SELECT 1 FROM course_offerings co
    WHERE co.id = offering_result_submissions.offering_id AND co.teacher_id = auth.uid()));

DROP POLICY IF EXISTS student_read_own_result_status ON offering_result_submissions;
CREATE POLICY student_read_own_result_status ON offering_result_submissions
  FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM enrollments e
    WHERE e.offering_id = offering_result_submissions.offering_id
      AND e.student_id = auth.uid()
      AND e.status = 'approved'));

DROP POLICY IF EXISTS admin_review_result_submissions ON offering_result_submissions;
CREATE POLICY admin_review_result_submissions ON offering_result_submissions
  FOR ALL
  USING (get_my_profile_role() IN ('admin', 'dept_admin', 'super_admin', 'exam_controller'))
  WITH CHECK (get_my_profile_role() IN ('admin', 'dept_admin', 'super_admin', 'exam_controller'));

-- ------------------------------------------------- attendance -> mark component
--
-- Scales each student's attendance percentage onto the attendance component's
-- max (7 theory, 10 lab) and writes it in. Late counts as attended and excused
-- is excluded from the denominator, matching how the register itself reports.
-- Bonus is added on top and then clamped, so reward credit can lift a student
-- but never past the component ceiling.
--
-- A student with no sessions at all scores 0 rather than full marks: silently
-- awarding 7/7 to a class whose register was never taken would be worse than
-- an obvious zero.

CREATE OR REPLACE FUNCTION sync_attendance_marks(p_offering_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_component_id uuid;
  v_max numeric;
  v_updated integer;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM course_offerings co
    WHERE co.id = p_offering_id AND co.teacher_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Not your course offering';
  END IF;

  SELECT mc.id, mc.max_marks INTO v_component_id, v_max
  FROM mark_components mc
  JOIN course_offerings co ON co.id = p_offering_id
  JOIN courses c ON c.id = co.course_id
  WHERE mc.course_type = COALESCE(c.course_type, 'theory') AND mc.is_auto;

  IF v_component_id IS NULL THEN
    RAISE EXCEPTION 'No attendance component for this course type';
  END IF;

  WITH tally AS (
    SELECT e.id AS enrollment_id,
           COUNT(*) FILTER (WHERE ar.status IN ('present', 'late'))  AS attended,
           COUNT(*) FILTER (WHERE ar.status <> 'excused')            AS counted,
           COALESCE(SUM(ar.bonus), 0)                                AS bonus
    FROM enrollments e
    LEFT JOIN attendance_records ar ON ar.student_id = e.student_id
    LEFT JOIN attendance_sessions s
           ON s.id = ar.session_id AND s.offering_id = e.offering_id
    WHERE e.offering_id = p_offering_id
      AND e.status = 'approved'
      AND (ar.id IS NULL OR s.id IS NOT NULL)
    GROUP BY e.id
  )
  INSERT INTO student_marks (enrollment_id, component_id, marks, updated_by)
  SELECT t.enrollment_id, v_component_id,
         LEAST(v_max,
               ROUND(CASE WHEN t.counted = 0 THEN 0
                          ELSE (t.attended::numeric / t.counted) * v_max END
                     + t.bonus, 2)),
         auth.uid()
  FROM tally t
  ON CONFLICT (enrollment_id, component_id)
  DO UPDATE SET marks = EXCLUDED.marks, updated_by = EXCLUDED.updated_by;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated;
END;
$fn$;

REVOKE ALL ON FUNCTION sync_attendance_marks(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION sync_attendance_marks(uuid) TO authenticated;
