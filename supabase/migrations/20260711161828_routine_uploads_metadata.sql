-- Stores the header metadata a routine PDF prints on itself (version label,
-- effective-from date, prepared-by committee) per department+type, since
-- schedule_slots/exams hold one row per class session, not per-upload
-- batch info, and none of that PDF-header text was captured anywhere before
-- this. One row per (department, routine_type) — a re-upload overwrites the
-- previous header, matching how the underlying schedule/exam rows themselves
-- are fully replaced on re-upload.
CREATE TABLE routine_uploads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  department text NOT NULL,
  routine_type text NOT NULL CHECK (routine_type IN ('class_routine', 'exam_routine')),
  version_label text,
  effective_from_text text,
  prepared_by text,
  uploaded_by uuid REFERENCES profiles(id) ON DELETE SET NULL,
  uploaded_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (department, routine_type)
);

ALTER TABLE routine_uploads ENABLE ROW LEVEL SECURITY;
CREATE POLICY "auth_read_routine_uploads" ON routine_uploads FOR SELECT TO authenticated USING (TRUE);
-- No client-facing write policy — parse-routine writes via the service-role
-- client (bypasses RLS), same as schedule_slots/exams themselves.
