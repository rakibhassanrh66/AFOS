-- You cannot join, or be admitted to, a course that has ended.
--
-- Found in live data: two students sit APPROVED on CSE221, which was archived
-- at 19:09, and a third request is still pending on another archived offering.
-- An archived course is hidden from every list in the app, generates no
-- schedule rows, and can carry no attendance or marks -- so an enrolment in one
-- is a student holding a place in a course that does not exist. The teacher
-- sees the request, approves it in good faith, and nothing happens afterwards.
--
-- Browse Courses already filters is_archived, so a student cannot normally SEE
-- an ended course to apply to. That is a UI filter and it is not the rule: the
-- pending row above was created before the course was archived and survived it,
-- and any direct API call bypasses the filter entirely.
--
-- Two guards, because there are two distinct moments:
--   * requesting -- refuse the INSERT outright.
--   * being admitted -- refuse the approval, since a request can outlive the
--     archiving of the course it points at, exactly as one did here.
--
-- Existing rows are deliberately left alone. They are the historical record of
-- what happened, and restoring the offering (My Course Offerings -> Ended ->
-- Restore) makes them meaningful again rather than needing a data fix.

CREATE OR REPLACE FUNCTION assert_offering_not_archived()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $fn$
DECLARE v_archived boolean; v_code text;
BEGIN
  SELECT co.is_archived, c.code INTO v_archived, v_code
  FROM course_offerings co
  LEFT JOIN courses c ON c.id = co.course_id
  WHERE co.id = NEW.offering_id;

  IF COALESCE(v_archived, false) THEN
    RAISE EXCEPTION
      '% has ended and is no longer accepting students. Restore it first if this was a mistake.',
      COALESCE(v_code, 'That course')
      USING errcode = '23514';
  END IF;

  RETURN NEW;
END;
$fn$;

REVOKE ALL ON FUNCTION assert_offering_not_archived() FROM public, anon, authenticated;

DROP TRIGGER IF EXISTS trg_no_enrolment_into_archived ON enrollments;
CREATE TRIGGER trg_no_enrolment_into_archived
  BEFORE INSERT ON enrollments
  FOR EACH ROW EXECUTE FUNCTION assert_offering_not_archived();

-- Approval is the second moment. A request made while the course was live can
-- still be sitting there after it is archived -- which is precisely the state
-- found on this project -- so the INSERT guard alone would not have caught it.
DROP TRIGGER IF EXISTS trg_no_approval_into_archived ON enrollments;
CREATE TRIGGER trg_no_approval_into_archived
  BEFORE UPDATE OF status ON enrollments
  FOR EACH ROW
  WHEN (NEW.status = 'approved' AND OLD.status IS DISTINCT FROM 'approved')
  EXECUTE FUNCTION assert_offering_not_archived();
