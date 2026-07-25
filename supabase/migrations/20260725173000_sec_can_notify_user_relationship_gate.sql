-- =====================================================================
--  AFOS — Relationship gate for send-notification's direct (userIds) mode.
--
--  THE HOLE. send-notification accepted `userIds` from ANY authenticated
--  caller and wrote an arbitrary title/body/deepLink into those users'
--  notification centres, plus a real push. A student could send 20 people
--  "Your account has been suspended - tap to reactivate" pointing at any
--  in-app route. Nothing verified the sender had any connection to the
--  recipients.
--
--  WHY A RELATIONSHIP GATE RATHER THAN A ROLE GATE. Direct sends are
--  genuinely used peer-to-peer: a student asks to join a club and the
--  president is told, a mentee books and the mentor is told, a lost-item
--  claimant and the poster talk to each other. Requiring an elevated role
--  would break all of those. What they have in common is that the two
--  users share a *record* the database can verify, so that is what this
--  checks.
--
--  Every one of the app's non-elevated direct-send call sites creates its
--  row (booking / claim / membership request / enrolment) BEFORE notifying,
--  so the relationship already exists at notify time.
--
--  Callable only by service_role: the Edge Function passes the caller id it
--  resolved from the JWT itself, so this must never be reachable by a
--  client that could pass someone else's id as p_caller.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.can_notify_user(p_caller uuid, p_target uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT p_caller IS NOT NULL AND p_target IS NOT NULL AND p_caller <> p_target AND (

    -- Mentorship, either direction.
    EXISTS (SELECT 1 FROM mentorship_bookings b
             WHERE (b.student_id = p_caller AND b.mentor_id  = p_target)
                OR (b.mentor_id  = p_caller AND b.student_id = p_target))

    -- Same club: president <-> member, or president <-> someone with a
    -- pending membership/post request for that club (the applicant is not a
    -- member yet at the moment the president is notified).
    OR EXISTS (
      SELECT 1 FROM clubs c
       WHERE (c.president_id = p_target AND (
                EXISTS (SELECT 1 FROM club_members m            WHERE m.club_id = c.id AND m.member_id  = p_caller)
             OR EXISTS (SELECT 1 FROM club_membership_requests r WHERE r.club_id = c.id AND r.student_id = p_caller)
             OR EXISTS (SELECT 1 FROM club_post_requests r       WHERE r.club_id = c.id AND r.member_id  = p_caller)))
          OR (c.president_id = p_caller AND (
                EXISTS (SELECT 1 FROM club_members m            WHERE m.club_id = c.id AND m.member_id  = p_target)
             OR EXISTS (SELECT 1 FROM club_membership_requests r WHERE r.club_id = c.id AND r.student_id = p_target)
             OR EXISTS (SELECT 1 FROM club_post_requests r       WHERE r.club_id = c.id AND r.member_id  = p_target))))

    -- Lost & found: poster <-> claimant on the same post.
    OR EXISTS (SELECT 1 FROM lost_found_posts p
                 JOIN lost_found_claims cl ON cl.post_id = p.id
                WHERE (p.poster_id    = p_caller AND cl.claimant_id = p_target)
                   OR (cl.claimant_id = p_caller AND p.poster_id    = p_target))

    -- SOS: an alert is broadcast to many people, any of whom may respond to
    -- its owner. Scoped to a currently-active alert so this does not become
    -- a permanent licence to message anyone who ever raised one.
    OR EXISTS (SELECT 1 FROM sos_alerts s WHERE s.user_id = p_target AND s.status = 'active')

    -- A student messaging their own section's Class Representative.
    -- batch/section/department must all be present AND equal: without the
    -- NOT NULL guards two students with no section set would match on
    -- NULL = NULL semantics and every CR would be reachable by anyone.
    OR EXISTS (SELECT 1 FROM students me
                 JOIN students cr
                   ON cr.batch_label   = me.batch_label
                  AND cr.section       = me.section
                  AND cr.department_id = me.department_id
                WHERE me.profile_id = p_caller
                  AND cr.profile_id = p_target
                  AND cr.is_cr
                  AND me.batch_label IS NOT NULL
                  AND me.section     IS NOT NULL
                  AND me.department_id IS NOT NULL)

    -- Course: an enrolled (or applying) student <-> that offering's teacher.
    OR EXISTS (SELECT 1 FROM enrollments e
                 JOIN course_offerings o ON o.id = e.offering_id
                WHERE (e.student_id = p_caller AND o.teacher_id = p_target)
                   OR (o.teacher_id = p_caller AND e.student_id = p_target))
  );
$$;

REVOKE ALL ON FUNCTION public.can_notify_user(uuid, uuid) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.can_notify_user(uuid, uuid) TO service_role;

NOTIFY pgrst, 'reload schema';
