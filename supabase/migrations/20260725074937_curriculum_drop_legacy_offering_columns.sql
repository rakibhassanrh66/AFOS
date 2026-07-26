-- =====================================================================
--  AFOS — Contract step: drop the single-meeting columns from
--  course_offerings now that meetings live in their own table.
--
--  20260725140000 deliberately LEFT these in place (expand/migrate/contract)
--  so that no intermediate state had a schema the shipped Dart code couldn't
--  read. The repository and all three offering screens now read meetings
--  from course_offering_meetings exclusively -- verified with a repo-wide
--  grep for these column names against `course_offerings` -- so the old
--  inline columns are dead weight.
--
--  Leaving them would be actively harmful rather than merely untidy: two
--  places claiming to hold "when does this class meet" is exactly the kind
--  of drift that produced the batch/section triple-store this session had to
--  reconcile, and a future writer could populate the wrong one and have the
--  routine silently disagree with the offering.
--
--  Safe: course_offerings has no rows, and no code path reads or writes
--  these columns any more.
--
--  course_offerings.semester (the 1..12 programme semester) is NOT dropped
--  -- that is a different concept from a meeting time and is still used.
-- =====================================================================

ALTER TABLE course_offerings
  DROP COLUMN IF EXISTS day_of_week,
  DROP COLUMN IF EXISTS start_time,
  DROP COLUMN IF EXISTS end_time,
  DROP COLUMN IF EXISTS room_number,
  DROP COLUMN IF EXISTS building;

NOTIFY pgrst, 'reload schema';
