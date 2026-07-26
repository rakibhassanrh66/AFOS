-- exams_identity previously included start_time in the natural key
-- (subject_code, exam_date, start_time, batch, exam_type). Confirmed live:
-- when an early exam-routine upload failed to parse a start_time for a
-- given day (landing as NULL) and a later, more complete upload correctly
-- parsed it, the upsert's ON CONFLICT target no longer matched the existing
-- row (NULL vs a real time is never "the same" under a unique index), so a
-- second row was INSERTED instead of the first being UPDATED — students saw
-- the same exam listed twice, once with a working time and once broken.
-- A subject only ever sits one exam per (date, batch, exam_type); dropping
-- start_time from the key means a corrected re-upload updates the existing
-- row in place instead of duplicating it.
drop index if exists exams_identity;
create unique index exams_identity on public.exams (subject_code, exam_date, batch, exam_type);
