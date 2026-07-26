-- Nobody was told when a teacher submitted results for publication.
--
-- offering_result_submissions carried exactly one trigger, on_results_approved,
-- which fires when an admin APPROVES. The submission itself notified no one:
-- the teacher pressed "Submit for approval", the row went to status 'pending',
-- and it sat there until an admin happened to open the Results screen and look.
--
-- Every other stage of this workflow already announces itself -- an offering
-- submitted for review notifies the admins, an approval notifies the class, a
-- join request notifies the teacher -- so this was the one silent step, and it
-- is the step that gates a whole class getting their marks.
--
-- Mirrors notify_offering_submitted(): same recipient tiers, same
-- department-scoping for dept_admin so they only hear about their own
-- department, and same in-transaction guarantee so a backgrounded app cannot
-- lose it.
--
-- Verified live: submitting notifies the reviewer tiers and zero students, and
-- a later non-status UPDATE on an already-pending row does not re-announce.

CREATE OR REPLACE FUNCTION notify_results_submitted()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_code text;
  v_dept text;
  v_section text;
  v_batch text;
BEGIN
  -- Only the pending transition. Guarding on OLD.status as well means a
  -- teacher re-submitting after a rejection announces itself again, but an
  -- unrelated UPDATE on an already-pending row does not.
  IF NEW.status <> 'pending'
     OR (TG_OP = 'UPDATE' AND COALESCE(OLD.status, '') = 'pending') THEN
    RETURN NEW;
  END IF;

  SELECT c.code, co.department, co.section, co.batch
    INTO v_code, v_dept, v_section, v_batch
  FROM course_offerings co
  LEFT JOIN courses c ON c.id = co.course_id
  WHERE co.id = NEW.offering_id;

  INSERT INTO user_notifications (user_id, title, body, category, deep_link_route)
  SELECT p.id,
         'Results awaiting publication',
         COALESCE(v_code, 'A course') || ' (Section ' || COALESCE(v_section, '?') ||
           ', Batch ' || COALESCE(v_batch, '?') || ') has marks submitted and needs approval.',
         'result',
         '/grades'
    FROM profiles p
   WHERE p.role IN ('super_admin', 'admin', 'exam_controller')
      OR (p.role = 'dept_admin' AND p.department IS NOT NULL
          AND p.department = v_dept);

  RETURN NEW;
END;
$fn$;

REVOKE ALL ON FUNCTION notify_results_submitted() FROM public, anon, authenticated;

DROP TRIGGER IF EXISTS trg_notify_results_submitted ON offering_result_submissions;
CREATE TRIGGER trg_notify_results_submitted
  AFTER INSERT OR UPDATE OF status ON offering_result_submissions
  FOR EACH ROW EXECUTE FUNCTION notify_results_submitted();
