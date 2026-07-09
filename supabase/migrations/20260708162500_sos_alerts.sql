-- SOS / Emergency Alert system, core alert record. Recipient resolution
-- itself lives in the trigger-sos-alert edge function (runs with the
-- service-role key, bypasses RLS entirely by design), but the table still
-- needs RLS for the sender's own view, admin oversight, and a recipient
-- opening the alert detail screen from a push notification.
create table sos_alerts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id),
  latitude double precision not null,
  longitude double precision not null,
  zone_type text not null check (zone_type in ('campus','zila')),
  message text,
  voice_path text,
  status text not null default 'active' check (status in ('active','resolved','false_alarm')),
  recipient_count int not null default 0,
  resolved_by uuid references profiles(id),
  resolved_at timestamptz,
  created_at timestamptz not null default now()
);

alter table sos_alerts enable row level security;

create policy own_select_sos_alerts on sos_alerts
  for select using (auth.uid() = user_id);

create policy admin_manage_sos_alerts on sos_alerts
  for all using (get_my_profile_role() in ('admin','super_admin','staff'))
  with check (get_my_profile_role() in ('admin','super_admin','staff'));

-- A recipient may open the alert they were actually notified about (from
-- the push's deep link) without being granted broad read access to every
-- alert in the system.
create policy recipient_select_sos_alerts on sos_alerts
  for select using (
    exists (
      select 1 from user_notifications un
      where un.user_id = auth.uid()
        and un.category = 'sos'
        and un.deep_link_route = '/sos/' || sos_alerts.id::text
    )
  );

alter publication supabase_realtime add table sos_alerts;
