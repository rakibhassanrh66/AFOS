-- Why a student could get no notifications at all, and never appear on a roster.
--
-- Batch and section are stored TWICE: profiles.batch/section, which is what
-- every profile screen writes, and students.batch_label/section, which is what
-- list_offering_audience(), list_section_students(),
-- list_students_by_batch_section(), find_section_cr() and enforce_section_cap()
-- all READ. The mirroring between them was done by hand in two screens, so any
-- path that missed it left the two disagreeing silently and forever.
--
-- Live example that prompted this: Samia's profile said CSE / batch 68 /
-- section D, and her students row said CSE / batch 66 / section F. She was
-- therefore invisible to every roster and every audience for her own section --
-- no course-available notification, no place on the teacher's mark sheet --
-- while a classmate in the identical batch and section received everything.
--
-- profiles is the authoritative side: it is what complete_profile_screen and
-- settings_screen write first and what the user edits. students is the mirror.

CREATE OR REPLACE FUNCTION sync_student_batch_section()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_moved boolean;
BEGIN
  IF NEW.role <> 'student' THEN
    RETURN NEW;
  END IF;

  SELECT (s.batch_label IS DISTINCT FROM COALESCE(NEW.batch, s.batch_label)
       OR s.section     IS DISTINCT FROM COALESCE(NEW.section, s.section))
    INTO v_moved
    FROM students s WHERE s.profile_id = NEW.id;

  IF NOT COALESCE(v_moved, false) THEN
    RETURN NEW;
  END IF;

  -- A CR mandate belongs to a specific section, so moving section ends it --
  -- independently of the one_cr_per_section index, which would otherwise
  -- reject the move outright if the destination already had a CR. The student
  -- can stand again in their new section.
  UPDATE students s
     SET batch_label = COALESCE(NEW.batch, s.batch_label),
         section     = COALESCE(NEW.section, s.section),
         is_cr       = false,
         cr_since    = NULL
   WHERE s.profile_id = NEW.id;

  RETURN NEW;
END;
$fn$;

REVOKE ALL ON FUNCTION sync_student_batch_section() FROM public, anon, authenticated;

DROP TRIGGER IF EXISTS trg_sync_student_batch_section ON profiles;
CREATE TRIGGER trg_sync_student_batch_section
  AFTER INSERT OR UPDATE OF batch, section, role ON profiles
  FOR EACH ROW EXECUTE FUNCTION sync_student_batch_section();

-- One-time repair of rows that already diverged. Same CR rule as above, and
-- COALESCE so a profile with no batch set never blanks out a students row that
-- does have one -- this only corrects genuine disagreement, it does not erase.
--
-- On the live database this moved exactly one student (Samia, 66/F -> 68/D)
-- and cleared the CR flag she held for the section she had left; batch 68
-- section D already had a different CR.
UPDATE students s
   SET batch_label = COALESCE(p.batch, s.batch_label),
       section     = COALESCE(p.section, s.section),
       is_cr       = false,
       cr_since    = NULL
  FROM profiles p
 WHERE p.id = s.profile_id
   AND p.role = 'student'
   AND (s.batch_label IS DISTINCT FROM COALESCE(p.batch, s.batch_label)
     OR s.section     IS DISTINCT FROM COALESCE(p.section, s.section));

-- ------------------------------------------------ notify the class on approval
--
-- This was done client-side in approveOffering() and wrapped in a bare
-- `catch (_) {}`, so if the admin's app was backgrounded or the request
-- dropped, the entire batch was simply never told their course had opened --
-- silently, with no retry and nothing in the logs. The submitted-for-review
-- and results-approved notifications already run as triggers for exactly this
-- reason; this brings approval in line with them.

CREATE OR REPLACE FUNCTION notify_offering_approved()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_code text;
BEGIN
  IF NEW.status <> 'approved' OR COALESCE(OLD.status, '') = 'approved' THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(c.code, 'A course') INTO v_code
    FROM courses c WHERE c.id = NEW.course_id;

  INSERT INTO user_notifications (user_id, title, body, category, deep_link_route)
  SELECT p.id,
         'New course available',
         v_code || ' (Section ' || COALESCE(NEW.section, '?') ||
           ') is open to join for Batch ' || COALESCE(NEW.batch, '?') || '.',
         'course_offering',
         '/schedule/browse-courses'
    FROM students s
    JOIN profiles p ON p.id = s.profile_id
    LEFT JOIN departments d ON d.id = s.department_id
   WHERE COALESCE(d.code, p.department) = NEW.department
     -- COALESCE against profiles as a second line of defence: the mirror
     -- trigger above keeps these equal, but a student with no students-row
     -- value should still be reachable rather than silently dropped.
     AND COALESCE(s.batch_label, p.batch)   = NEW.batch
     AND COALESCE(s.section,     p.section) = NEW.section;

  RETURN NEW;
END;
$fn$;

REVOKE ALL ON FUNCTION notify_offering_approved() FROM public, anon, authenticated;

DROP TRIGGER IF EXISTS trg_notify_offering_approved ON course_offerings;
CREATE TRIGGER trg_notify_offering_approved
  AFTER UPDATE OF status ON course_offerings
  FOR EACH ROW EXECUTE FUNCTION notify_offering_approved();
