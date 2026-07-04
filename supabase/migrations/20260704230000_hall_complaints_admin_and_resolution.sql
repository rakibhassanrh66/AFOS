-- hall_complaints could only ever be inserted and read by the student who
-- filed it (own_complaints SELECT, insert_complaint INSERT) — no admin-tier
-- role could see or resolve any complaint at all, and there was no place to
-- record a resolution. Add both, mirroring the hall_applications review
-- pattern (reviewed_by/reviewed_at -> resolved_by/resolved_at).

ALTER TABLE hall_complaints ADD COLUMN IF NOT EXISTS resolution TEXT;
ALTER TABLE hall_complaints ADD COLUMN IF NOT EXISTS resolved_by UUID;
ALTER TABLE hall_complaints ADD COLUMN IF NOT EXISTS resolved_at TIMESTAMPTZ;

ALTER TABLE hall_complaints DROP CONSTRAINT IF EXISTS hall_complaints_status_check;
ALTER TABLE hall_complaints ADD CONSTRAINT hall_complaints_status_check
  CHECK (status IN ('open', 'in_progress', 'resolved', 'dismissed'));

CREATE POLICY "admin_complaints_all" ON hall_complaints FOR ALL USING (
  EXISTS (
    SELECT 1 FROM profiles
    WHERE profiles.id = auth.uid()
      AND profiles.role = ANY (ARRAY['admin','staff','super_admin'])
  )
);
