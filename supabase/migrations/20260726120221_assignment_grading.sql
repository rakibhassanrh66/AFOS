-- Assignment grading and file submission.
--
-- The pieces that were missing: assignment_submissions had no marks, feedback
-- or grader columns at all, so there was no path from a submission to a grade.
-- `attachment_url` existed on both tables but nothing ever wrote it -- there
-- was no bucket to write to. Submissions were text-only and, once made, could
-- not be edited (INSERT-only RLS plus a UNIQUE, so no resubmission either).

ALTER TABLE assignments
  ADD COLUMN IF NOT EXISTS max_marks numeric(5, 2) NOT NULL DEFAULT 10;
ALTER TABLE assignments DROP CONSTRAINT IF EXISTS assignments_max_marks_check;
ALTER TABLE assignments ADD CONSTRAINT assignments_max_marks_check
  CHECK (max_marks > 0 AND max_marks <= 100);

ALTER TABLE assignment_submissions
  ADD COLUMN IF NOT EXISTS marks numeric(5, 2),
  ADD COLUMN IF NOT EXISTS feedback text,
  ADD COLUMN IF NOT EXISTS graded_by uuid REFERENCES profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS graded_at timestamptz;

ALTER TABLE assignment_submissions DROP CONSTRAINT IF EXISTS assignment_submissions_marks_check;
ALTER TABLE assignment_submissions ADD CONSTRAINT assignment_submissions_marks_check
  CHECK (marks IS NULL OR marks >= 0);
ALTER TABLE assignment_submissions DROP CONSTRAINT IF EXISTS assignment_submissions_feedback_len;
ALTER TABLE assignment_submissions ADD CONSTRAINT assignment_submissions_feedback_len
  CHECK (feedback IS NULL OR length(feedback) <= 1000);

-- Ceiling is the assignment's own max, so it is cross-table and cannot be a
-- CHECK. Also stamps the grader, so "who marked this" is never guesswork.
CREATE OR REPLACE FUNCTION assert_submission_marks_within_max()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $fn$
DECLARE v_max numeric;
BEGIN
  IF NEW.marks IS NOT NULL THEN
    SELECT a.max_marks INTO v_max FROM assignments a WHERE a.id = NEW.assignment_id;
    IF NEW.marks > v_max THEN
      RAISE EXCEPTION 'Marks % exceed this assignment''s maximum of %', NEW.marks, v_max;
    END IF;
    IF NEW.marks IS DISTINCT FROM COALESCE(OLD.marks, -1) THEN
      NEW.graded_by := auth.uid();
      NEW.graded_at := now();
    END IF;
  END IF;
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_submission_marks_within_max ON assignment_submissions;
CREATE TRIGGER trg_submission_marks_within_max
  BEFORE INSERT OR UPDATE ON assignment_submissions
  FOR EACH ROW EXECUTE FUNCTION assert_submission_marks_within_max();

-- A teacher can grade submissions on their own assignments. Previously they
-- could only read them -- getSubmissions() existed in Dart and was never even
-- called, because there was nothing to do with the result.
DROP POLICY IF EXISTS teacher_grade_submissions ON assignment_submissions;
CREATE POLICY teacher_grade_submissions ON assignment_submissions
  FOR UPDATE
  USING (EXISTS (
    SELECT 1 FROM assignments a
    WHERE a.id = assignment_submissions.assignment_id AND a.teacher_id = auth.uid()))
  WITH CHECK (EXISTS (
    SELECT 1 FROM assignments a
    WHERE a.id = assignment_submissions.assignment_id AND a.teacher_id = auth.uid()));

-- A student may revise their own submission until the deadline. After it, the
-- row freezes -- the teacher may already have marked it, and a silent edit
-- underneath a grade would be worse than a refused save.
DROP POLICY IF EXISTS student_update_own_submission_before_deadline ON assignment_submissions;
CREATE POLICY student_update_own_submission_before_deadline ON assignment_submissions
  FOR UPDATE
  USING (student_id = auth.uid() AND EXISTS (
    SELECT 1 FROM assignments a
    WHERE a.id = assignment_submissions.assignment_id AND a.deadline > now()))
  WITH CHECK (student_id = auth.uid() AND marks IS NULL AND graded_by IS NULL);

DROP POLICY IF EXISTS student_read_own_submission ON assignment_submissions;
CREATE POLICY student_read_own_submission ON assignment_submissions
  FOR SELECT USING (student_id = auth.uid());

-- ------------------------------------------------------------------ storage
--
-- Private, unlike avatars/lost-found: coursework is the student's own work and
-- must not be world-readable by URL. Reads go through signed URLs.

INSERT INTO storage.buckets (id, name, public)
VALUES ('assignment-submissions', 'assignment-submissions', false)
ON CONFLICT (id) DO NOTHING;

-- Path convention is {uid}/{filename}, matching StorageUploadService and the
-- other buckets, so ownership is the first path segment.
DROP POLICY IF EXISTS assignment_submission_own_write ON storage.objects;
CREATE POLICY assignment_submission_own_write ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'assignment-submissions'
              AND (storage.foldername(name))[1] = auth.uid()::text);

DROP POLICY IF EXISTS assignment_submission_own_update ON storage.objects;
CREATE POLICY assignment_submission_own_update ON storage.objects
  FOR UPDATE TO authenticated
  USING (bucket_id = 'assignment-submissions'
         AND (storage.foldername(name))[1] = auth.uid()::text);

DROP POLICY IF EXISTS assignment_submission_own_read ON storage.objects;
CREATE POLICY assignment_submission_own_read ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'assignment-submissions'
         AND (storage.foldername(name))[1] = auth.uid()::text);

-- The teacher who set the assignment can read what was handed in to them.
DROP POLICY IF EXISTS assignment_submission_teacher_read ON storage.objects;
CREATE POLICY assignment_submission_teacher_read ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'assignment-submissions' AND EXISTS (
    SELECT 1 FROM assignment_submissions s
    JOIN assignments a ON a.id = s.assignment_id
    WHERE a.teacher_id = auth.uid()
      AND s.attachment_url LIKE '%' || storage.objects.name));
