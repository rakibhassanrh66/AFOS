-- Club chat, mirroring the existing dept_messages pattern (one implicit
-- room per club rather than multiple named channels, since a club has one
-- membership list, not department-style sub-audiences).
create table if not exists club_messages (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references clubs(id) on delete cascade,
  sender_id uuid not null references profiles(id) on delete cascade,
  content text not null,
  created_at timestamptz not null default now()
);

alter table club_messages enable row level security;

create policy club_members_read_messages on club_messages for select
  using (exists (select 1 from club_members cm where cm.club_id = club_messages.club_id and cm.member_id = auth.uid()));

create policy club_members_send_messages on club_messages for insert
  with check (sender_id = auth.uid()
    and exists (select 1 from club_members cm where cm.club_id = club_messages.club_id and cm.member_id = auth.uid()));

create policy club_members_delete_own_messages on club_messages for delete
  using (sender_id = auth.uid());

alter publication supabase_realtime add table club_messages;

-- Same 24h auto-expiry already running for dept_messages
-- ("expire-dept-messages", confirmed live via cron.job) — club chat needs
-- the identical behavior, not a separate/different retention rule.
select cron.schedule('expire-club-messages', '*/15 * * * *',
  $$DELETE FROM club_messages WHERE created_at < now() - interval '24 hours'$$);
