-- =====================================================================
--  AFOS — Close three silent gaps in the course-offering lifecycle.
--
--  Symptoms reported: a teacher submits an offering and no admin ever
--  learns it is waiting (one sat ~6h); a student taps "Request to Join",
--  the card flips to REQUEST PENDING, and the teacher is never told, so
--  it is never approved and the student never reaches the course group.
--  The group RLS was fine all along — `can_access_course_group` admits an
--  approved enrolment correctly. Nothing was ever approved, because
--  nobody was ever told there was anything to approve.
--
--  These live in triggers rather than in the Dart repository on purpose.
--  The three writes they react to (`createOffering`, `requestJoin`,
--  `approveJoin`) are plain PostgREST calls; a client-side notification
--  after one of them is a second, independent request that is simply lost
--  if the app is backgrounded, the network drops, or the process is
--  killed — and the loss is silent. In a trigger the notification commits
--  in the same transaction as the row that justifies it, so the two can
--  never disagree.
--
--  In-app only (`user_notifications`). OneSignal push still goes through
--  the send-notification edge function; Postgres has no business making
--  outbound HTTP calls inside a transaction.
-- =====================================================================

-- Who reviews a pending offering. super_admin/admin see everything;
-- dept_admin is scoped to their own department, so an EEE dept_admin is
-- not paged about a CSE course.
CREATE OR REPLACE FUNCTION public.notify_offering_submitted()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_label text;
BEGIN
  IF NEW.status IS DISTINCT FROM 'pending' THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(c.code, 'A course') INTO v_label
    FROM courses c WHERE c.id = NEW.course_id;

  INSERT INTO user_notifications (user_id, title, body, category, deep_link_route)
  SELECT p.id,
         'Course offering awaiting review',
         COALESCE(v_label, 'A course') || ' (Section ' || COALESCE(NEW.section, '?') ||
           ', Batch ' || COALESCE(NEW.batch, '?') || ') was submitted and needs approval.',
         'course_offering',
         '/admin/course-offerings'
    FROM profiles p
   WHERE p.role IN ('super_admin', 'admin')
      OR (p.role = 'dept_admin' AND p.department IS NOT NULL
          AND p.department = NEW.department);

  RETURN NEW;
END;
$$;

-- A student asked to join. Only the offering's own teacher is told.
CREATE OR REPLACE FUNCTION public.notify_enrollment_requested()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_teacher_id uuid;
  v_label      text;
  v_student    text;
BEGIN
  IF NEW.status IS DISTINCT FROM 'pending' THEN
    RETURN NEW;
  END IF;

  SELECT co.teacher_id, COALESCE(c.code, 'your course')
    INTO v_teacher_id, v_label
    FROM course_offerings co
    LEFT JOIN courses c ON c.id = co.course_id
   WHERE co.id = NEW.offering_id;

  -- A teacher enrolling in their own offering would otherwise notify
  -- themselves; harmless but noise.
  IF v_teacher_id IS NULL OR v_teacher_id = NEW.student_id THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(p.full_name, 'A student') INTO v_student
    FROM profiles p WHERE p.id = NEW.student_id;

  INSERT INTO user_notifications (user_id, title, body, category, deep_link_route)
  VALUES (v_teacher_id,
          'New join request',
          COALESCE(v_student, 'A student') || ' asked to join ' || COALESCE(v_label, 'your course') || '.',
          'course_offering',
          '/schedule/my-offerings');

  RETURN NEW;
END;
$$;

-- The request was decided. Tell the student either way: a silent refusal
-- is indistinguishable from being ignored, which is exactly what this
-- whole flow felt like.
CREATE OR REPLACE FUNCTION public.notify_enrollment_reviewed()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_label text;
BEGIN
  -- Only on a real transition into a terminal state. Without the status
  -- comparison this would fire on every unrelated UPDATE of the row.
  IF NEW.status IS NOT DISTINCT FROM OLD.status
     OR NEW.status NOT IN ('approved', 'rejected') THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(c.code, 'the course') INTO v_label
    FROM course_offerings co
    LEFT JOIN courses c ON c.id = co.course_id
   WHERE co.id = NEW.offering_id;

  INSERT INTO user_notifications (user_id, title, body, category, deep_link_route)
  VALUES (NEW.student_id,
          CASE WHEN NEW.status = 'approved'
               THEN 'Join request approved'
               ELSE 'Join request declined' END,
          CASE WHEN NEW.status = 'approved'
               THEN 'You are enrolled in ' || COALESCE(v_label, 'the course') ||
                    '. Its classes are on your routine and the course group is now open.'
               ELSE 'Your request to join ' || COALESCE(v_label, 'the course') ||
                    ' was declined.' END,
          'course_offering',
          '/schedule/browse-courses');

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_offering_submitted   ON course_offerings;
DROP TRIGGER IF EXISTS trg_notify_enrollment_requested ON enrollments;
DROP TRIGGER IF EXISTS trg_notify_enrollment_reviewed  ON enrollments;

CREATE TRIGGER trg_notify_offering_submitted
  AFTER INSERT ON course_offerings
  FOR EACH ROW EXECUTE FUNCTION notify_offering_submitted();

CREATE TRIGGER trg_notify_enrollment_requested
  AFTER INSERT ON enrollments
  FOR EACH ROW EXECUTE FUNCTION notify_enrollment_requested();

CREATE TRIGGER trg_notify_enrollment_reviewed
  AFTER UPDATE OF status ON enrollments
  FOR EACH ROW EXECUTE FUNCTION notify_enrollment_reviewed();

-- CREATE FUNCTION grants EXECUTE to PUBLIC by default, and these are
-- SECURITY DEFINER. They are only ever reached through the triggers above,
-- so nothing needs to call them directly — and .github/scripts/
-- check_definer_acls.py fails the build on any definer function left
-- reachable by anon.
REVOKE EXECUTE ON FUNCTION public.notify_offering_submitted()   FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.notify_enrollment_requested() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.notify_enrollment_reviewed()  FROM PUBLIC, anon, authenticated;
