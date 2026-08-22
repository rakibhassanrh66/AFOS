-- The owner asked to group students by Fall/Summer/Spring + year, and to ask
-- every teacher and student for the join date printed on their ID card.
-- Measured first: no admission-term column existed anywhere, the student IDs
-- in the table are inconsistent test data (221-15-9999 beside
-- 0242220005101554 beside 0643234699485) so no term code can be parsed from
-- them, `batches` holds 3 rows and is not linked to profiles.batch, and
-- teachers.joining_date / staff.joining_date are NULL for all 6 people.
alter table profiles
  add column if not exists admission_season text,
  add column if not exists admission_year int,
  -- "the join date based on their ID card time mentioned" -- for a student the
  -- date printed on the card, for a teacher or officer the date they joined.
  -- ONE concept, ONE column. teachers.joining_date and staff.joining_date
  -- already exist and stay as mirrors, because this project has been burned by
  -- exactly this shape before: set_teacher_initial() wrote
  -- teachers.teacher_initial while the routine directory read
  -- profiles.teacher_initial, and two teachers silently had no duties.
  add column if not exists joined_on date;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'profiles_admission_season_ck') then
    alter table profiles add constraint profiles_admission_season_ck
      check (admission_season is null or admission_season in ('spring','summer','fall'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'profiles_admission_year_ck') then
    alter table profiles add constraint profiles_admission_year_ck
      check (admission_year is null or (admission_year between 2000 and 2100));
  end if;
end $$;

comment on column profiles.joined_on is
  'Date printed on the ID card (student) or date of joining (teacher/staff). '
  'SOURCE OF TRUTH. teachers.joining_date and staff.joining_date are mirrors '
  'kept in sync by trg_profile_completeness -- never write them directly.';
