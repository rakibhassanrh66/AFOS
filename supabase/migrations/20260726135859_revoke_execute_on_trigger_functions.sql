-- Trigger functions must not be reachable as RPCs.
--
-- Postgres grants EXECUTE to PUBLIC on every new function, and PostgREST
-- exposes anything the caller can execute at /rest/v1/rpc/<name>. The six
-- functions below were added earlier in this session and inherited that
-- default, so they showed up in the security advisors as anon-callable.
--
-- The two SECURITY DEFINER ones are the ones that actually matter:
-- notify_teaching_assigned() and on_results_approved() run as the owner, and
-- while calling them outside a trigger raises (NEW is not defined), exposed
-- definer surface should not exist at all. The other four are plain
-- constraint/touch triggers, revoked for consistency -- notify_offering_
-- submitted() has been locked down this way since it was written, and a
-- convention that only half holds is one nobody can rely on.

REVOKE ALL ON FUNCTION assert_mark_components_total_100()      FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION assert_student_mark_within_component()  FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION assert_submission_marks_within_max()    FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION notify_teaching_assigned()              FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION on_results_approved()                   FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION touch_attendance_updated_at()           FROM public, anon, authenticated;
