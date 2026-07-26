-- Full user-deletion support for the super-admin "delete user entirely"
-- feature. Before this, almost every content table had a plain (NO ACTION)
-- FK to profiles.id, which meant auth.admin.deleteUser() would fail outright
-- for any account with real activity (a booking, a message, a claim, etc.)
-- — this is why full user deletion was never actually possible.
--
-- Two policies, matched to what each row represents:
--  - CASCADE: rows that are the user's own personal content/activity — it
--    makes sense for these to disappear with the account (matches "delete
--    that user entirely and all of his works").
--  - SET NULL: rows that are shared/institutional content or a positional
--    reference — deleting the *row* just because the referenced person's
--    account was removed would be wrong (e.g. removing a club's president
--    account should not delete the whole club).

ALTER TABLE borrowed_books DROP CONSTRAINT borrowed_books_student_id_fkey,
  ADD CONSTRAINT borrowed_books_student_id_fkey FOREIGN KEY (student_id) REFERENCES profiles(id) ON DELETE CASCADE;
ALTER TABLE club_members DROP CONSTRAINT club_members_member_id_fkey,
  ADD CONSTRAINT club_members_member_id_fkey FOREIGN KEY (member_id) REFERENCES profiles(id) ON DELETE CASCADE;
ALTER TABLE dept_messages DROP CONSTRAINT dept_messages_sender_id_fkey,
  ADD CONSTRAINT dept_messages_sender_id_fkey FOREIGN KEY (sender_id) REFERENCES profiles(id) ON DELETE CASCADE;
ALTER TABLE event_registrations DROP CONSTRAINT event_registrations_student_id_fkey,
  ADD CONSTRAINT event_registrations_student_id_fkey FOREIGN KEY (student_id) REFERENCES profiles(id) ON DELETE CASCADE;
ALTER TABLE exam_seat_assignments DROP CONSTRAINT exam_seat_assignments_student_id_fkey,
  ADD CONSTRAINT exam_seat_assignments_student_id_fkey FOREIGN KEY (student_id) REFERENCES profiles(id) ON DELETE CASCADE;
ALTER TABLE feedback DROP CONSTRAINT feedback_user_id_fkey,
  ADD CONSTRAINT feedback_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
ALTER TABLE hall_complaints DROP CONSTRAINT hall_complaints_student_id_fkey,
  ADD CONSTRAINT hall_complaints_student_id_fkey FOREIGN KEY (student_id) REFERENCES profiles(id) ON DELETE CASCADE;
ALTER TABLE lost_found_claims DROP CONSTRAINT lost_found_claims_claimant_id_fkey,
  ADD CONSTRAINT lost_found_claims_claimant_id_fkey FOREIGN KEY (claimant_id) REFERENCES profiles(id) ON DELETE CASCADE;
ALTER TABLE lost_found_posts DROP CONSTRAINT lost_found_posts_poster_id_fkey,
  ADD CONSTRAINT lost_found_posts_poster_id_fkey FOREIGN KEY (poster_id) REFERENCES profiles(id) ON DELETE CASCADE;
ALTER TABLE mentors DROP CONSTRAINT mentors_id_fkey,
  ADD CONSTRAINT mentors_id_fkey FOREIGN KEY (id) REFERENCES profiles(id) ON DELETE CASCADE;
ALTER TABLE mentorship_bookings DROP CONSTRAINT mentorship_bookings_student_id_fkey,
  ADD CONSTRAINT mentorship_bookings_student_id_fkey FOREIGN KEY (student_id) REFERENCES profiles(id) ON DELETE CASCADE;
ALTER TABLE payment_records DROP CONSTRAINT payment_records_student_id_fkey,
  ADD CONSTRAINT payment_records_student_id_fkey FOREIGN KEY (student_id) REFERENCES profiles(id) ON DELETE CASCADE;
ALTER TABLE user_notifications DROP CONSTRAINT user_notifications_user_id_fkey,
  ADD CONSTRAINT user_notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
ALTER TABLE vr_access_log DROP CONSTRAINT vr_access_log_scanned_user_id_fkey,
  ADD CONSTRAINT vr_access_log_scanned_user_id_fkey FOREIGN KEY (scanned_user_id) REFERENCES profiles(id) ON DELETE CASCADE;
ALTER TABLE vr_access_log DROP CONSTRAINT vr_access_log_scanned_by_id_fkey,
  ADD CONSTRAINT vr_access_log_scanned_by_id_fkey FOREIGN KEY (scanned_by_id) REFERENCES profiles(id) ON DELETE CASCADE;

ALTER TABLE audit_log DROP CONSTRAINT audit_log_changed_by_fkey,
  ADD CONSTRAINT audit_log_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES profiles(id) ON DELETE SET NULL;
ALTER TABLE buses DROP CONSTRAINT buses_driver_profile_id_fkey,
  ADD CONSTRAINT buses_driver_profile_id_fkey FOREIGN KEY (driver_profile_id) REFERENCES profiles(id) ON DELETE SET NULL;
ALTER TABLE clubs DROP CONSTRAINT clubs_president_id_fkey,
  ADD CONSTRAINT clubs_president_id_fkey FOREIGN KEY (president_id) REFERENCES profiles(id) ON DELETE SET NULL;
ALTER TABLE departments DROP CONSTRAINT departments_head_id_fkey,
  ADD CONSTRAINT departments_head_id_fkey FOREIGN KEY (head_id) REFERENCES profiles(id) ON DELETE SET NULL;
ALTER TABLE faculties DROP CONSTRAINT faculties_dean_id_fkey,
  ADD CONSTRAINT faculties_dean_id_fkey FOREIGN KEY (dean_id) REFERENCES profiles(id) ON DELETE SET NULL;
ALTER TABLE grade_change_requests DROP CONSTRAINT grade_change_requests_reviewed_by_fkey,
  ADD CONSTRAINT grade_change_requests_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES profiles(id) ON DELETE SET NULL;
ALTER TABLE notices DROP CONSTRAINT notices_author_id_fkey,
  ADD CONSTRAINT notices_author_id_fkey FOREIGN KEY (author_id) REFERENCES profiles(id) ON DELETE SET NULL;
ALTER TABLE roles DROP CONSTRAINT roles_created_by_fkey,
  ADD CONSTRAINT roles_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;
