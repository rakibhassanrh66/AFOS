-- FOUR DECISIONS MADE ABOUT A STUDENT THAT WERE NEVER TOLD TO THEM.
--
-- club_membership_requests, cr_requests, hall_applications and
-- mentorship_bookings each carry a status that an administrator, a club
-- president or a faculty member moves off 'pending' to a verdict. None of the
-- four had a trigger of ANY kind on it, so the only way a student could learn
-- the answer was to reopen the screen and check by hand. Every other decision
-- surface in the app already notifies -- enrolments, course offerings, result
-- submissions, teaching assignments -- so this is an omission, not a policy.
--
-- All four are modelled on notify_enrollment_reviewed: SECURITY DEFINER with a
-- pinned search_path (so they do not add to the function_search_path_mutable
-- advisor), fire only when the status genuinely CHANGED and landed on a
-- verdict, and insert exactly one row addressed to the single student the
-- decision concerns. Status values are taken from each table's own CHECK
-- constraint rather than from what happens to be in the table today.

-- ── Club membership ────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_club_membership_reviewed()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_club text;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status
     OR NEW.status NOT IN ('approved', 'rejected') THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(c.name, 'the club') INTO v_club FROM clubs c WHERE c.id = NEW.club_id;

  INSERT INTO user_notifications (user_id, title, body, category, deep_link_route)
  VALUES (NEW.student_id,
          CASE WHEN NEW.status = 'approved'
               THEN 'Club membership approved' ELSE 'Club membership declined' END,
          CASE WHEN NEW.status = 'approved'
               THEN 'You are now a member of ' || COALESCE(v_club, 'the club') ||
                    '. Its group chat and events are open to you.'
               ELSE 'Your request to join ' || COALESCE(v_club, 'the club') ||
                    ' was declined' ||
                    COALESCE('. Reason: ' || NULLIF(btrim(NEW.rejection_reason), ''), '.') END,
          'club', '/clubs');
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_notify_club_membership_reviewed ON public.club_membership_requests;
CREATE TRIGGER trg_notify_club_membership_reviewed
  AFTER UPDATE OF status ON public.club_membership_requests
  FOR EACH ROW EXECUTE FUNCTION public.notify_club_membership_reviewed();

-- ── Class representative ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_cr_request_reviewed()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status
     OR NEW.status NOT IN ('approved', 'rejected') THEN
    RETURN NEW;
  END IF;

  INSERT INTO user_notifications (user_id, title, body, category, deep_link_route)
  VALUES (NEW.student_id,
          CASE WHEN NEW.status = 'approved'
               THEN 'You are now the class representative'
               ELSE 'Class representative request declined' END,
          CASE WHEN NEW.status = 'approved'
               THEN 'You represent batch ' || NEW.batch_label || ', section ' ||
                    NEW.section || '. The tools for it are on your profile.'
               ELSE 'Your request to represent batch ' || NEW.batch_label ||
                    ', section ' || NEW.section || ' was declined' ||
                    COALESCE('. Reason: ' || NULLIF(btrim(NEW.rejection_reason), ''), '.') END,
          'cr', '/profile');
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_notify_cr_request_reviewed ON public.cr_requests;
CREATE TRIGGER trg_notify_cr_request_reviewed
  AFTER UPDATE OF status ON public.cr_requests
  FOR EACH ROW EXECUTE FUNCTION public.notify_cr_request_reviewed();

-- ── Hall seat ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_hall_application_reviewed()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_where text;
BEGIN
  -- student_id is nullable on this table; a row without one has nobody to tell.
  IF NEW.student_id IS NULL
     OR NEW.status IS NOT DISTINCT FROM OLD.status
     OR NEW.status NOT IN ('approved', 'rejected') THEN
    RETURN NEW;
  END IF;

  v_where := NULLIF(btrim(CONCAT_WS(', ',
               NULLIF(btrim(COALESCE(NEW.assigned_building, '')), ''),
               NULLIF(btrim(COALESCE(NEW.assigned_room, '')), ''))), '');

  INSERT INTO user_notifications (user_id, title, body, category, deep_link_route)
  VALUES (NEW.student_id,
          CASE WHEN NEW.status = 'approved'
               THEN 'Hall application approved' ELSE 'Hall application declined' END,
          CASE WHEN NEW.status = 'approved'
               THEN COALESCE('You have been allocated ' || v_where || '.',
                             'Your hall seat has been approved.')
               ELSE 'Your hall application was declined' ||
                    COALESCE('. Reason: ' || NULLIF(btrim(NEW.rejection_reason), ''), '.') END,
          'hall', '/hall');
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_notify_hall_application_reviewed ON public.hall_applications;
CREATE TRIGGER trg_notify_hall_application_reviewed
  AFTER UPDATE OF status ON public.hall_applications
  FOR EACH ROW EXECUTE FUNCTION public.notify_hall_application_reviewed();

-- ── Mentorship session ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_mentorship_booking_reviewed()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_mentor text; v_when text;
BEGIN
  -- 'completed' is not a decision, it is a record of something that already
  -- happened; the student was there. Only the verdict transitions notify.
  IF NEW.student_id IS NULL
     OR NEW.status IS NOT DISTINCT FROM OLD.status
     OR NEW.status NOT IN ('confirmed', 'rejected') THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(NULLIF(btrim(p.full_name), ''), 'your mentor') INTO v_mentor
    FROM profiles p WHERE p.id = NEW.mentor_id;

  v_when := to_char(NEW.scheduled_at AT TIME ZONE 'Asia/Dhaka', 'FMDay FMDD FMMon, FMHH12:MI am');

  INSERT INTO user_notifications (user_id, title, body, category, deep_link_route)
  VALUES (NEW.student_id,
          CASE WHEN NEW.status = 'confirmed'
               THEN 'Mentorship session confirmed' ELSE 'Mentorship session declined' END,
          CASE WHEN NEW.status = 'confirmed'
               THEN COALESCE(v_mentor, 'Your mentor') || ' confirmed your session' ||
                    COALESCE(' on ' || v_when, '') || '.' ||
                    COALESCE(' Where: ' || NULLIF(btrim(NEW.location_or_link), ''), '')
               ELSE COALESCE(v_mentor, 'Your mentor') || ' could not take the session' ||
                    COALESCE(' on ' || v_when, '') || '.' END,
          'mentorship', '/mentorship');
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_notify_mentorship_booking_reviewed ON public.mentorship_bookings;
CREATE TRIGGER trg_notify_mentorship_booking_reviewed
  AFTER UPDATE OF status ON public.mentorship_bookings
  FOR EACH ROW EXECUTE FUNCTION public.notify_mentorship_booking_reviewed();
