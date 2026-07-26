-- ══════════════════════════════════════════════════════════════════════
--  AFOS — Class routine (batch/section/room) + exam routine (mid/final)
--  PDF import support. Run after 001_init.sql / 002_lost_found_claims.sql
-- ══════════════════════════════════════════════════════════════════════

-- Class routine grid PDFs are keyed by room+day+time, not just subject —
-- multiple sections of the same course can run in the same slot in
-- different rooms, so batch/section/room must all be part of identity.
ALTER TABLE schedule_slots ADD COLUMN IF NOT EXISTS batch TEXT;
ALTER TABLE schedule_slots ADD COLUMN IF NOT EXISTS section TEXT;
ALTER TABLE schedule_slots ADD COLUMN IF NOT EXISTS teacher_initial TEXT;

DROP INDEX IF EXISTS schedule_slots_subject_code_day_of_week_start_time_departm_key;
ALTER TABLE schedule_slots DROP CONSTRAINT IF EXISTS schedule_slots_subject_code_day_of_week_start_time_departm_key;
CREATE UNIQUE INDEX IF NOT EXISTS schedule_slots_identity
  ON schedule_slots (subject_code, day_of_week, start_time, room_number, batch, section, department, semester);

-- Exam routine PDFs list mid/final slots per batch, not per-student seat
-- (that's exam_seat_assignments, already separate).
ALTER TABLE exams ADD COLUMN IF NOT EXISTS exam_type TEXT DEFAULT 'final'
  CHECK (exam_type IN ('mid','final','improvement','retake'));
ALTER TABLE exams ADD COLUMN IF NOT EXISTS batch TEXT;
ALTER TABLE exams ADD COLUMN IF NOT EXISTS section TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS exams_identity
  ON exams (subject_code, exam_date, start_time, batch, exam_type);

-- So students see only their own batch/section and teachers see only
-- their own initials-tagged classes, without a separate lookup table.
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS batch TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS section TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS teacher_initial TEXT;
