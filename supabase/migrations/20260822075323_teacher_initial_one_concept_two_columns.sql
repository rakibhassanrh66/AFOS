-- `teacher_initial` lives on BOTH `profiles` and `teachers`, and nothing kept
-- them in step.
--
-- `set_teacher_initial()` wrote only `teachers`. The routine screen's teacher
-- directory reads only `profiles`. `my_exam_schedule()` reads only `teachers`.
-- Measured before this migration: profiles held 2 initials, teachers held 0 —
-- so two teachers who already had an initial got no invigilation duties, and
-- setting one through the RPC would never have reached the routine directory.
--
-- Both columns stay (each has its own readers and its own RLS reach), but
-- there is now exactly one writer, and it writes both.
create or replace function set_teacher_initial(p_profile_id uuid, p_initial text)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v text := nullif(btrim(p_initial), '');
begin
  -- Gated INTERNALLY and raises, matching every other privileged RPC here.
  if not exists (
    select 1 from profiles p
    where p.id = (select auth.uid()) and p.is_verified
      and (p.role = any (array['admin','dept_admin','super_admin','exam_controller'])
           or caller_can('routine','upload')
           or caller_can('exam_seat','upload'))
  ) then
    raise exception 'Not permitted to set a teacher initial'
      using errcode = '42501';
  end if;

  update teachers set teacher_initial = v where profile_id = p_profile_id;
  if not found then
    raise exception 'No teacher record for that profile';
  end if;

  -- The denormalised copy the routine directory reads. Updated in the same
  -- statement so the two can never disagree again.
  update profiles set teacher_initial = v where id = p_profile_id;
end;
$fn$;

-- One-time reconciliation, in both directions, never overwriting a value that
-- is already there.
update teachers t
   set teacher_initial = p.teacher_initial
  from profiles p
 where p.id = t.profile_id
   and nullif(btrim(p.teacher_initial), '') is not null
   and nullif(btrim(t.teacher_initial), '') is null;

update profiles p
   set teacher_initial = t.teacher_initial
  from teachers t
 where t.profile_id = p.id
   and nullif(btrim(t.teacher_initial), '') is not null
   and nullif(btrim(p.teacher_initial), '') is null;
