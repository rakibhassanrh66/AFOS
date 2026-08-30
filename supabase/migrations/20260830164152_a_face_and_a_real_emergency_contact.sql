-- An emergency contact identical to the user's own number is not a second
-- point of contact, and nothing has ever required a real, checked photo.
-- complete_profile_screen.dart already collects emergency_contact and offers
-- AvatarPicker, but neither is enforced: emergency_contact can equal phone,
-- and avatar_url is entirely optional with no deadline and no review.
--
-- This extends profile_is_complete() (20260822105453) rather than building a
-- second gate: the router already redirects anyone with profile_completed =
-- false to /complete-profile, so folding both requirements into the same
-- function reuses that enforcement for free.
--
-- PHOTO DESIGN. avatar_url keeps its existing meaning everywhere it is
-- already read (~15 call sites across chat, attendance, schedule, dashboard,
-- clubs) -- "the live, approved photo". A newly submitted photo lands in
-- avatar_pending_url/avatar_review_status instead, and is only copied into
-- avatar_url on admin approval, so none of those existing readers change.
--
-- THE 48H CLOCK anchors on verified_at, stamped the instant is_verified first
-- becomes true (the one moment the account is genuinely usable at all, since
-- the router already blocks everything before is_verified). Backfilled from
-- created_at, not now() -- now() would hand every already-verified account a
-- fresh, undeserved two-day pass on a requirement meant to already apply to
-- them.
--
-- A SILENT USER STILL NEEDS TO BE CAUGHT. The trigger only re-fires on a
-- write to profiles; someone who does nothing for 48h needs the flag actively
-- recomputed. This project already solves exactly this shape with pg_cron
-- (expire-club-messages, expire-empty-room-requests) -- reconcile_avatar_
-- deadlines() does a no-op touch on anyone whose deadline just passed with no
-- compliant photo, which re-fires trg_profile_completeness.

alter table profiles
  add column if not exists verified_at timestamptz,
  add column if not exists avatar_pending_url text,
  add column if not exists avatar_review_status text not null default 'none'
    check (avatar_review_status in ('none', 'pending', 'approved', 'rejected')),
  add column if not exists avatar_review_reason text,
  add column if not exists avatar_submitted_at timestamptz,
  add column if not exists avatar_reviewed_by uuid references profiles(id),
  add column if not exists avatar_reviewed_at timestamptz;

comment on column profiles.avatar_url is
  'The live, admin-approved photo shown throughout the app. Not written '
  'directly by the client as of this migration -- see avatar_pending_url '
  'and my_submit_avatar().';
comment on column profiles.avatar_pending_url is
  'A submitted photo awaiting admin review. Copied into avatar_url by '
  'admin_approve_avatar(); cleared by admin_reject_avatar().';
comment on column profiles.verified_at is
  'Stamped the instant is_verified first becomes true. Anchors the 48h '
  'mandatory-photo grace period in profile_is_complete() -- never written '
  'anywhere else.';

update profiles set verified_at = created_at
 where is_verified = true and verified_at is null;

-- ---------------------------------------------------------------------------
-- profile_is_complete(): two more "everyone" clauses, same signature.
-- ---------------------------------------------------------------------------
create or replace function profile_is_complete(p profiles)
returns boolean language sql stable set search_path to 'public' as $$
  select
    nullif(btrim(coalesce(p.full_name, '')), '')            is not null
    and nullif(btrim(coalesce(p.phone, '')), '')            is not null
    and nullif(btrim(coalesce(p.gender, '')), '')           is not null
    and nullif(btrim(coalesce(p.emergency_contact, '')), '') is not null
    and nullif(btrim(coalesce(p.permanent_division, '')), '') is not null
    and nullif(btrim(coalesce(p.permanent_district, '')), '') is not null
    and nullif(btrim(coalesce(p.permanent_upazila, '')), '')  is not null
    -- Digit-only comparison so formatting ("+880 1712-345678" vs
    -- "01712345678") cannot dodge the check -- they must still be a
    -- DIFFERENT number, not just differently typed.
    and (
      nullif(regexp_replace(coalesce(p.emergency_contact, ''), '\D', '', 'g'), '')
      is distinct from
      nullif(regexp_replace(coalesce(p.phone, ''), '\D', '', 'g'), '')
    )
    -- Compliant while: not yet verified (is_verified already blocks this
    -- account from doing anything, so the photo clock has not started);
    -- still inside the 48h grace window; or already engaged (a photo is
    -- pending review, or was approved). Only "never uploaded" or "uploaded
    -- and rejected, never resubmitted" blocks once the deadline passes.
    and (
      p.verified_at is null
      or now() - p.verified_at < interval '48 hours'
      or p.avatar_review_status in ('pending', 'approved')
    )
    and case p.role
      when 'student' then
        p.department_id is not null
        and nullif(btrim(coalesce(p.batch, '')), '')   is not null
        and nullif(btrim(coalesce(p.section, '')), '') is not null
        and p.semester         is not null
        and p.admission_season is not null
        and p.admission_year   is not null
        and p.joined_on        is not null
      when 'teacher' then
        p.department_id is not null and p.joined_on is not null
        and exists (select 1 from teachers t
                     where t.profile_id = p.id
                       and nullif(btrim(coalesce(t.designation, '')), '') is not null)
      when 'staff' then
        p.joined_on is not null
        and exists (select 1 from staff s
                     where s.profile_id = p.id
                       and nullif(btrim(coalesce(s.designation, '')), '') is not null)
      else
        nullif(btrim(coalesce(p.role, '')), '') is not null
    end
$$;

-- ---------------------------------------------------------------------------
-- The user's own submit path. No admin check -- everyone submits their own.
-- ---------------------------------------------------------------------------
create or replace function public.my_submit_avatar(p_url text)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  if p_url is null or btrim(p_url) = '' then
    raise exception 'A photo URL is required' using errcode = '22023';
  end if;
  update profiles
     set avatar_pending_url = p_url,
         avatar_review_status = 'pending',
         avatar_submitted_at = now(),
         avatar_review_reason = null
   where id = auth.uid();
end;
$$;

revoke all on function public.my_submit_avatar(text) from public, anon;
grant execute on function public.my_submit_avatar(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Admin review queue. Same authorization pattern as admin_user_groups /
-- admin_search_users -- can_browse_users() is the exact population the owner
-- asked to reuse (the Pending-registrations approval population).
-- ---------------------------------------------------------------------------
create or replace function public.admin_list_pending_avatars(p_limit int default 100)
returns table (
  id uuid, full_name text, email text, role text,
  avatar_pending_url text, avatar_submitted_at timestamptz
)
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  if not can_browse_users() then
    raise exception 'Not authorized to browse users' using errcode = '42501';
  end if;

  return query
  select p.id, p.full_name, p.email, p.role,
         p.avatar_pending_url, p.avatar_submitted_at
    from profiles p
   where p.avatar_review_status = 'pending'
   order by p.avatar_submitted_at asc nulls last
   limit greatest(1, least(coalesce(p_limit, 100), 200));
end;
$$;

revoke all on function public.admin_list_pending_avatars(int) from public, anon;
grant execute on function public.admin_list_pending_avatars(int) to authenticated;

create or replace function public.admin_approve_avatar(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  if not can_browse_users() then
    raise exception 'Not authorized to browse users' using errcode = '42501';
  end if;

  update profiles
     set avatar_url = avatar_pending_url,
         avatar_pending_url = null,
         avatar_review_status = 'approved',
         avatar_reviewed_by = auth.uid(),
         avatar_reviewed_at = now(),
         avatar_review_reason = null
   where id = p_user_id and avatar_review_status = 'pending';
end;
$$;

revoke all on function public.admin_approve_avatar(uuid) from public, anon;
grant execute on function public.admin_approve_avatar(uuid) to authenticated;

create or replace function public.admin_reject_avatar(p_user_id uuid, p_reason text default null)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  if not can_browse_users() then
    raise exception 'Not authorized to browse users' using errcode = '42501';
  end if;

  update profiles
     set avatar_pending_url = null,
         avatar_review_status = 'rejected',
         avatar_review_reason = nullif(btrim(coalesce(p_reason, '')), ''),
         avatar_reviewed_by = auth.uid(),
         avatar_reviewed_at = now()
   where id = p_user_id and avatar_review_status = 'pending';
end;
$$;

revoke all on function public.admin_reject_avatar(uuid, text) from public, anon;
grant execute on function public.admin_reject_avatar(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- The sweep. Cron-only -- not exposed to authenticated/anon at all.
-- ---------------------------------------------------------------------------
create or replace function public.reconcile_avatar_deadlines()
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  -- A no-op write is enough: it re-fires trg_profile_completeness, which
  -- recomputes profile_is_complete() and this time finds the deadline passed.
  -- Scoped to profile_completed = true so a row already flipped false is
  -- never re-touched on every tick.
  update profiles
     set updated_at = updated_at
   where profile_completed = true
     and verified_at is not null
     and verified_at + interval '48 hours' <= now()
     and avatar_review_status not in ('pending', 'approved');
end;
$$;

revoke all on function public.reconcile_avatar_deadlines() from public, anon, authenticated;

select cron.schedule('reconcile-avatar-deadlines', '*/15 * * * *',
  $$select public.reconcile_avatar_deadlines()$$);
