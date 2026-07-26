-- Club supervisor / assistant supervisor posts.
--
-- Reuses the existing club_post_requests -> admin approval -> club_members.role
-- pipeline rather than adding a parallel one: the only thing missing was that
-- the requested_role CHECK didn't allow the two supervisor posts.
--
-- These two differ from secretary/vice_president/president in who holds them:
-- a supervisor is a faculty member, not a student officer, and is typically
-- not already a member of the club when they apply. The approving code path
-- therefore upserts into club_members instead of updating an assumed-existing
-- row (see _approvePost in manage_clubs_screen.dart).

ALTER TABLE club_post_requests DROP CONSTRAINT IF EXISTS club_post_requests_requested_role_check;
ALTER TABLE club_post_requests ADD CONSTRAINT club_post_requests_requested_role_check
  CHECK (requested_role = ANY (ARRAY[
    'secretary'::text,
    'vice_president'::text,
    'president'::text,
    'supervisor'::text,
    'assistant_supervisor'::text
  ]));
