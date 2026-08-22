-- grading_scale HAD RLS ENABLED AND NO POLICY, WHICH DENIES EVERY ROW.
--
-- Applied 2026-08-17 as ledger version 20260817182441.
--
-- Found by a backend sweep, not by a failure -- because it cannot fail loudly.
-- The chain:
--
--   trg_calculate_grade on marks  ->  calculate_grade()
--
-- calculate_grade() is one of 11 trigger functions here that are INVOKER
-- rather than SECURITY DEFINER (29 are DEFINER). The other 10 only assert on
-- NEW/OLD or read tables the caller can already see. This one reads
-- grading_scale, which authenticated could not see at all:
--
--   select count(*) from grading_scale  as authenticated  ->  0
--   select letter_grade ... 85          as owner          ->  'A+'
--
-- And the function does not check:
--
--   SELECT * INTO scale FROM grading_scale WHERE ... LIMIT 1;
--   NEW.letter_grade := scale.letter_grade;   -- NULL when nothing matched
--   NEW.grade_point  := scale.grade_point;    -- NULL when nothing matched
--
-- A plpgsql SELECT INTO that finds no row leaves the record NULL and raises
-- nothing, so any mark written by a plain authenticated user would be stored
-- UNGRADED, silently, with no error anywhere. Same failure shape as
-- 20260814224805 (blank instead of loud) and the view-drift gotcha: the
-- system does not break, it just quietly answers nothing.
--
-- NOT currently biting: marks is empty (0 rows) and the only SQL writer is
-- approve_grade_change(), which IS security definer and therefore bypasses
-- RLS. This is a landmine, not a fire -- the first direct PostgREST insert
-- into marks would arm it.
--
-- FIXED BY OPENING THE TABLE, NOT BY ELEVATING THE TRIGGER. Making
-- calculate_grade() SECURITY DEFINER would hand a write trigger owner rights
-- in order to fix a read problem. grading_scale is the published DIU grade
-- boundary table -- 10 rows of 80->A+, 75->A, ... 0->F. It is in every student
-- handbook. There is nothing here to protect, and a reader who can see their
-- own marks but not the scale those marks are graded against is incoherent.
--
-- Read-only, and authenticated only: anon has no business here, and the app
-- never writes this table at runtime.

create policy "Grading scale is readable by signed-in users"
  on grading_scale for select
  to authenticated
  using (true);

comment on table grading_scale is
  'Published DIU grade boundaries. Readable by any signed-in user: calculate_grade() runs as the INVOKER, so a locked table silently stored marks with a NULL letter_grade. Writes stay owner-only (no INSERT/UPDATE/DELETE policy).';

-- VERIFIED BEHAVIOURALLY as authenticated, after applying:
--   rows visible  10
--   85 -> 'A+'   38 -> 'F'   72 -> 3.50
--   INSERT       -> 42501 new row violates row-level security policy
