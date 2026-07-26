-- =====================================================================
--  AFOS — Let a mentor read the profile of a student who booked them
--
--  Found by live-testing the new mentorship "Requests" tab: the teacher's
--  query for their own incoming bookings succeeded, but the embedded
--  profiles!student_id join came back null — no RLS policy let a teacher
--  view an arbitrary student's profile at all, so the request showed up
--  with no name attached. Scope this to only students who actually have
--  a booking (of any status) with that specific mentor.
-- =====================================================================

CREATE POLICY "mentor_reads_own_booking_students" ON profiles FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM mentorship_bookings b
    WHERE b.mentor_id = auth.uid() AND b.student_id = profiles.id
  )
);
