-- club_events already existed (read-only, queried in clubs_screen.dart) but
-- had zero rows ever and no INSERT policy at all — a president could not
-- actually create an event through any path, client or RLS. Also its one
-- existing SELECT policy ("auth_read_events") made every event visible to
-- every authenticated user immediately, with no way to time-gate visibility
-- as requested ("president sets a time, event becomes visible to everyone
-- at that time").
alter table club_events add column if not exists visible_from timestamptz not null default now();
alter table club_events add column if not exists created_by uuid references profiles(id) on delete set null;

drop policy if exists auth_read_events on club_events;

-- Club members always see their own club's events regardless of
-- visible_from (they shouldn't be kept in the dark about their own club).
create policy members_read_own_club_events on club_events for select
  using (exists (select 1 from club_members cm where cm.club_id = club_events.club_id and cm.member_id = auth.uid()));

-- Everyone else only sees an event once its president-set reveal time
-- arrives — this is the actual time-gating the feature asked for.
create policy everyone_read_visible_events on club_events for select
  using (visible_from <= now());

create policy president_create_events on club_events for insert
  with check (created_by = auth.uid()
    and exists (select 1 from clubs c where c.id = club_events.club_id and c.president_id = auth.uid()));

create policy president_update_own_events on club_events for update
  using (exists (select 1 from clubs c where c.id = club_events.club_id and c.president_id = auth.uid()));

create policy president_delete_own_events on club_events for delete
  using (exists (select 1 from clubs c where c.id = club_events.club_id and c.president_id = auth.uid()));
