-- =====================================================================
--  AFOS — Mentorship booking: enforce availability + block self-approval
--
--  Found two gaps while wiring the teacher availability toggle:
--  1. insert_booking only checked auth.uid() = student_id — a student
--     could still INSERT a booking against a mentor who has turned
--     mentorship off (is_accepting_bookings = false); the "off" toggle
--     was UI-only, not enforced in the database.
--  2. update_booking let EITHER party update ANY column including
--     status — meaning a student could set their own booking's status
--     to 'confirmed' directly via the API, self-approving without the
--     teacher ever responding.
-- =====================================================================

DROP POLICY IF EXISTS "insert_booking" ON mentorship_bookings;
CREATE POLICY "insert_booking" ON mentorship_bookings FOR INSERT WITH CHECK (
  auth.uid() = student_id
  AND EXISTS (SELECT 1 FROM mentors m WHERE m.id = mentor_id AND m.is_accepting_bookings = true)
);

DROP POLICY IF EXISTS "update_booking" ON mentorship_bookings;
CREATE POLICY "update_booking" ON mentorship_bookings FOR UPDATE
  USING (auth.uid() = mentor_id OR auth.uid() = student_id)
  WITH CHECK (
    auth.uid() = mentor_id
    OR (auth.uid() = student_id AND status <> 'confirmed')
  );
