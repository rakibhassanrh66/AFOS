-- App-wide config flags (single row). First flag: the SOS visibility gate.
-- Purely a visibility/access toggle on top of the existing SOS feature — it
-- does NOT restructure any sos_alerts / user_locations / sos_responses data.
create table if not exists public.app_config (
  id smallint primary key default 1 check (id = 1),
  sos_enabled boolean not null default false,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete set null
);

-- Exactly one row, id = 1.
insert into public.app_config (id, sos_enabled)
values (1, false)
on conflict (id) do nothing;

alter table public.app_config enable row level security;

-- Every signed-in user can READ the flag (to decide whether to show SOS).
drop policy if exists app_config_select on public.app_config;
create policy app_config_select on public.app_config
  for select to authenticated
  using (true);

-- Only super_admin may FLIP it. get_my_profile_role() is the existing
-- SECURITY DEFINER role accessor used elsewhere for admin gating.
drop policy if exists app_config_update on public.app_config;
create policy app_config_update on public.app_config
  for update to authenticated
  using (public.get_my_profile_role() = 'super_admin')
  with check (public.get_my_profile_role() = 'super_admin');

-- Live propagation so flipping the toggle reflects on every device at once.
alter publication supabase_realtime add table public.app_config;
