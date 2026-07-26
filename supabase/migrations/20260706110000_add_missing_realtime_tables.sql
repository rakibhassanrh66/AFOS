-- Systemic gap found while re-investigating "super admin can't see hall
-- applications": only 6 tables were ever added to supabase_realtime
-- (profiles, dept_messages, notices, schedule_slots, transport_live_status,
-- transport_routes), but every admin "manage" screen built since Phase 2
-- subscribes via .onPostgresChanges() to tables that were never added —
-- the subscription silently never fires (no error), so an admin who has
-- the screen already open never sees new/changed rows without manually
-- leaving and reopening it. Same root cause as the earlier profiles-
-- realtime fix (20260706000200), just never applied to these six tables.
ALTER PUBLICATION supabase_realtime ADD TABLE hall_applications;
ALTER PUBLICATION supabase_realtime ADD TABLE hall_complaints;
ALTER PUBLICATION supabase_realtime ADD TABLE cr_requests;
ALTER PUBLICATION supabase_realtime ADD TABLE conference_room_requests;
ALTER PUBLICATION supabase_realtime ADD TABLE club_membership_requests;
ALTER PUBLICATION supabase_realtime ADD TABLE club_post_requests;
