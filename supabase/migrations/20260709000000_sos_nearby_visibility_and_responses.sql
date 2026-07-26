-- User's explicit choice (asked directly, not guessed): anyone physically
-- near an active SOS alert should be able to see it and volunteer to help,
-- not just the zone-resolved recipient set trigger-sos-alert already
-- notifies. Same 5km/60min freshness thresholds as trigger-sos-alert's own
-- NEARBY_RADIUS_KM/NEARBY_STALE_MINUTES constants, so "who counts as
-- nearby" agrees everywhere in the app rather than drifting between the
-- edge function and this policy.
create policy nearby_select_sos_alerts on sos_alerts for select
using (
  status = 'active'
  and exists (
    select 1 from user_locations ul
    where ul.user_id = auth.uid()
      and ul.sharing_enabled = true
      and ul.latitude is not null and ul.longitude is not null
      and ul.updated_at >= now() - interval '60 minutes'
      and (
        6371 * 2 * asin(sqrt(
          power(sin(radians(ul.latitude - sos_alerts.latitude) / 2), 2) +
          cos(radians(sos_alerts.latitude)) * cos(radians(ul.latitude)) *
          power(sin(radians(ul.longitude - sos_alerts.longitude) / 2), 2)
        ))
      ) <= 5
  )
);

-- "I'm on my way" acknowledgments -- deliberately deferred in the original
-- SOS build, now explicitly requested: nearby volunteers register that
-- they're responding, and the alert owner + admins see who's coming, not
-- just that an alert exists.
create table sos_responses (
  id uuid primary key default gen_random_uuid(),
  alert_id uuid not null references sos_alerts(id) on delete cascade,
  responder_id uuid not null references profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (alert_id, responder_id)
);

alter table sos_responses enable row level security;

-- Visibility mirrors sos_alerts' own RLS exactly (this subquery re-runs
-- under the same requesting role, so it's gated by whichever of
-- own_select/recipient_select/nearby_select/admin_manage actually applies)
-- -- anyone who can see the alert can see who's responding to it.
create policy select_sos_responses on sos_responses for select
using (exists (select 1 from sos_alerts sa where sa.id = sos_responses.alert_id));

-- Registering as a responder requires being able to see the (still-active)
-- alert in the first place -- same visibility gate as the select policy,
-- not just "any authenticated user can insert any alert_id".
create policy insert_sos_responses on sos_responses for insert
with check (
  responder_id = auth.uid()
  and exists (select 1 from sos_alerts sa where sa.id = sos_responses.alert_id and sa.status = 'active')
);

-- A responder can withdraw their own "I'm on my way".
create policy own_delete_sos_response on sos_responses for delete
using (responder_id = auth.uid());

create policy admin_manage_sos_responses on sos_responses for all
using (get_my_profile_role() = ANY (ARRAY['admin', 'super_admin', 'staff']))
with check (get_my_profile_role() = ANY (ARRAY['admin', 'super_admin', 'staff']));
