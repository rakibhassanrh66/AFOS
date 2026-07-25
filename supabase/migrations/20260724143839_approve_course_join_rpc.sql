create or replace function public.approve_course_join(p_enrollment_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_student_id uuid;
  v_offering_id uuid;
  v_teacher_id uuid;
  v_slot_id uuid;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select e.student_id, e.offering_id, co.teacher_id
    into v_student_id, v_offering_id, v_teacher_id
  from enrollments e
  join course_offerings co on co.id = e.offering_id
  where e.id = p_enrollment_id and e.status = 'pending';

  if v_student_id is null then
    raise exception 'Join request not found or already reviewed';
  end if;

  if v_teacher_id is distinct from auth.uid()
     and get_my_profile_role() not in ('admin','dept_admin','super_admin')
     and not caller_can('enrollments','manage') then
    raise exception 'Only the offering''s teacher or an admin can approve this request';
  end if;

  update enrollments set status = 'approved' where id = p_enrollment_id;

  select id into v_slot_id from schedule_slots where course_offering_id = v_offering_id limit 1;
  if v_slot_id is not null then
    insert into user_pinned_slots (user_id, schedule_slot_id)
      values (v_student_id, v_slot_id)
      on conflict (user_id, schedule_slot_id) do nothing;
  end if;
end;
$$;

grant execute on function public.approve_course_join(uuid) to authenticated;
