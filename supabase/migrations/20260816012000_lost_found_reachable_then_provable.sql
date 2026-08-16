-- Lost & Found: reachable, then provable.
--
-- APPLIED 2026-08-16.
--
-- The flow read as inauthentic because it was. Measured, not guessed:
--   * profiles.phone is nullable and 4 of 11 profiles had none, so "call them"
--     had nothing to call;
--   * contact_preference / contact_value have ZERO references in lib/ -- dead
--     columns since the day they were added;
--   * auth_read_lf is `status <> 'deleted'`, so anything written to
--     contact_value is readable by every authenticated user on campus;
--   * own_lf_manage is an ALL policy on poster_id, so the poster could write
--     status='returned' straight from the client and skip the verified RPC;
--   * returned_to was always the claimant -- wrong for a `lost` post.

-- ---------------------------------------------------------------- 24h thread
alter table public.lost_found_claims add column if not exists accepted_at timestamptz;

create table if not exists public.lost_found_messages (
  id          bigserial primary key,
  post_id     uuid not null references public.lost_found_posts(id) on delete cascade,
  sender_id   uuid not null references public.profiles(id) on delete cascade,
  body        text not null check (btrim(body) <> '' and length(body) <= 1000),
  created_at  timestamptz not null default now()
);
create index if not exists lost_found_messages_post_idx
  on public.lost_found_messages (post_id, created_at);
alter table public.lost_found_messages enable row level security;

-- One helper so the read policy, the write policy, the contact RPC and the app
-- all agree on who is on a thread and whether it is still open.
create or replace function public.lost_found_thread_open(p_post_id uuid, p_user uuid)
returns boolean
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $function$
  select exists (
    select 1
      from lost_found_posts p
      join lost_found_claims c on c.post_id = p.id and c.status = 'accepted'
     where p.id = p_post_id
       and (p_user = p.poster_id or p_user = c.claimant_id)
       and c.accepted_at is not null
       and now() < c.accepted_at + interval '24 hours'
  );
$function$;
revoke all on function public.lost_found_thread_open(uuid, uuid) from public, anon;
grant execute on function public.lost_found_thread_open(uuid, uuid) to authenticated;

-- The 24h window lives in the RLS predicate, NOT in a cleanup job. An expired
-- thread is unreadable the moment it expires, whether or not any row was ever
-- deleted -- so "it disappears within 24 hours" is a property of the database
-- rather than a promise about a cron that may not have run.
create policy lf_thread_read on public.lost_found_messages
  for select to authenticated
  using (lost_found_thread_open(post_id, (select auth.uid())));

create policy lf_thread_write on public.lost_found_messages
  for insert to authenticated
  with check (sender_id = (select auth.uid())
              and lost_found_thread_open(post_id, (select auth.uid())));

-- Deliberately no UPDATE and no DELETE policy for anyone. An agreement about
-- where to meet is evidence, and evidence one side can edit afterwards is
-- worth less than none.
create policy lf_thread_authority_read on public.lost_found_messages
  for select to authenticated
  using (get_my_profile_role() = 'super_admin'
         or caller_can('audit', 'read', (select auth.uid())));

-- ------------------------------------------------------------------- contact
-- The number is NEVER put on the post. It is released to one counterparty,
-- only after a claim is accepted, only while the thread is open.
create or replace function public.lost_found_counterparty_contact(p_post_id uuid)
returns table (profile_id uuid, full_name text, phone text, avatar_url text)
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_poster uuid; v_claimant uuid; v_me uuid := auth.uid(); v_other uuid;
begin
  if v_me is null then
    raise exception 'Sign in first.' using errcode = '42501';
  end if;

  select p.poster_id, c.claimant_id into v_poster, v_claimant
    from lost_found_posts p
    join lost_found_claims c on c.post_id = p.id and c.status = 'accepted'
   where p.id = p_post_id limit 1;

  if v_poster is null then
    raise exception 'Nobody has been matched to this item yet.';
  end if;
  if not lost_found_thread_open(p_post_id, v_me) then
    raise exception 'This contact window has closed.' using errcode = '42501';
  end if;

  v_other := case when v_me = v_poster then v_claimant
                  when v_me = v_claimant then v_poster end;
  if v_other is null then
    raise exception 'You are not part of this handover.' using errcode = '42501';
  end if;

  return query
    select pr.id, pr.full_name, nullif(btrim(pr.phone), ''), pr.avatar_url
      from profiles pr where pr.id = v_other;
end;
$function$;
revoke all on function public.lost_found_counterparty_contact(uuid) from public, anon;
grant execute on function public.lost_found_counterparty_contact(uuid) to authenticated;

-- Accepting a claim stamps when the 24h window opened.
create or replace function public.accept_lost_found_claim(p_claim_id uuid)
returns void
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_post_id uuid; v_poster uuid;
begin
  select c.post_id, p.poster_id into v_post_id, v_poster
    from lost_found_claims c join lost_found_posts p on p.id = c.post_id
   where c.id = p_claim_id;

  if v_post_id is null then
    raise exception 'That claim no longer exists.';
  end if;
  if v_poster is distinct from auth.uid() then
    raise exception 'Only the person who posted this item can accept a claim.'
      using errcode = '42501';
  end if;

  update lost_found_claims set status = 'accepted', accepted_at = now()
   where id = p_claim_id;
  update lost_found_claims set status = 'superseded'
   where post_id = v_post_id and id <> p_claim_id and status = 'pending';
  update lost_found_posts set status = 'awaiting_handover' where id = v_post_id;
end;
$function$;

-- ------------------------------------------------------------------ handover
-- WHO RECEIVES DEPENDS ON WHAT KIND OF POST IT IS.
--
-- The previous version always recorded returned_to = claimant and always
-- required the POSTER to call it. Right for a `found` post, backwards for a
-- `lost` one: there the poster is the person who lost the item and the
-- claimant is the person who found it, so the item travels TO the poster. The
-- log recorded the finder as having received the property.
--
--   type    | receiver (scans, and is recorded) | giver (is scanned)
--   --------+-----------------------------------+--------------------------
--   lost    | poster   -- they lost it          | claimant -- they found it
--   found   | claimant -- they own it           | poster   -- they found it
--
-- One rule underneath: THE RECEIVER SCANS THE GIVER. Whoever ends up holding
-- the item is the one who has to prove who handed it over.
create or replace function public.complete_lost_found_handover(
  p_post_id uuid, p_uid uuid, p_vrid text, p_exp bigint)
returns void
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_poster uuid; v_status text; v_type text;
  v_claimant uuid; v_scanned uuid;
  v_receiver uuid; v_giver uuid; v_me uuid := auth.uid();
begin
  select poster_id, status, type into v_poster, v_status, v_type
    from lost_found_posts where id = p_post_id;

  if v_poster is null then
    raise exception 'That post no longer exists.';
  end if;
  if v_status <> 'awaiting_handover' then
    raise exception 'Accept a claim first - there is nobody to hand this to yet.';
  end if;

  select claimant_id into v_claimant from lost_found_claims
   where post_id = p_post_id and status = 'accepted'
   order by created_at desc limit 1;
  if v_claimant is null then
    raise exception 'No accepted claim on this post.';
  end if;

  if v_type = 'lost' then
    v_receiver := v_poster;   v_giver := v_claimant;
  else
    v_receiver := v_claimant; v_giver := v_poster;
  end if;

  if v_me is distinct from v_receiver then
    raise exception 'Only the person receiving the item can confirm the handover.'
      using errcode = '42501';
  end if;

  -- Verifies the HMAC and the expiry, writes vr_access_log, and RAISES on a
  -- forged or expired token. The scanned identity is whatever the signature
  -- proves, not what the caller claims.
  select v.id::uuid into v_scanned
    from verify_vr_id_scan(p_uid, p_vrid, p_exp) v limit 1;

  if v_scanned is distinct from v_giver then
    raise exception 'That ID belongs to someone else. Scan the person handing the item over.';
  end if;

  perform set_config('afos.verified_handover', p_post_id::text, true);

  update lost_found_posts
     set status = 'returned', returned_to = v_receiver, returned_at = now(),
         handover_verified = true
   where id = p_post_id;
end;
$function$;

-- The escape hatch gets the same receiver rule, so the log reads consistently
-- whichever way an item was closed. A system that cannot be completed offline
-- gets worked around instead of used.
create or replace function public.close_lost_found_unverified(p_post_id uuid, p_note text default null)
returns void
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_poster uuid; v_type text; v_claimant uuid; v_receiver uuid;
begin
  select poster_id, type into v_poster, v_type from lost_found_posts where id = p_post_id;
  if v_poster is null then
    raise exception 'That post no longer exists.';
  end if;
  if v_poster is distinct from auth.uid() then
    raise exception 'Only the person who posted this item can close it.'
      using errcode = '42501';
  end if;

  select claimant_id into v_claimant from lost_found_claims
   where post_id = p_post_id and status = 'accepted'
   order by created_at desc limit 1;

  v_receiver := case when v_claimant is null then null
                     when v_type = 'lost' then v_poster
                     else v_claimant end;

  perform set_config('afos.verified_handover', p_post_id::text, true);

  update lost_found_posts
     set status = 'returned', returned_to = v_receiver, returned_at = now(),
         handover_verified = false, handover_note = p_note
   where id = p_post_id;
end;
$function$;

-- own_lf_manage is ALL on poster_id, so the poster could write
-- status='returned' straight from the client and skip both RPCs -- the exact
-- "mark it found and we are done" that made the flow feel unverified.
-- 'returned' is now reachable only through code that sets this marker, and a
-- PostgREST client cannot call set_config.
create or replace function public.guard_lost_found_returned()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
begin
  if NEW.status = 'returned' and OLD.status is distinct from 'returned' then
    if current_setting('afos.verified_handover', true) is distinct from NEW.id::text then
      raise exception 'Confirm the handover by scanning, or close it as unverified. This state cannot be set directly.';
    end if;
  end if;
  return NEW;
end;
$function$;

drop trigger if exists guard_lost_found_returned_trigger on public.lost_found_posts;
create trigger guard_lost_found_returned_trigger
  before update on public.lost_found_posts
  for each row execute function public.guard_lost_found_returned();
revoke all on function public.guard_lost_found_returned() from public, anon, authenticated;

-- --------------------------------------------------------------------- phone
-- "Every user must have a phone number for this app."
--
-- NOT a NOT NULL column and NOT a CHECK constraint. 4 of 11 existing profiles
-- have no phone, so NOT NULL would fail to apply -- and a NOT VALID CHECK only
-- skips the one-time scan, it still blocks UPDATEs, which would leave exactly
-- those users permanently unable to fix their own profile. The requirement is
-- enforced where a missing number actually breaks something.
create or replace function public.require_phone_for_lost_found()
returns trigger
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_phone text; v_user uuid;
begin
  v_user := case tg_table_name when 'lost_found_posts' then NEW.poster_id
                               else NEW.claimant_id end;
  select nullif(btrim(phone), '') into v_phone from profiles where id = v_user;
  if v_phone is null then
    raise exception 'Add your phone number in Settings first. Lost & Found only works if the other person can reach you.'
      using errcode = 'P0001';
  end if;
  return NEW;
end;
$function$;

drop trigger if exists require_phone_on_lf_post on public.lost_found_posts;
create trigger require_phone_on_lf_post before insert on public.lost_found_posts
  for each row execute function public.require_phone_for_lost_found();

drop trigger if exists require_phone_on_lf_claim on public.lost_found_claims;
create trigger require_phone_on_lf_claim before insert on public.lost_found_claims
  for each row execute function public.require_phone_for_lost_found();

revoke all on function public.require_phone_for_lost_found() from public, anon, authenticated;

-- ------------------------------------------------------------------ realtime
-- Without this the chat screen subscribes to a channel that never fires.
-- Supabase only streams changes for tables in the `supabase_realtime`
-- publication, and a new table is not added to it automatically -- so each
-- side would see the other's messages only by leaving and reopening the
-- thread. For a "meet me at the gate" conversation that is the whole feature
-- failing quietly, which is the worst way for it to fail.
--
-- Adding a table to the publication does NOT bypass RLS: realtime re-checks
-- the row policies per subscriber, so lf_thread_read still decides who
-- receives an event, including the 24-hour expiry.
alter publication supabase_realtime add table public.lost_found_messages;
