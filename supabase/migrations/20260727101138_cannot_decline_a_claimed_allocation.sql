-- You cannot decline an allocation you have already built a course from.
--
-- The converse of 20260726225438, and the hole it left. That migration stopped
-- an offering being attached to an allocation nobody accepted. It did not stop
-- the other order of events: an allocation that ALREADY carries an offering_id
-- being flipped to 'declined'. The module leader would then be told
-- "DECLINED — reassign", and the uniqueness index (partial on
-- status <> 'declined') would happily let them give the class to somebody else,
-- while the original teacher's offering is still live on the routine, still has
-- students enrolled in it, and still generates their attendance and marks.
--
-- This became reachable rather than theoretical once the Teaching Load screen
-- started rendering the real status: the one live allocation on this project
-- sits at status='pending' WITH an offering_id (historical, from before
-- accept/decline existed), so its card legitimately offers Accept and Decline.
-- Accept is the correct resolution and closes the leader's queue. Decline would
-- have quietly created the contradiction above.
--
-- Checked BEFORE the module-leader/admin early return, deliberately, and for
-- the same reason as the sibling guard: this is data integrity, not permission.
-- An admin doing it by hand produces exactly the same broken state.
--
-- Archiving the offering first is the supported way out, which is why the
-- message says so — that path already drops the routine rows and the students'
-- pins.

CREATE OR REPLACE FUNCTION assert_teaching_assignment_edit()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $fn$
BEGIN
  IF NEW.offering_id IS NOT NULL
     AND NEW.offering_id IS DISTINCT FROM OLD.offering_id
     AND NEW.status <> 'accepted' THEN
    RAISE EXCEPTION
      'Accept this allocation before creating its course offering (status is %)',
      NEW.status
      USING errcode = '23514';
  END IF;

  IF NEW.status = 'declined'
     AND OLD.status IS DISTINCT FROM 'declined'
     AND NEW.offering_id IS NOT NULL THEN
    RAISE EXCEPTION
      'This allocation already has a course offering. Archive the offering first if the class is not going ahead.'
      USING errcode = '23514';
  END IF;

  IF is_module_leader(NEW.department)
     OR get_my_profile_role() IN ('admin', 'dept_admin', 'super_admin')
     OR caller_can('course_offerings', 'manage') THEN
    RETURN NEW;
  END IF;

  IF NEW.teacher_id      IS DISTINCT FROM OLD.teacher_id
     OR NEW.department   IS DISTINCT FROM OLD.department
     OR NEW.course_code  IS DISTINCT FROM OLD.course_code
     OR NEW.course_type  IS DISTINCT FROM OLD.course_type
     OR NEW.batch        IS DISTINCT FROM OLD.batch
     OR NEW.section      IS DISTINCT FROM OLD.section
     OR NEW.semester     IS DISTINCT FROM OLD.semester
     OR NEW.assigned_by  IS DISTINCT FROM OLD.assigned_by THEN
    RAISE EXCEPTION 'You may only accept or decline an allocation, not change it'
      USING errcode = '42501';
  END IF;

  IF NEW.status = 'declined' AND COALESCE(btrim(NEW.decline_reason), '') = '' THEN
    RAISE EXCEPTION 'A reason is required when declining an allocation'
      USING errcode = '23514';
  END IF;

  RETURN NEW;
END;
$fn$;

REVOKE ALL ON FUNCTION assert_teaching_assignment_edit() FROM public, anon, authenticated;
