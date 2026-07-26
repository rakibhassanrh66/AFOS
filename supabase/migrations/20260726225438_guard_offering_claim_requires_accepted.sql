-- An offering may only be created from an allocation the teacher ACCEPTED.
--
-- Found in live data: one teaching_assignment sits at status='pending' with an
-- offering_id already stamped on it -- a teacher turned an allocation into a
-- course without ever answering it, so the module leader is still looking at
-- "AWAITING TEACHER" for a class that is already running.
--
-- That row is historical (claimed 21:10, before the accept/decline build even
-- existed), and the current app filters the New Course Offering form to
-- accepted-and-unclaimed allocations. But that filter is CLIENT-SIDE ONLY.
-- Nothing in the database enforced it, so an older build -- or any direct API
-- call -- can still produce the same inconsistency. The UI filter is a
-- convenience; this is the rule.
--
-- Deliberately checked BEFORE the module-leader/admin early return: this is a
-- data-integrity rule, not a permission one. Nobody, at any privilege level,
-- should be able to attach an offering to an allocation that was never
-- accepted -- an admin doing it by hand produces exactly the same misleading
-- state.
--
-- Only fires when offering_id is actually being SET, so accepting, declining
-- and ordinary edits are unaffected, and the existing historical row is left
-- alone (a BEFORE UPDATE trigger cannot rewrite the past).
--
-- Verified live as the allocating admin: claiming while pending fails,
-- claiming while declined fails, claiming once accepted succeeds, and
-- accept/decline themselves still work.

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
