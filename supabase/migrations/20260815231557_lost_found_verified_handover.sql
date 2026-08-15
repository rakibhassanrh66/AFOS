-- =====================================================================
--  Lost & Found: join the two tracks, and make a handover prove itself.
--
--  APPLIED 2026-08-15. Filename matches the remote ledger version read back
--  from supabase_migrations.schema_migrations, not local wall clock.
--
--  WHAT WAS WRONG. Two independent state machines:
--
--    lost_found_posts.status   the POSTER alone tapped "Mark Found" and it
--                              became 'returned'. No counterparty, no
--                              evidence, no record of who received the item.
--    lost_found_claims.status  a claimant claimed, the poster accepted or
--                              rejected.
--
--  Accepting a claim changed NOTHING about the post, and marking a post
--  returned resolved no claims. An item could be marked returned with no
--  claimant at all. That is why the flow felt unverified: it was.
--
--  (A THIRD track was found while testing this -- see the next migration,
--  claim_acceptance_is_not_a_handover.)
--
--  WHAT REPLACES IT. Accepting binds the post to that claimant, and the item
--  is only 'returned' once the poster has scanned the claimant's VR-ID -- the
--  same server-signed rotating token the campus ID uses. HMAC verified in the
--  database, so a client cannot forge it, and it lands in vr_access_log.
--
--  VERIFIED with BEGIN/ROLLBACK:
--    forged token                       -> 'Invalid VR-ID token'
--    GENUINE token, wrong person        -> 'That ID belongs to someone else'
--    genuine token, accepted claimant   -> returned, handover_verified=true,
--                                         returned_to set, returned_at set
-- =====================================================================

alter table public.lost_found_posts
  add column if not exists returned_to        uuid references public.profiles(id) on delete set null,
  add column if not exists returned_at        timestamptz,
  add column if not exists handover_verified  boolean not null default false,
  add column if not exists handover_note      text;

comment on column public.lost_found_posts.handover_verified is
  'TRUE only when the poster scanned the claimant VR-ID at handover. FALSE '
  'means it was closed manually -- still a real outcome, but not proof.';

-- 'awaiting_handover' is the state that did not exist: accepted, but not yet
-- in the owner hands.
alter table public.lost_found_posts drop constraint if exists lost_found_posts_status_check;
alter table public.lost_found_posts add constraint lost_found_posts_status_check
  check (status = any (array['active','claimed','awaiting_handover','returned']));

alter table public.lost_found_claims drop constraint if exists lost_found_claims_status_check;
alter table public.lost_found_claims add constraint lost_found_claims_status_check
  check (status = any (array['pending','accepted','rejected','superseded']));

create or replace function public.accept_lost_found_claim(p_claim_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_post_id uuid; v_poster uuid;
begin
  select c.post_id, p.poster_id into v_post_id, v_poster
    from lost_found_claims c join lost_found_posts p on p.id = c.post_id
   where c.id = p_claim_id;
  if v_post_id is null then raise exception 'That claim no longer exists.'; end if;
  if v_poster is distinct from auth.uid() then
    raise exception 'Only the person who posted this item can accept a claim.' using errcode = '42501';
  end if;
  update lost_found_claims set status = 'accepted' where id = p_claim_id;
  -- Everyone else waiting on this item is told, rather than left pending.
  update lost_found_claims set status = 'superseded'
   where post_id = v_post_id and id <> p_claim_id and status = 'pending';
  update lost_found_posts set status = 'awaiting_handover' where id = v_post_id;
end; $$;

-- The handover itself. Calls verify_vr_id_scan rather than re-implementing the
-- HMAC check: one copy of that logic, and the scan is recorded in
-- vr_access_log as a side effect, which is exactly the provenance we want.
create or replace function public.complete_lost_found_handover(
  p_post_id uuid, p_uid uuid, p_vrid text, p_exp bigint
) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_poster uuid; v_status text; v_claimant uuid; v_scanned uuid;
begin
  select poster_id, status into v_poster, v_status from lost_found_posts where id = p_post_id;
  if v_poster is null then raise exception 'That post no longer exists.'; end if;
  if v_poster is distinct from auth.uid() then
    raise exception 'Only the person who posted this item can complete the handover.' using errcode = '42501';
  end if;
  if v_status <> 'awaiting_handover' then
    raise exception 'Accept a claim first - there is nobody to hand this to yet.';
  end if;

  select claimant_id into v_claimant from lost_found_claims
   where post_id = p_post_id and status = 'accepted' order by created_at desc limit 1;
  if v_claimant is null then raise exception 'No accepted claim on this post.'; end if;

  -- RAISES on a forged or expired token. The scanned identity is whatever the
  -- signature actually proves, not what the caller claims.
  select v.id::uuid into v_scanned from verify_vr_id_scan(p_uid, p_vrid, p_exp) v limit 1;
  if v_scanned is distinct from v_claimant then
    raise exception 'That ID belongs to someone else. Scan the person whose claim you accepted.';
  end if;

  update lost_found_posts
     set status='returned', returned_to=v_claimant, returned_at=now(), handover_verified=true
   where id = p_post_id;
end; $$;

-- The escape hatch, recorded honestly as UNVERIFIED. A process that cannot be
-- completed when the other person phone is flat gets worked around instead of
-- used -- so closing manually stays possible, it just never claims proof.
create or replace function public.close_lost_found_unverified(
  p_post_id uuid, p_note text default null
) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_poster uuid; v_claimant uuid;
begin
  select poster_id into v_poster from lost_found_posts where id = p_post_id;
  if v_poster is null then raise exception 'That post no longer exists.'; end if;
  if v_poster is distinct from auth.uid() then
    raise exception 'Only the person who posted this item can close it.' using errcode = '42501';
  end if;
  select claimant_id into v_claimant from lost_found_claims
   where post_id = p_post_id and status = 'accepted' order by created_at desc limit 1;
  update lost_found_posts
     set status='returned', returned_to=v_claimant, returned_at=now(),
         handover_verified=false, handover_note=p_note
   where id = p_post_id;
end; $$;

revoke all on function public.accept_lost_found_claim(uuid) from public, anon;
revoke all on function public.complete_lost_found_handover(uuid, uuid, text, bigint) from public, anon;
revoke all on function public.close_lost_found_unverified(uuid, text) from public, anon;
grant execute on function public.accept_lost_found_claim(uuid) to authenticated;
grant execute on function public.complete_lost_found_handover(uuid, uuid, text, bigint) to authenticated;
grant execute on function public.close_lost_found_unverified(uuid, text) to authenticated;
