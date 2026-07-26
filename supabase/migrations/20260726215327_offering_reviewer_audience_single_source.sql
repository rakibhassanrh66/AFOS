-- Makes the reviewer audience identical BY CONSTRUCTION, not by coincidence.
--
-- Two stages notify "the people who review this": an offering submitted for
-- approval, and results submitted for publication. Each wrote its recipient
-- rule twice -- once in the trigger (in-app row) and once in the client (push
-- banner) -- and the two had already drifted:
--
--   * offering submitted: the trigger scopes dept_admin to the offering's own
--     department; the client pushed to EVERY dept_admin regardless.
--   * results submitted: the trigger includes a scoped dept_admin; the client
--     omitted dept_admin entirely, so they would get the in-app row and never
--     a banner.
--
-- Neither shows up on this project today because it has zero dept_admins, so a
-- test counting recipients passes while the logic is wrong. That is precisely
-- the failure mode this sweep exists to catch: two systems describing one fact,
-- each verified alone, never compared to each other.
--
-- One definition now, called by both sides -- the same fix already applied to
-- offering_section_audience().
--
-- Verified by temporarily making a spare profile a dept_admin (restored
-- afterwards): the function's output equals the trigger's own predicate, the
-- offering department's dept_admin IS included, and a dept_admin from another
-- department is NOT.

CREATE OR REPLACE FUNCTION offering_reviewer_audience(
  p_offering_id uuid,
  p_include_exam_controller boolean DEFAULT false
)
RETURNS TABLE(profile_id uuid)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
  SELECT p.id
  FROM course_offerings co
  JOIN profiles p ON (
        p.role IN ('super_admin', 'admin')
     OR (p_include_exam_controller AND p.role = 'exam_controller')
     OR (p.role = 'dept_admin' AND p.department IS NOT NULL
         AND p.department = co.department)
  )
  WHERE co.id = p_offering_id;
$fn$;

REVOKE ALL ON FUNCTION offering_reviewer_audience(uuid, boolean) FROM public, anon;
GRANT EXECUTE ON FUNCTION offering_reviewer_audience(uuid, boolean) TO authenticated;

CREATE OR REPLACE FUNCTION notify_offering_submitted()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE v_label text;
BEGIN
  IF NEW.status IS DISTINCT FROM 'pending' THEN RETURN NEW; END IF;

  SELECT COALESCE(c.code, 'A course') INTO v_label
    FROM courses c WHERE c.id = NEW.course_id;

  INSERT INTO user_notifications (user_id, title, body, category, deep_link_route)
  SELECT a.profile_id,
         'Course offering awaiting review',
         COALESCE(v_label, 'A course') || ' (Section ' || COALESCE(NEW.section, '?') ||
           ', Batch ' || COALESCE(NEW.batch, '?') || ') was submitted and needs approval.',
         'course_offering',
         '/admin/course-offerings'
    FROM offering_reviewer_audience(NEW.id, false) a;

  RETURN NEW;
END;
$fn$;

REVOKE ALL ON FUNCTION notify_offering_submitted() FROM public, anon, authenticated;

CREATE OR REPLACE FUNCTION notify_results_submitted()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE v_code text; v_section text; v_batch text;
BEGIN
  IF NEW.status <> 'pending'
     OR (TG_OP = 'UPDATE' AND COALESCE(OLD.status, '') = 'pending') THEN
    RETURN NEW;
  END IF;

  SELECT c.code, co.section, co.batch INTO v_code, v_section, v_batch
  FROM course_offerings co
  LEFT JOIN courses c ON c.id = co.course_id
  WHERE co.id = NEW.offering_id;

  INSERT INTO user_notifications (user_id, title, body, category, deep_link_route)
  SELECT a.profile_id,
         'Results awaiting publication',
         COALESCE(v_code, 'A course') || ' (Section ' || COALESCE(v_section, '?') ||
           ', Batch ' || COALESCE(v_batch, '?') || ') has marks submitted and needs approval.',
         'result',
         '/grades'
    FROM offering_reviewer_audience(NEW.offering_id, true) a;

  RETURN NEW;
END;
$fn$;

REVOKE ALL ON FUNCTION notify_results_submitted() FROM public, anon, authenticated;
