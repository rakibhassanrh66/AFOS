-- Two audiences, told apart properly.
--
-- "A new course is open to join" goes to everyone in the offering's batch and
-- section -- most of whom are not enrolled yet, that being the point.
--
-- "Your result is published" goes to the students who actually took it. The
-- on_results_approved trigger already had this right (enrollments WHERE status
-- = 'approved'), but the push added alongside it in v2.5.13+44 reused
-- list_offering_audience, the SECTION roster. Publishing results therefore
-- banner-ed every student in the batch, including people who never took the
-- course, while the in-app row went only to those who did. Wrong recipients,
-- and the two channels disagreeing about who the message was even for.

-- --------------------------------------------------- who the section contains
--
-- Single definition, so the trigger and the RPC cannot drift. The COALESCE
-- fallback matches notify_offering_approved: the profiles/students mirror keeps
-- these equal, but a student with no students-row value must still be reachable
-- rather than silently dropped -- and previously the in-app path had that
-- fallback while the push path did not, so the two could target different sets.
CREATE OR REPLACE FUNCTION offering_section_audience(p_offering_id uuid)
RETURNS TABLE(profile_id uuid)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
  SELECT p.id
  FROM course_offerings co
  JOIN students s ON true
  JOIN profiles p ON p.id = s.profile_id
  LEFT JOIN departments d ON d.id = s.department_id
  WHERE co.id = p_offering_id
    AND COALESCE(d.code, p.department)        = co.department
    AND COALESCE(s.batch_label, p.batch)      = co.batch
    AND COALESCE(s.section,     p.section)    = co.section;
$fn$;

REVOKE ALL ON FUNCTION offering_section_audience(uuid) FROM public, anon, authenticated;

CREATE OR REPLACE FUNCTION list_offering_audience(p_offering_id uuid)
RETURNS TABLE(profile_id uuid)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING errcode='42501';
  END IF;
  RETURN QUERY SELECT a.profile_id FROM offering_section_audience(p_offering_id) a;
END;
$fn$;

REVOKE ALL ON FUNCTION list_offering_audience(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION list_offering_audience(uuid) TO authenticated;

-- ------------------------------------------------- who actually took the course
--
-- Restricted to the people entitled to publish or teach it, so it cannot be
-- used to enumerate a class roster.
CREATE OR REPLACE FUNCTION list_offering_enrolled(p_offering_id uuid)
RETURNS TABLE(profile_id uuid)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING errcode='42501';
  END IF;
  IF NOT EXISTS (
        SELECT 1 FROM course_offerings co
        WHERE co.id = p_offering_id AND co.teacher_id = auth.uid())
     AND get_my_profile_role() NOT IN ('admin','dept_admin','super_admin','exam_controller')
     AND NOT caller_can('course_offerings','manage') THEN
    RAISE EXCEPTION 'Not allowed to read this course''s roster' USING errcode='42501';
  END IF;

  RETURN QUERY
  SELECT e.student_id
  FROM enrollments e
  WHERE e.offering_id = p_offering_id AND e.status = 'approved';
END;
$fn$;

REVOKE ALL ON FUNCTION list_offering_enrolled(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION list_offering_enrolled(uuid) TO authenticated;

-- The trigger now shares the section definition instead of repeating it.
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
  SELECT a.profile_id,
         'New course available',
         v_code || ' (Section ' || COALESCE(NEW.section, '?') ||
           ') is open to join for Batch ' || COALESCE(NEW.batch, '?') || '.',
         'course_offering',
         '/schedule/browse-courses'
    FROM offering_section_audience(NEW.id) a;

  RETURN NEW;
END;
$fn$;

REVOKE ALL ON FUNCTION notify_offering_approved() FROM public, anon, authenticated;
