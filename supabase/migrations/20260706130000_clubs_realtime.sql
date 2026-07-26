-- clubs_screen.dart only ever did a one-time fetch with no live updates —
-- a student's own membership status (pending -> joined) or a new club
-- being added never appeared without manually leaving and reopening the
-- screen. club_membership_requests/club_post_requests were already added
-- to the realtime publication for the admin-side screen; clubs and
-- club_members were not, and are needed for the student/president-facing
-- screen to actually reflect live changes.
ALTER PUBLICATION supabase_realtime ADD TABLE clubs;
ALTER PUBLICATION supabase_realtime ADD TABLE club_members;
