-- Module leaders and the teaching loads they hand out.
--
-- The gap this fills: nothing recorded WHO is supposed to teach WHAT. A
-- teacher opened the New Course Offering form and typed a course code, a
-- batch and a section from memory. Two teachers could each claim the same
-- class, a typo produced a section nobody belongs to, and the department had
-- no list of what had actually been allocated for the semester.
--
-- The university process is that each department has a course module leader
-- who allocates the semester's teaching -- e.g. four theory sections and four
-- lab groups to one teacher -- and the teacher then fills in the course
-- detail and submits it for approval as before. This models exactly that:
-- an allocation is a record, and the offering form starts from it.
--
-- NOT a new value in profiles.role. That CHECK constraint is referenced by
-- get_my_profile_role() across a large number of RLS policies, and a module
-- leader is still a teacher -- they teach their own classes too. Being a
-- module leader is an appointment held IN a department, the same way a club
-- supervisor is an appointment held in a club, so it is a row rather than a
-- change of identity.

-- ----------------------------------------------------------- the appointment

CREATE TABLE IF NOT EXISTS module_leaders (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  department    text NOT NULL,
  teacher_id    uuid NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
  appointed_by  uuid REFERENCES profiles (id) ON DELETE SET NULL,
  appointed_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (department, teacher_id)
);

CREATE INDEX IF NOT EXISTS module_leaders_teacher_idx ON module_leaders (teacher_id);

COMMENT ON TABLE module_leaders IS
  'Teachers appointed to allocate a department''s teaching load. Appointment '
  'is granted by an admin; the holder keeps their ordinary teacher role.';

-- Deliberately STABLE + SECURITY DEFINER: called from the RLS policies on
-- teaching_assignments below, where an ordinary teacher cannot see the
-- module_leaders rows of a department they are not in.
CREATE OR REPLACE FUNCTION is_module_leader(p_department text, p_user_id uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
  SELECT EXISTS (
    SELECT 1 FROM module_leaders ml
    WHERE ml.teacher_id = p_user_id
      AND ml.department = p_department
  );
$fn$;

REVOKE ALL ON FUNCTION is_module_leader(text, uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION is_module_leader(text, uuid) TO authenticated;

-- ------------------------------------------------------------- the allocation

CREATE TABLE IF NOT EXISTS teaching_assignments (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  department    text NOT NULL,
  teacher_id    uuid NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
  course_code   text NOT NULL,
  course_title  text NOT NULL DEFAULT '',
  course_type   text NOT NULL DEFAULT 'theory' CHECK (course_type IN ('theory', 'lab')),
  batch         text NOT NULL,
  section       text NOT NULL,
  semester      integer NOT NULL CHECK (semester BETWEEN 1 AND 12),
  note          text NOT NULL DEFAULT '',
  assigned_by   uuid REFERENCES profiles (id) ON DELETE SET NULL,
  assigned_at   timestamptz NOT NULL DEFAULT now(),
  -- Set once the teacher turns this allocation into an actual offering, so
  -- the module leader can see what has and has not been acted on. ON DELETE
  -- SET NULL rather than CASCADE: withdrawing a pending offering should
  -- return the allocation to the to-do list, not silently delete it.
  offering_id   uuid REFERENCES course_offerings (id) ON DELETE SET NULL,
  -- The integrity rule that matters. One teacher per course/batch/section
  -- per semester -- two teachers cannot each believe they own 63M's CSE221,
  -- which is the class of confusion the whole feature exists to remove.
  UNIQUE (department, course_code, batch, section, semester)
);

CREATE INDEX IF NOT EXISTS teaching_assignments_teacher_idx
  ON teaching_assignments (teacher_id, semester);
CREATE INDEX IF NOT EXISTS teaching_assignments_department_idx
  ON teaching_assignments (department, semester);

COMMENT ON TABLE teaching_assignments IS
  'What a module leader has allocated to a teacher for a semester. The '
  'teacher''s New Course Offering form starts from these rows.';

-- ---------------------------------------------------------------------- RLS

ALTER TABLE module_leaders ENABLE ROW LEVEL SECURITY;
ALTER TABLE teaching_assignments ENABLE ROW LEVEL SECURITY;

-- Readable by any signed-in user: a teacher needs to know who allocates in
-- their department, and it is not sensitive.
DROP POLICY IF EXISTS read_module_leaders ON module_leaders;
CREATE POLICY read_module_leaders ON module_leaders
  FOR SELECT TO authenticated USING (true);

-- Appointing a module leader is an admin act. A module leader cannot appoint
-- more module leaders -- that would let the appointment spread sideways
-- without the department ever agreeing to it.
DROP POLICY IF EXISTS admin_manage_module_leaders ON module_leaders;
CREATE POLICY admin_manage_module_leaders ON module_leaders
  FOR ALL TO authenticated
  USING (
    get_my_profile_role() IN ('admin', 'dept_admin', 'super_admin')
    OR caller_can('course_offerings', 'manage')
  )
  WITH CHECK (
    get_my_profile_role() IN ('admin', 'dept_admin', 'super_admin')
    OR caller_can('course_offerings', 'manage')
  );

-- A teacher reads only what was allocated to them.
DROP POLICY IF EXISTS teacher_read_own_assignments ON teaching_assignments;
CREATE POLICY teacher_read_own_assignments ON teaching_assignments
  FOR SELECT TO authenticated
  USING (teacher_id = (SELECT auth.uid()));

-- ...and may claim one by stamping the offering they created from it. The
-- WITH CHECK pins teacher_id so an UPDATE cannot be used to reassign the row
-- to somebody else, and the offering must genuinely be theirs.
DROP POLICY IF EXISTS teacher_claim_own_assignment ON teaching_assignments;
CREATE POLICY teacher_claim_own_assignment ON teaching_assignments
  FOR UPDATE TO authenticated
  USING (teacher_id = (SELECT auth.uid()))
  WITH CHECK (
    teacher_id = (SELECT auth.uid())
    AND (
      offering_id IS NULL
      OR EXISTS (
        SELECT 1 FROM course_offerings co
        WHERE co.id = offering_id AND co.teacher_id = (SELECT auth.uid())
      )
    )
  );

DROP POLICY IF EXISTS module_leader_manage_assignments ON teaching_assignments;
CREATE POLICY module_leader_manage_assignments ON teaching_assignments
  FOR ALL TO authenticated
  USING (is_module_leader(department))
  WITH CHECK (is_module_leader(department));

DROP POLICY IF EXISTS admin_manage_assignments ON teaching_assignments;
CREATE POLICY admin_manage_assignments ON teaching_assignments
  FOR ALL TO authenticated
  USING (
    get_my_profile_role() IN ('admin', 'dept_admin', 'super_admin')
    OR caller_can('course_offerings', 'manage')
  )
  WITH CHECK (
    get_my_profile_role() IN ('admin', 'dept_admin', 'super_admin')
    OR caller_can('course_offerings', 'manage')
  );

-- ------------------------------------------------------------- notification

-- Tell the teacher in the same transaction as the allocation. A client-side
-- follow-up call is silently lost if the app is backgrounded mid-request,
-- which is how a course offering once sat for hours with nobody informed.
CREATE OR REPLACE FUNCTION notify_teaching_assigned()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
BEGIN
  INSERT INTO user_notifications (user_id, title, body, category, deep_link_route)
  VALUES (
    NEW.teacher_id,
    'New teaching assignment',
    NEW.course_code || ' (' || NEW.course_type || ') — Batch ' || NEW.batch ||
      ', Section ' || NEW.section || '. Create the course offering when ready.',
    'course_offering',
    '/schedule/my-offerings'
  );
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_notify_teaching_assigned ON teaching_assignments;
CREATE TRIGGER trg_notify_teaching_assigned
  AFTER INSERT ON teaching_assignments
  FOR EACH ROW EXECUTE FUNCTION notify_teaching_assigned();

-- -------------------------------------------------------- module leader view

-- What a module leader sees: every allocation in their department with the
-- teacher's name and whether it has been turned into an offering yet.
-- security_invoker so the RLS above still applies -- the view must not become
-- a way to read another department's allocations.
CREATE OR REPLACE VIEW teaching_assignment_overview
WITH (security_invoker = true) AS
SELECT
  ta.*,
  p.full_name       AS teacher_name,
  p.teacher_initial AS teacher_initial,
  co.status         AS offering_status
FROM teaching_assignments ta
JOIN profiles p ON p.id = ta.teacher_id
LEFT JOIN course_offerings co ON co.id = ta.offering_id;

COMMENT ON VIEW teaching_assignment_overview IS
  'teaching_assignments joined to the teacher and the offering it produced. '
  'security_invoker, so the underlying RLS still decides who sees what.';
