-- ══════════════════════════════════════════════════════════════════════
--  AFOS — 003_routine_pdf_import.sql guessed the wrong auto-generated
--  constraint name when dropping the old identity constraint, so it
--  silently no-op'd and the old (subject_code, day_of_week, start_time,
--  department, semester) uniqueness — with no room/batch/section — stayed
--  active. Since the same course code legitimately repeats across many
--  rooms/batches/sections at the same day/time, that stale constraint
--  rejected almost every class-routine row as a "duplicate".
-- ══════════════════════════════════════════════════════════════════════

ALTER TABLE schedule_slots DROP CONSTRAINT IF EXISTS schedule_slots_subject_code_day_of_week_start_time_departme_key;
