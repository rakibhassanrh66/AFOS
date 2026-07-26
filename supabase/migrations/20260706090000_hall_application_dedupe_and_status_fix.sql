-- Fix two real bugs found in the Hall Allocation feature:
-- 1) hall_applications_status_check never allowed 'cancel_requested', yet
--    both hall_screen.dart's _requestCancellation() and
--    manage_hall_screen.dart's filters use that value — any student tapping
--    "Request Cancellation" on an approved seat got a raw constraint error.
-- 2) No unique constraint ever existed on (student_id), so a student whose
--    "My Application" view kept crashing (see hall_screen.dart fix) could
--    re-apply repeatedly, leaving several duplicate active rows behind.

-- Dedupe first: keep only the most recent non-terminal application per
-- student, cancel the older duplicates (they were accidental resubmits,
-- not distinct real requests).
WITH ranked AS (
  SELECT id, row_number() OVER (PARTITION BY student_id ORDER BY created_at DESC) AS rn
  FROM hall_applications
  WHERE status NOT IN ('rejected', 'cancelled')
)
UPDATE hall_applications
SET status = 'cancelled'
WHERE id IN (SELECT id FROM ranked WHERE rn > 1);

ALTER TABLE hall_applications DROP CONSTRAINT IF EXISTS hall_applications_status_check;
ALTER TABLE hall_applications ADD CONSTRAINT hall_applications_status_check
  CHECK (status IN ('pending', 'reviewing', 'approved', 'rejected', 'cancelled', 'cancel_requested'));

CREATE UNIQUE INDEX IF NOT EXISTS hall_applications_one_active_per_student
  ON hall_applications (student_id)
  WHERE status NOT IN ('rejected', 'cancelled');
