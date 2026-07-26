-- =====================================================================
--  AFOS — Validate and normalise the identity fields the curriculum
--  system matches on.
--
--  WHY NORMALISATION MATTERS AS MUCH AS VALIDATION. Student visibility,
--  the notification audience RPC, the CR lookup and the offering unique
--  key all compare batch/section with plain `=`. A teacher typing section
--  "a" while the student record says "A" produces no error anywhere -- the
--  course just silently never appears for that section, and the batch
--  never gets notified. Constraints alone would not catch that; the values
--  are individually valid, they just don't match. So these are normalised
--  on write, at the database, rather than trusting every form to remember.
--
--  Validation is applied at the DB boundary rather than only in Dart
--  because PostgREST is directly reachable with any session token -- a
--  client-side rule is advisory.
--
--  All existing rows already satisfy these (checked before adding):
--  initials FNB/MSK, sections B/F, batches 65/66/68.
-- =====================================================================

-- ---------------------------------------------------------------
-- 1. Normalisation
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.normalise_student_identity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  NEW.section     := NULLIF(upper(btrim(NEW.section)), '');
  NEW.batch_label := NULLIF(btrim(NEW.batch_label), '');
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_normalise_student_identity ON students;
CREATE TRIGGER trg_normalise_student_identity
  BEFORE INSERT OR UPDATE OF section, batch_label ON students
  FOR EACH ROW EXECUTE FUNCTION public.normalise_student_identity();

CREATE OR REPLACE FUNCTION public.normalise_offering_identity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  NEW.section    := NULLIF(upper(btrim(NEW.section)), '');
  NEW.batch      := NULLIF(btrim(NEW.batch), '');
  NEW.department := NULLIF(upper(btrim(NEW.department)), '');
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_normalise_offering_identity ON course_offerings;
CREATE TRIGGER trg_normalise_offering_identity
  BEFORE INSERT OR UPDATE OF section, batch, department ON course_offerings
  FOR EACH ROW EXECUTE FUNCTION public.normalise_offering_identity();

-- Teacher initials are compared case-insensitively by the routine screen's
-- directory lookup and by the existing unique index on upper(teacher_initial);
-- storing them upper-cased makes the stored form match the compared form.
CREATE OR REPLACE FUNCTION public.normalise_profile_identity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  NEW.teacher_initial := NULLIF(upper(btrim(NEW.teacher_initial)), '');
  NEW.section         := NULLIF(upper(btrim(NEW.section)), '');
  NEW.batch           := NULLIF(btrim(NEW.batch), '');
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_normalise_profile_identity ON profiles;
CREATE TRIGGER trg_normalise_profile_identity
  BEFORE INSERT OR UPDATE OF teacher_initial, section, batch ON profiles
  FOR EACH ROW EXECUTE FUNCTION public.normalise_profile_identity();

-- Bring existing rows into the normalised form so old data and new data
-- compare equal.
UPDATE students SET section = upper(btrim(section)) WHERE section IS DISTINCT FROM upper(btrim(section));
UPDATE profiles SET teacher_initial = upper(btrim(teacher_initial))
 WHERE teacher_initial IS NOT NULL AND teacher_initial IS DISTINCT FROM upper(btrim(teacher_initial));
UPDATE profiles SET section = upper(btrim(section))
 WHERE section IS NOT NULL AND section IS DISTINCT FROM upper(btrim(section));


-- ---------------------------------------------------------------
-- 2. Validation
-- ---------------------------------------------------------------
-- teacher_initial had NO format rule at all: any string of any length was
-- accepted, and it is the join key the routine screen resolves teachers by.
ALTER TABLE profiles DROP CONSTRAINT IF EXISTS profiles_teacher_initial_format;
ALTER TABLE profiles ADD CONSTRAINT profiles_teacher_initial_format
  CHECK (teacher_initial IS NULL OR teacher_initial ~ '^[A-Z]{2,6}$');

ALTER TABLE students DROP CONSTRAINT IF EXISTS students_section_format;
ALTER TABLE students ADD CONSTRAINT students_section_format
  CHECK (section IS NULL OR section ~ '^[A-Z0-9]{1,4}$');

ALTER TABLE students DROP CONSTRAINT IF EXISTS students_batch_label_format;
ALTER TABLE students ADD CONSTRAINT students_batch_label_format
  CHECK (batch_label IS NULL OR batch_label ~ '^[A-Za-z0-9-]{1,10}$');

ALTER TABLE course_offerings DROP CONSTRAINT IF EXISTS course_offerings_section_format;
ALTER TABLE course_offerings ADD CONSTRAINT course_offerings_section_format
  CHECK (section IS NULL OR section ~ '^[A-Z0-9]{1,4}$');

ALTER TABLE course_offerings DROP CONSTRAINT IF EXISTS course_offerings_batch_format;
ALTER TABLE course_offerings ADD CONSTRAINT course_offerings_batch_format
  CHECK (batch IS NULL OR batch ~ '^[A-Za-z0-9-]{1,10}$');

-- Course codes are the de-facto join key between offerings and the routine
-- (schedule_slots.subject_code), so they get the same treatment.
ALTER TABLE courses DROP CONSTRAINT IF EXISTS courses_code_format;
ALTER TABLE courses ADD CONSTRAINT courses_code_format
  CHECK (code ~ '^[A-Za-z0-9 -]{2,20}$');

REVOKE ALL ON FUNCTION public.normalise_student_identity()  FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.normalise_offering_identity() FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.normalise_profile_identity()  FROM public, anon, authenticated;
