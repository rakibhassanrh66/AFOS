-- CREATE FUNCTION grants EXECUTE to PUBLIC by default, and the four triggers
-- added in 20260904085938_notify_on_request_decisions are SECURITY DEFINER, so
-- they landed reachable by anon and authenticated. check_definer_acls.py
-- caught it on the very next CI run, which is exactly what that audit is for --
-- the same omission has been cleaned up three times before in this project.
--
-- Nothing should call these directly: they are trigger bodies, invoked by the
-- table's own AFTER UPDATE, and a caller reaching one over PostgREST could
-- write an arbitrary notification into any user's tray. This matches the ACL
-- every other notify_* trigger already carries (postgres | service_role).

REVOKE ALL ON FUNCTION public.notify_club_membership_reviewed()   FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.notify_cr_request_reviewed()        FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.notify_hall_application_reviewed()  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.notify_mentorship_booking_reviewed() FROM PUBLIC, anon, authenticated;
