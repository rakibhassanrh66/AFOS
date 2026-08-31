-- The real seat-plan PDF prints a leading "Faculty"/"Dept." column on every
-- new-course row (confirmed against the real Summer 2026 finals documents —
-- see exam_room_pdf_parser.dart's own header comment), but
-- exam_room_pdf_parser.dart never read it, so exam_room_allocations has never
-- had anywhere to put it. That absence is what let a same-date re-upload
-- collide across departments: with no department column, the client's
-- replace-on-reupload step could only scope its delete by exam_date, and a
-- live check against this table found dates with FIVE distinct batches/
-- courses sharing one calendar day (e.g. 2026-08-27: CSE414, ACT327, BNS101,
-- PHY101, CSE115 — 269 rows total) — a single-course re-upload for that date
-- would silently delete every other department's rows for it. The client-side
-- fix narrows the delete to (exam_date, batch, section) — already sufficient
-- on its own, confirmed against the same data (one batch sits exactly one
-- course per date) — and this column is the additional, honest record of
-- which department each row's PDF actually named, for display/filtering.
--
-- No backfill: the ~3400 existing rows predate this column and their source
-- PDFs are gone, so there is no honest way to derive their department after
-- the fact. They stay NULL rather than guessed.
ALTER TABLE exam_room_allocations ADD COLUMN IF NOT EXISTS department text;

CREATE INDEX IF NOT EXISTS exam_room_allocations_department_idx
  ON exam_room_allocations (department, exam_date);
