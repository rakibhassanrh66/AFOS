-- Backs the in-app "What's New" / release history screen. A real table
-- (not a hardcoded in-app list) so future releases can be added without a
-- code deploy, and so the list doesn't silently go stale the way a
-- hardcoded changelog would.
create table if not exists public.app_releases (
  id uuid primary key default gen_random_uuid(),
  version text not null,
  release_date date not null,
  title text not null,
  highlights text[] not null default '{}',
  platforms text[] not null default array['web', 'android', 'ios'],
  created_at timestamptz not null default now()
);

create unique index if not exists app_releases_version_idx on public.app_releases (version);

alter table public.app_releases enable row level security;

-- Public read -- this is meant to be visible to anyone using the app,
-- not gated by role.
create policy public_read_app_releases on public.app_releases
  for select using (true);

create policy admin_write_app_releases on public.app_releases for all using (
  exists (select 1 from profiles where profiles.id = auth.uid()
    and profiles.role in ('admin', 'dept_admin', 'super_admin'))
);

insert into public.app_releases (version, release_date, title, highlights, platforms) values
('1.0.0+7', '2026-07-13', 'Responsive Web & Security Hardening',
  array[
    'Desktop-width web now gets a real adaptive layout instead of a stretched phone screen -- a permanent nav rail, a two-pane login/register with an animated intro panel, and hover/glass polish throughout',
    'Fixed a critical Supabase security-advisor finding: a view was bypassing row-level security -- replaced with a properly hardened SECURITY DEFINER function',
    'Password reset was silently incomplete (the emailed link went nowhere) -- built the missing screen and wired native Android/iOS deep-linking so the link opens the right app instead of always falling back to a browser',
    'Dashboard, payment, and Lost & Found grids no longer balloon into oversized tiles on wide screens; module card icons are properly centered on every platform'
  ], array['web', 'android', 'ios']),
('1.0.0+6', '2026-07-12', 'Notification Fixes & Cross-Platform Cleanup',
  array[
    'Fixed the notification bell staying stuck on a stale count -- an out-of-order network response race, not the realtime bug fixed earlier',
    'Fixed a real crash: the SOS floating button''s voice-note recorder had no web implementation at all and threw the moment it was tapped',
    'iOS was missing camera/photo-library permission descriptions -- the QR scanner and photo upload would have crashed the app outright on a real iPhone'
  ], array['web', 'android', 'ios']),
('1.0.0+2', '2026-07-09', 'Offline Support, SOS System, and Routine Engine v2',
  array[
    'New offline architecture: read-cache for routine/transport/dashboard/notices, a write-outbox that queues actions (hall applications, complaints, feedback, bookings) until connectivity returns',
    'Emergency SOS system: hold-to-arm alert button, nearby-alert visibility, admin oversight, and an optional voice note',
    'Class routine parser rewritten for clean building/room parsing, lab tags, retakes, and lab-subgroup detection',
    'Notification tap-through now correctly deep-links to the relevant screen from both in-app and OS push taps'
  ], array['web', 'android', 'ios']),
('1.0.0+1', '2026-07-08', 'Dashboard Redesign & Real Staff Accounts',
  array[
    'Dashboard visual redesign and a real, distinct Staff account type',
    'A dozen live-verified bug fixes across hall applications, settings, and CI'
  ], array['web', 'android', 'ios']),
('1.0.0', '2026-07-06', 'Approval Gating, Clubs, and Grading',
  array[
    'New-user approval gating with a super-admin review dashboard',
    'Clubs system with a two-tier membership/officer approval flow',
    'Grading system, teacher assignments with automated deadline reminders, and conference room booking'
  ], array['web', 'android', 'ios'])
on conflict (version) do nothing;
