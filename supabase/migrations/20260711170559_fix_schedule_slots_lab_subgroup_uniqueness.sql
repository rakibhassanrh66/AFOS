-- schedule_slots_identity (from the routine_schema_v2 migration) is a
-- UNIQUE index on (subject_code, day_of_week, start_time, room_number,
-- batch, section, lab_subgroup, department, semester) — but Postgres
-- treats NULL as never equal to NULL in a unique index, and lab_subgroup is
-- NULL for every non-lab class (the large majority of any real routine).
-- That means the index could never actually detect a "conflict" for any
-- non-lab row, so parse-routine's upsert (which relies on ON CONFLICT
-- against this exact index) silently fell through to a plain INSERT on
-- every re-upload instead of updating in place — confirmed live: a second
-- upload of the same file produced exact duplicate rows for every non-lab
-- class rather than replacing them, and a real account's own schedule view
-- showed the same class 3 times.
--
-- Fix: lab_subgroup becomes NOT NULL with 0 as a real "not a lab subgroup"
-- sentinel (never a genuine subgroup number, which is always 1 or 2), so
-- every row has a real, comparable value and the unique index works as
-- intended for lab and non-lab rows alike. The app's own reading of this
-- column (is this row lab subgroup 1 or 2?) stays untouched — the Dart
-- model maps 0 back to null at read time, so nothing above the DB layer
-- needs to know 0 is a sentinel rather than a real absence.

-- Drop the old (ineffective-for-NULLs) index first so the cleanup below
-- isn't blocked by the very constraint this migration is replacing.
DROP INDEX IF EXISTS schedule_slots_identity;

-- The live table already accumulated real duplicate rows (confirmed: a
-- second upload of the same file inserted a full second copy of every
-- non-lab class) plus leftover rows from a parser generation predating the
-- building/room split (room_number still carrying the building prefix,
-- e.g. "KT-518" sitting alongside the correct "518" for the same class).
-- Surgically deduplicating that mixed-generation data is error-prone;
-- wiping the affected rows and letting the next re-upload (which fully
-- replaces its department's data, per parse-routine's deleteObsolete)
-- repopulate cleanly is the reliable fix. Scoped to the departments that
-- actually have data at all right now, not a blanket TRUNCATE.
DELETE FROM schedule_slots WHERE department IN (SELECT DISTINCT department FROM schedule_slots);

-- Existing CHECK only ever allowed 1, 2, or NULL — widen it to also allow
-- the new 0 sentinel.
ALTER TABLE schedule_slots DROP CONSTRAINT IF EXISTS schedule_slots_lab_subgroup_check;
ALTER TABLE schedule_slots ADD CONSTRAINT schedule_slots_lab_subgroup_check CHECK (lab_subgroup = ANY (ARRAY[0, 1, 2]));

ALTER TABLE schedule_slots ALTER COLUMN lab_subgroup SET DEFAULT 0;
ALTER TABLE schedule_slots ALTER COLUMN lab_subgroup SET NOT NULL;

CREATE UNIQUE INDEX schedule_slots_identity ON schedule_slots
  (subject_code, day_of_week, start_time, room_number, batch, section, lab_subgroup, department, semester);
