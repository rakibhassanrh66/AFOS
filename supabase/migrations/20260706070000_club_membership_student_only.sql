-- The original club_membership_requests insert policy only checked
-- auth.uid()=student_id, with no role restriction — any authenticated
-- user (including super_admin/teacher/staff) could technically request
-- club membership via a direct API call. Clubs are explicitly student-only
-- per spec ("super admin will not act like any student or teacher").
DROP POLICY IF EXISTS own_club_membership_request_insert ON club_membership_requests;

CREATE POLICY own_club_membership_request_insert ON club_membership_requests
  FOR INSERT
  WITH CHECK (auth.uid() = student_id AND get_my_profile_role() = 'student');
