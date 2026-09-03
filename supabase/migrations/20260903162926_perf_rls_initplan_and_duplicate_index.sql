-- Three RLS policies on assignment_submissions and one on mail_capacity_alerts
-- called auth.uid() bare, so Postgres re-evaluated it FOR EVERY ROW instead of
-- once per query. Every other policy in this database already uses the
-- (select auth.uid()) form; these four were the last holdouts.
--
-- assignment_submissions is the table that makes this matter: it is empty
-- today and grows by one row per student per assignment, so the cost arrives
-- with real usage rather than being visible now. Semantics are identical --
-- the subselect is a stable InitPlan, evaluated once. Verified with EXPLAIN as
-- `authenticated`: the filter now reads `student_id = (InitPlan 23).col1`.

drop policy if exists student_read_own_submission on public.assignment_submissions;
create policy student_read_own_submission on public.assignment_submissions
  for select
  using (student_id = (select auth.uid()));

drop policy if exists student_update_own_submission_before_deadline on public.assignment_submissions;
create policy student_update_own_submission_before_deadline on public.assignment_submissions
  for update
  using (
    student_id = (select auth.uid())
    and exists (select 1 from public.assignments a
                 where a.id = assignment_submissions.assignment_id
                   and a.deadline > now())
  )
  with check (
    student_id = (select auth.uid())
    and marks is null
    and graded_by is null
  );

drop policy if exists teacher_grade_submissions on public.assignment_submissions;
create policy teacher_grade_submissions on public.assignment_submissions
  for update
  using (exists (select 1 from public.assignments a
                  where a.id = assignment_submissions.assignment_id
                    and a.teacher_id = (select auth.uid())))
  with check (exists (select 1 from public.assignments a
                       where a.id = assignment_submissions.assignment_id
                         and a.teacher_id = (select auth.uid())));

drop policy if exists mail_capacity_alerts_admin_read on public.mail_capacity_alerts;
create policy mail_capacity_alerts_admin_read on public.mail_capacity_alerts
  for select to authenticated
  using (exists (select 1 from public.profiles p
                  where p.id = (select auth.uid()) and p.role = 'super_admin'));

-- Two identical indexes on profiles(department_id). profiles_department_id_idx
-- is the one a migration creates (20260816190500); idx_profiles_department_id
-- was made ad hoc and appears in no migration, so dropping it is what keeps a
-- rebuilt database matching this one. Every profile write was maintaining both.
drop index if exists public.idx_profiles_department_id;

-- course_offerings.course_id had no usable index: the only index containing it
-- is UNIQUE (semester_id, course_id, batch, section), where course_id is not
-- the leading column, so a join or FK check on course_id alone cannot use it.
-- This is the hot one of the thirteen unindexed foreign keys the advisor
-- reports -- every course listing joins courses to their offerings. The other
-- twelve are admin-side columns (uploaded_by, reviewed_by, triaged_by) whose
-- tables are small and whose queries are rare; an index each would cost more
-- on write than it returns on read, so they are deliberately left alone.
create index if not exists course_offerings_course_id_idx
  on public.course_offerings (course_id);
