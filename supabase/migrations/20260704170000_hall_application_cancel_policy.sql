-- Allow a student to cancel their own hall application while it is still
-- pending review. Cancelling after allocation ('approved') is a separate,
-- admin-approved special-case workflow — intentionally out of scope here.

-- The original status CHECK didn't include 'cancelled' at all.
ALTER TABLE hall_applications DROP CONSTRAINT IF EXISTS hall_applications_status_check;
ALTER TABLE hall_applications ADD CONSTRAINT hall_applications_status_check
  CHECK (status IN ('pending','reviewing','approved','rejected','cancelled'));

CREATE POLICY "own_hall_cancel" ON hall_applications FOR UPDATE
  USING (auth.uid() = student_id AND status IN ('pending','reviewing'))
  WITH CHECK (auth.uid() = student_id AND status = 'cancelled');
