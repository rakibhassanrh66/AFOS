-- Real DIU exam seat plans (confirmed against an actual sample document)
-- allocate ROOM CAPACITY per section, not individual student seats — a
-- single section's exam spans several rooms with different seat counts
-- each, and a room can be split between two adjacent sections. There is
-- no per-student seat number anywhere in the source data, so this models
-- what the university actually publishes: "this batch+section's exam is
-- held across these rooms."
CREATE TABLE IF NOT EXISTS exam_room_allocations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  exam_title text,
  exam_date date NOT NULL,
  slot_label text,
  slot_start time,
  slot_end time,
  course_code text,
  course_title text,
  teacher_initial text,
  batch text NOT NULL,
  section text NOT NULL,
  room_no text NOT NULL,
  seats integer NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS exam_room_allocations_batch_section_idx
  ON exam_room_allocations (batch, section, exam_date);

ALTER TABLE exam_room_allocations ENABLE ROW LEVEL SECURITY;

CREATE POLICY auth_read_exam_room_allocations ON exam_room_allocations FOR SELECT USING (true);
CREATE POLICY admin_write_exam_room_allocations ON exam_room_allocations FOR ALL USING (
  EXISTS (SELECT 1 FROM profiles WHERE profiles.id = auth.uid()
    AND profiles.role = ANY (ARRAY['admin', 'dept_admin', 'super_admin', 'exam_controller']))
);

ALTER PUBLICATION supabase_realtime ADD TABLE exam_room_allocations;
