-- A teacher's initial, which is how the examination documents name them.
--
-- The seat plan's "Tech. Int." column holds NNM, SMC, MRH -- the only
-- identifier those documents carry for a teacher, and nothing in the app could
-- resolve it to a person, so "show me my invigilation duty" was unanswerable.
-- schedule_slots already pairs teacher_name with teacher_initial across 220
-- distinct initials, so the mapping is read out of data already here rather
-- than retyped.
--
-- The backfill matched 0 of 4 teachers when applied, and that is correct: all
-- four teacher accounts in this project are test ones ("Masuk", an email used
-- as a name) and none appear in the real routine. set_teacher_initial() exists
-- for that case.
alter table public.teachers
  add column if not exists teacher_initial text;

update public.teachers t
   set teacher_initial = s.ti
  from public.profiles p,
       (select distinct on (lower(btrim(teacher_name)))
               lower(btrim(teacher_name)) as nm,
               teacher_initial            as ti
          from schedule_slots
         where coalesce(teacher_name, '') <> ''
           and coalesce(teacher_initial, '') <> ''
         order by lower(btrim(teacher_name))) s
 where p.id = t.profile_id
   and t.teacher_initial is null
   and lower(btrim(p.full_name)) = s.nm;

create index if not exists teachers_initial_idx on public.teachers (teacher_initial);

comment on column public.teachers.teacher_initial is
  'The short initial the exam seat plan identifies this teacher by (Tech. Int.).';
