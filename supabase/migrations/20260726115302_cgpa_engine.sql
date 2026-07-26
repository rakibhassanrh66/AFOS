-- CGPA on the DIU 4.00 scale.
--
-- grading_scale was already seeded correctly (A+ 4.00 at 80+, down to F 0.00
-- below 40) and simply never read -- grades_screen.dart hardcoded the letters
-- instead. calculate_semester_sgpa() existed too and nothing ever called it.
-- This makes the scale the single source of truth and computes the rest.
--
-- Two rules shape the whole design:
--
--   RETAKES. "The previous lower grade is automatically wiped out and
--   completely replaced by the newer grade." A retake is simply a second
--   approved enrolment for the same course in a later term -- there is no
--   retake flag to set and none is needed. Only the newest attempt counts, so
--   student_counting_results does DISTINCT ON (student, course) ordered by
--   term descending. This also fixes a latent double-count: the old
--   calculate_semester_sgpa summed every enrolment, so a retaken course would
--   have been weighed twice.
--
--   PUBLICATION. Only approved results count. An in-progress mark must never
--   move a CGPA.

CREATE OR REPLACE VIEW student_counting_results
WITH (security_invoker = true) AS
SELECT DISTINCT ON (er.student_id, co.course_id)
  er.student_id,
  co.course_id,
  er.enrollment_id,
  er.offering_id,
  co.semester_id,
  co.semester,
  er.total_marks,
  er.letter_grade,
  er.grade_point,
  COALESCE(er.credit_hours, 0)::numeric AS credit_hours
FROM enrollment_results er
JOIN course_offerings co ON co.id = er.offering_id
WHERE er.publication_status = 'approved'
ORDER BY er.student_id, co.course_id,
         co.semester DESC NULLS LAST, er.enrollment_id DESC;

COMMENT ON VIEW student_counting_results IS
  'One row per student per course: the attempt that actually counts. A retake '
  'supersedes the earlier attempt entirely, per DIU policy.';

-- --------------------------------------------------------------------- SGPA

CREATE OR REPLACE FUNCTION student_sgpa(p_student_id uuid, p_semester integer)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $fn$
  SELECT CASE WHEN SUM(credit_hours) > 0
              THEN ROUND(SUM(grade_point * credit_hours) / SUM(credit_hours), 2)
              ELSE NULL END
  FROM student_counting_results
  WHERE student_id = p_student_id
    AND semester = p_semester
    AND grade_point IS NOT NULL;
$fn$;

-- --------------------------------------------------------------------- CGPA

CREATE OR REPLACE FUNCTION student_cgpa(p_student_id uuid)
RETURNS TABLE (
  cgpa numeric,
  total_credits numeric,
  earned_credits numeric,
  quality_points numeric,
  has_f boolean,
  standing text,
  honour text
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $fn$
  WITH r AS (
    SELECT * FROM student_counting_results
    WHERE student_id = p_student_id AND grade_point IS NOT NULL
  ), agg AS (
    SELECT
      COALESCE(SUM(credit_hours), 0)                     AS total_credits,
      -- A failed course earns no credit but still drags the average, which is
      -- exactly how a credit-weighted GPA is supposed to behave.
      COALESCE(SUM(credit_hours) FILTER (WHERE letter_grade <> 'F'), 0) AS earned_credits,
      COALESCE(SUM(grade_point * credit_hours), 0)       AS quality_points,
      COALESCE(bool_or(letter_grade = 'F'), false)       AS has_f
    FROM r
  )
  SELECT
    CASE WHEN total_credits > 0
         THEN ROUND(quality_points / total_credits, 2) END,
    total_credits,
    earned_credits,
    quality_points,
    has_f,
    CASE WHEN total_credits = 0 THEN 'no_results'
         WHEN quality_points / total_credits < 2.00 THEN 'probation'
         ELSE 'good' END,
    -- Honours are only meaningful at graduation and are void with a standing
    -- F, since the degree cannot be conferred at all in that case.
    CASE WHEN total_credits = 0 OR has_f THEN NULL
         WHEN quality_points / total_credits >= 3.90 THEN 'Summa Cum Laude'
         WHEN quality_points / total_credits >= 3.75 THEN 'Magna Cum Laude'
         END
  FROM agg;
$fn$;

REVOKE ALL ON FUNCTION student_sgpa(uuid, integer) FROM public, anon;
REVOKE ALL ON FUNCTION student_cgpa(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION student_sgpa(uuid, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION student_cgpa(uuid) TO authenticated;

-- Both are SECURITY INVOKER on purpose: they read through
-- student_counting_results -> enrollment_results -> student_marks, all of
-- which are RLS'd, so a caller can only ever aggregate rows they were already
-- allowed to see. A student gets their own CGPA; a teacher or admin gets one
-- for a student whose marks they can read. No definer escape hatch needed.

-- ------------------------------------------- why students.cgpa is NOT cached
--
-- students.cgpa has existed since the initial schema, was never computed
-- (every row NULL), and is displayed by vr_id_pdf_generator.dart and
-- vr_id_screen.dart. The obvious move is to refresh it on publication -- and
-- that is wrong twice over.
--
-- First, protect_student_admin_columns() rejects any write to students.status
-- or students.cgpa without has_permission('students','all','all'). Results are
-- approved by admin/dept_admin/super_admin/exam_controller, and an
-- exam_controller does not necessarily hold that permission, so publication
-- would fail for some approvers and not others. Making the refresher
-- SECURITY DEFINER to punch through that guard would defeat a deliberate
-- protection on the most sensitive column a student row has.
--
-- Second, it is a denormalised copy of something already derivable, so it can
-- only ever drift.
--
-- student_cgpa() reads through RLS'd views and is cheap, so the read surfaces
-- call it directly instead. The column is left untouched and unused.

-- Notify the class the moment an admin approves the results. In the same
-- transaction as the status change, deliberately: a client-side follow-up is
-- deliberate: a client-side follow-up call is silently lost if the app is
-- backgrounded, which is how an offering once sat for hours with nobody
-- informed (see the note on createOffering in course_offering_repository).

CREATE OR REPLACE FUNCTION on_results_approved()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_code text;
BEGIN
  IF NEW.status = 'approved' AND COALESCE(OLD.status, '') <> 'approved' THEN
    SELECT c.code INTO v_code
    FROM course_offerings co JOIN courses c ON c.id = co.course_id
    WHERE co.id = NEW.offering_id;

    INSERT INTO user_notifications (user_id, title, body, category, deep_link_route)
    SELECT e.student_id,
           'Result published',
           'Your result for ' || COALESCE(v_code, 'your course') || ' is now available.',
           'result',
           '/grades'
    FROM enrollments e
    WHERE e.offering_id = NEW.offering_id AND e.status = 'approved';
  END IF;
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_on_results_approved ON offering_result_submissions;
CREATE TRIGGER trg_on_results_approved
  AFTER INSERT OR UPDATE OF status ON offering_result_submissions
  FOR EACH ROW EXECUTE FUNCTION on_results_approved();
