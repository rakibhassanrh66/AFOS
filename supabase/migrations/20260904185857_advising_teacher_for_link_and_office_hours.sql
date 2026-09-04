-- =====================================================================
--  The teacher card for a link the caller is already party to.
--
--  WHY THIS EXISTS. `resolve_teacher_initial` can only answer while the
--  student still has the initial typed in front of them. A student may not
--  read the teacher directory, so `teacher_links` embeds nothing useful, and
--  reopening the app left an ACTIVE advisor link rendering with no teacher on
--  it at all — the card knew who it was linked to and could not say.
--
--  Scoped to the caller's own link. A stranger's link id returns no rows
--  rather than raising, because someone poking at ids should learn nothing
--  from the difference between "not yours" and "does not exist".
--
--  Note the anon revoke sits IN this migration rather than in a follow-up:
--  `revoke ... from public` does not remove Supabase's explicit anon grant,
--  which is how the four functions before this one ended up reachable signed
--  out and had to be fixed in 20260904183424.
-- =====================================================================

create or replace function public.teacher_for_link(p_link_id uuid)
returns table (
  teacher_id      uuid,
  full_name       text,
  teacher_initial text,
  designation     text,
  department      text,
  avatar_url      text,
  email           text,
  phone           text,
  on_leave        boolean
)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  select p.id, p.full_name, p.teacher_initial, t.designation, p.department,
         p.avatar_url, p.email, p.phone,
         exists (select 1 from teacher_leave tl
                  where tl.teacher_id = p.id
                    and current_date between tl.starts_on and tl.ends_on)
    from teacher_links l
    join profiles p on p.id = l.teacher_id
    left join teachers t on t.profile_id = p.id
   where l.id = p_link_id
     and (l.student_id = auth.uid() or l.teacher_id = auth.uid()
          or can_browse_users())
   limit 1;
$function$;

revoke all on function public.teacher_for_link(uuid) from public;
revoke all on function public.teacher_for_link(uuid) from anon;
grant execute on function public.teacher_for_link(uuid) to authenticated;
