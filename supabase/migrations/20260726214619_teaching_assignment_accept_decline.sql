-- A teacher can now accept or decline an allocation, with a reason.
--
-- Until now a module leader allocated a class and that was the end of the
-- conversation: the teacher was notified and had no way to say "I already have
-- four sections" or "that clashes". The leader had no signal either -- an
-- allocation nobody had acted on looked identical to one quietly refused.
--
-- DEFAULT TAKEN, since the question went unanswered three times: declining
-- FREES THE CLASS IMMEDIATELY. The declined row stays as the audit trail (who
-- refused, when, why) and the uniqueness index becomes PARTIAL so it ignores
-- declined rows -- which is the only reason reassignment can work at all. With
-- the old plain index a declined row still occupied the slot and the module
-- leader physically could not give that class to anybody else.
--
-- The alternative (leader must withdraw first) keeps one row per class but adds
-- a step before every reassignment. Changing to it is a one-line predicate on
-- the index plus dropping the reassign path.

ALTER TABLE teaching_assignments
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'accepted', 'declined')),
  ADD COLUMN IF NOT EXISTS decline_reason text
    CHECK (decline_reason IS NULL OR length(decline_reason) <= 500),
  ADD COLUMN IF NOT EXISTS responded_at timestamptz;

CREATE INDEX IF NOT EXISTS teaching_assignments_status_idx
  ON teaching_assignments (department, semester, status);

DROP INDEX IF EXISTS teaching_assignments_unique_class;
CREATE UNIQUE INDEX teaching_assignments_unique_class
  ON teaching_assignments (department, course_code, course_type, batch, section, semester)
  WHERE status <> 'declined';

COMMENT ON INDEX teaching_assignments_unique_class IS
  'One LIVE teacher per class per semester. Partial on status <> declined so a refused allocation keeps its audit row without blocking reassignment. course_type is in the key because a theory class and its lab are different classes.';

-- RLS cannot restrict columns, and teacher_claim_own_assignment allows UPDATE
-- on the teacher's own row. Without this a teacher could rewrite the course
-- code, batch or section they were allocated -- silently reassigning
-- themselves to a class the module leader never gave them.
CREATE OR REPLACE FUNCTION assert_teaching_assignment_edit()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $fn$
BEGIN
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

  -- A refusal without a reason is useless to the person who has to reassign it.
  IF NEW.status = 'declined' AND COALESCE(btrim(NEW.decline_reason), '') = '' THEN
    RAISE EXCEPTION 'A reason is required when declining an allocation'
      USING errcode = '23514';
  END IF;

  RETURN NEW;
END;
$fn$;

REVOKE ALL ON FUNCTION assert_teaching_assignment_edit() FROM public, anon, authenticated;

DROP TRIGGER IF EXISTS trg_assert_teaching_assignment_edit ON teaching_assignments;
CREATE TRIGGER trg_assert_teaching_assignment_edit
  BEFORE UPDATE ON teaching_assignments
  FOR EACH ROW EXECUTE FUNCTION assert_teaching_assignment_edit();

CREATE OR REPLACE FUNCTION notify_teaching_response()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE v_teacher text;
BEGIN
  IF NEW.status = OLD.status OR NEW.status = 'pending' THEN
    RETURN NEW;
  END IF;

  SELECT full_name INTO v_teacher FROM profiles WHERE id = NEW.teacher_id;

  INSERT INTO user_notifications (user_id, title, body, category, deep_link_route)
  SELECT p.id,
         CASE WHEN NEW.status = 'accepted'
              THEN 'Teaching allocation accepted'
              ELSE 'Teaching allocation declined' END,
         COALESCE(v_teacher, 'A teacher') || ' ' || NEW.status || ' ' ||
           NEW.course_code || ' (Batch ' || NEW.batch || ', Section ' || NEW.section || ')' ||
           CASE WHEN NEW.status = 'declined'
                THEN ' — ' || COALESCE(NEW.decline_reason, 'no reason given') ||
                     '. The class is free to reassign.'
                ELSE '.' END,
         'course_offering',
         '/schedule/teaching-load'
    FROM profiles p
   WHERE p.id = NEW.assigned_by
      OR EXISTS (SELECT 1 FROM module_leaders ml
                  WHERE ml.teacher_id = p.id AND ml.department = NEW.department);

  RETURN NEW;
END;
$fn$;

REVOKE ALL ON FUNCTION notify_teaching_response() FROM public, anon, authenticated;

DROP TRIGGER IF EXISTS trg_notify_teaching_response ON teaching_assignments;
CREATE TRIGGER trg_notify_teaching_response
  AFTER UPDATE OF status ON teaching_assignments
  FOR EACH ROW EXECUTE FUNCTION notify_teaching_response();
