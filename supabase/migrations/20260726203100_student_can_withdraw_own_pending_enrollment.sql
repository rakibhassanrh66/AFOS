-- A student could ask to join a course and then had no way to take it back.
--
-- enrollments had no DELETE policy at all, and UPDATE only for the offering's
-- teacher. So a request sent by mistake -- wrong section, wrong course, changed
-- mind -- sat in the teacher's queue permanently, and the student's only
-- feedback was a dead "REQUEST PENDING" badge with nothing to press. The
-- missing button in Browse Courses was the symptom; this was the cause.
--
-- Scoped to PENDING only, deliberately:
--   * 'approved' is enrolment, not a request. Leaving a course you are in is a
--     drop -- it has consequences for attendance, marks and the section cap --
--     and belongs with the teacher or admin, not a swipe by the student.
--   * 'rejected' is the teacher's decision and part of the record. Letting the
--     student delete it would quietly erase that and allow an unlimited
--     re-apply loop against a decision already made.
--
-- DELETE rather than a 'withdrawn' status: a request that was never decided is
-- not a decision worth keeping, and a status would need adding to the CHECK and
-- then filtering out of every teacher-facing query -- more surface for a row to
-- reappear somewhere it should not.
--
-- Verified live under SET LOCAL ROLE authenticated: a student cannot delete
-- another student's pending request, cannot delete their own APPROVED
-- enrolment, and can delete their own pending one.

DROP POLICY IF EXISTS student_withdraw_own_pending_enrollment ON enrollments;
CREATE POLICY student_withdraw_own_pending_enrollment ON enrollments
  FOR DELETE TO authenticated
  USING (
    student_id = (SELECT auth.uid())
    AND status = 'pending'
  );
