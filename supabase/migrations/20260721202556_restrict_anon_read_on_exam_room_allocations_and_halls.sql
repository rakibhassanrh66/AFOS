-- SEC-5: two RLS read policies admit anon, contradicting their own names.
--
-- Rounds 1 and 2 only ever looked at FUNCTIONS. Sweeping the other half of the
-- surface -- views, table grants, and the policies themselves -- turned up a
-- live leak that no previous audit had caught.
--
-- Both policies are literally named `auth_read_*`, but were created with no TO
-- clause. A policy with no TO clause defaults to PUBLIC, which includes anon,
-- and both had `USING (true)`. Proven with a role-simulated probe:
--
--   ANON sees exam_room_allocations = 1632   (of 1632)
--   ANON sees halls                 = 5      (of 5)
--
-- exam_room_allocations holds no personal identifiers, so this is not a PII
-- breach -- but it is the university's entire exam timetable: exam_date,
-- slot_start/end, course_code, course_title, teacher_initial, batch, section,
-- room_no. Readable by anyone on the internet, before the exams happen.
--
-- The same probe confirmed profiles, students, sos_alerts and sos_responses all
-- return 0 rows for anon, so those are correctly gated and are NOT changed here.
-- In particular sos_responses' `EXISTS (SELECT 1 FROM sos_alerts ...)` does
-- mirror parent-alert visibility as intended: RLS applies to subqueries inside
-- policy expressions too, so the caller only matches alerts they can already see.
--
-- The write policies are already correct (admin/exam_controller via auth.uid())
-- and are deliberately left alone -- only the read side is widened.
--
-- ALTER POLICY ... TO is used rather than DROP + CREATE so the USING expression
-- is preserved exactly and there is no window where the table is unprotected.

alter policy auth_read_exam_room_allocations
  on public.exam_room_allocations
  to authenticated;

alter policy auth_read_halls
  on public.halls
  to authenticated;

-- Deliberately NOT changed, recorded so the next sweep does not re-litigate them:
--
--   departments / programs / roles  -- `USING (true)` to {anon,authenticated} is
--     intentional: the signup and complete-profile screens populate their
--     dropdowns from these BEFORE a session exists. Restricting them breaks
--     registration. They are non-sensitive reference data.
--   app_releases  -- public read is the point (the What's New feed).
--   club_events (visible_from <= now()) and staff_designations (is_active) --
--     non-sensitive, and already filtered rather than blanket-true.
--   halls.admin_write_halls -- roles is {public}, which reads alarmingly, but its
--     USING requires `profiles.id = auth.uid()`, which anon can never satisfy.
--     A no-op to tighten, so left alone to keep this migration's blast radius
--     to the read side only.
