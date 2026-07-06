-- A student who already has an approved hall seat could never cancel at
-- all before this (own_hall_cancel only permits updates while status is
-- still pending/reviewing) — per spec, cancelling *after* allocation needs
-- to go through a request+reason that a super admin/staff approves or
-- denies, rather than being instant self-service like a pre-allocation
-- cancel is.
ALTER TABLE hall_applications ADD COLUMN IF NOT EXISTS cancellation_reason text;

CREATE POLICY own_hall_request_cancel ON hall_applications
  FOR UPDATE
  USING (auth.uid() = student_id AND status = 'approved')
  WITH CHECK (auth.uid() = student_id AND status = 'cancel_requested');
