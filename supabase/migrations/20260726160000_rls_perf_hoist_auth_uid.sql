-- Performance-only rewrite of the attendance / marks / results policies.
-- Semantics are unchanged; every predicate below is the one already in place,
-- with two mechanical differences.
--
-- 1. `auth.uid()` -> `(SELECT auth.uid())`. Bare, it is treated as volatile and
--    re-evaluated once PER ROW; wrapped, the planner hoists it to an InitPlan
--    and evaluates it once per query. On a 50-student register that is 50
--    calls instead of 1, and it is the single biggest cost in reading these
--    tables. Flagged by the advisors as auth_rls_initplan.
--
-- 2. `TO authenticated`. These were created with no TO clause, which defaults
--    to PUBLIC and therefore includes `anon`. An anonymous caller could never
--    satisfy the predicates anyway, but Postgres still evaluated every policy
--    for them, and it made the intended audience unreadable from the schema.
--
-- The module_leaders / teaching_assignments policies added later already do
-- both; this brings the earlier three migrations in line with them.
--
-- Verified after applying by running a probe as SET LOCAL ROLE authenticated
-- with request.jwt.claims set to each party in turn: the owning teacher sees
-- their register, a second teacher sees zero rows, an enrolled student sees
-- their own record and the session, and a student cannot write a record.

-- ------------------------------------------------------ attendance_sessions

DROP POLICY IF EXISTS teacher_manage_own_attendance_sessions ON attendance_sessions;
CREATE POLICY teacher_manage_own_attendance_sessions ON attendance_sessions
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM course_offerings co
                  WHERE co.id = attendance_sessions.offering_id
                    AND co.teacher_id = (SELECT auth.uid())))
  WITH CHECK (EXISTS (SELECT 1 FROM course_offerings co
                       WHERE co.id = attendance_sessions.offering_id
                         AND co.teacher_id = (SELECT auth.uid())));

DROP POLICY IF EXISTS student_read_own_attendance_sessions ON attendance_sessions;
CREATE POLICY student_read_own_attendance_sessions ON attendance_sessions
  FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM enrollments e
                  WHERE e.offering_id = attendance_sessions.offering_id
                    AND e.student_id = (SELECT auth.uid())
                    AND e.status = 'approved'));

DROP POLICY IF EXISTS admin_observe_attendance_sessions ON attendance_sessions;
CREATE POLICY admin_observe_attendance_sessions ON attendance_sessions
  FOR SELECT TO authenticated
  USING (get_my_profile_role() = ANY (ARRAY['admin','dept_admin','super_admin','exam_controller']));

-- ------------------------------------------------------- attendance_records

DROP POLICY IF EXISTS teacher_manage_own_attendance_records ON attendance_records;
CREATE POLICY teacher_manage_own_attendance_records ON attendance_records
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM attendance_sessions s
                   JOIN course_offerings co ON co.id = s.offering_id
                  WHERE s.id = attendance_records.session_id
                    AND co.teacher_id = (SELECT auth.uid())))
  WITH CHECK (EXISTS (SELECT 1 FROM attendance_sessions s
                        JOIN course_offerings co ON co.id = s.offering_id
                       WHERE s.id = attendance_records.session_id
                         AND co.teacher_id = (SELECT auth.uid())));

DROP POLICY IF EXISTS student_read_own_attendance_records ON attendance_records;
CREATE POLICY student_read_own_attendance_records ON attendance_records
  FOR SELECT TO authenticated
  USING (student_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS admin_observe_attendance_records ON attendance_records;
CREATE POLICY admin_observe_attendance_records ON attendance_records
  FOR SELECT TO authenticated
  USING (get_my_profile_role() = ANY (ARRAY['admin','dept_admin','super_admin','exam_controller']));

-- ------------------------------------------------------------ student_marks

DROP POLICY IF EXISTS teacher_manage_own_student_marks ON student_marks;
CREATE POLICY teacher_manage_own_student_marks ON student_marks
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM enrollments e
                   JOIN course_offerings co ON co.id = e.offering_id
                  WHERE e.id = student_marks.enrollment_id
                    AND co.teacher_id = (SELECT auth.uid())))
  WITH CHECK (EXISTS (SELECT 1 FROM enrollments e
                        JOIN course_offerings co ON co.id = e.offering_id
                       WHERE e.id = student_marks.enrollment_id
                         AND co.teacher_id = (SELECT auth.uid())));

DROP POLICY IF EXISTS student_read_published_marks ON student_marks;
CREATE POLICY student_read_published_marks ON student_marks
  FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM enrollments e
                   JOIN offering_result_submissions ors ON ors.offering_id = e.offering_id
                  WHERE e.id = student_marks.enrollment_id
                    AND e.student_id = (SELECT auth.uid())
                    AND ors.status = 'approved'));

DROP POLICY IF EXISTS admin_observe_student_marks ON student_marks;
CREATE POLICY admin_observe_student_marks ON student_marks
  FOR SELECT TO authenticated
  USING (get_my_profile_role() = ANY (ARRAY['admin','dept_admin','super_admin','exam_controller']));

-- ---------------------------------------------- offering_result_submissions

DROP POLICY IF EXISTS teacher_submit_own_results ON offering_result_submissions;
CREATE POLICY teacher_submit_own_results ON offering_result_submissions
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM course_offerings co
                  WHERE co.id = offering_result_submissions.offering_id
                    AND co.teacher_id = (SELECT auth.uid())))
  WITH CHECK (EXISTS (SELECT 1 FROM course_offerings co
                       WHERE co.id = offering_result_submissions.offering_id
                         AND co.teacher_id = (SELECT auth.uid())));

DROP POLICY IF EXISTS student_read_own_result_status ON offering_result_submissions;
CREATE POLICY student_read_own_result_status ON offering_result_submissions
  FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM enrollments e
                  WHERE e.offering_id = offering_result_submissions.offering_id
                    AND e.student_id = (SELECT auth.uid())
                    AND e.status = 'approved'));

DROP POLICY IF EXISTS admin_review_result_submissions ON offering_result_submissions;
CREATE POLICY admin_review_result_submissions ON offering_result_submissions
  FOR ALL TO authenticated
  USING (get_my_profile_role() = ANY (ARRAY['admin','dept_admin','super_admin','exam_controller']))
  WITH CHECK (get_my_profile_role() = ANY (ARRAY['admin','dept_admin','super_admin','exam_controller']));

-- ------------------------------------------------------------------ indexes

-- assignment_submissions.graded_by is a foreign key with no covering index, so
-- deleting or updating the referenced profile forced a sequential scan of
-- every submission. Flagged as unindexed_foreign_keys.
CREATE INDEX IF NOT EXISTS assignment_submissions_graded_by_idx
  ON assignment_submissions (graded_by);
