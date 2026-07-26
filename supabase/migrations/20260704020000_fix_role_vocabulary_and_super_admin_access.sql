-- =====================================================================
--  AFOS — Fix role-name drift + missing super_admin/dept_admin access
--
--  Root cause: several RLS policies were written checking profiles.role
--  against 'faculty', 'dept_head', 'hall_manager' — none of which are
--  real values. handle_new_user() only ever assigns 'student', 'teacher',
--  or whatever an admin manually sets via the new admin_manage_all_profiles
--  policy, and the seeded `roles` table only has: student, teacher,
--  admin, super_admin, staff, dept_admin, exam_controller. This means
--  every real teacher account (role='teacher') has been silently locked
--  out of posting notices, pinning dept-chat messages, and reading
--  teacher-only channels since these features were added — the checks
--  could never match.
--
--  Also: several admin-gated policies never included 'super_admin' at
--  all (exam_seat_assignments, hall_applications), meaning the Super
--  Admin account could not manage exam seating or hall applications
--  through the app despite being required to bypass/oversee everything.
--
--  This migration normalizes role vocabulary to match the real `roles`
--  table and ensures super_admin is included everywhere an admin-level
--  bypass is expected, and gives dept_admin the same department-scoped
--  academic permissions as admin (grade_change, students, results).
-- =====================================================================

-- dept_channels: teacher-only channel visibility
DROP POLICY IF EXISTS "auth_read_channels" ON dept_channels;
CREATE POLICY "auth_read_channels" ON dept_channels FOR SELECT TO authenticated USING (
  audience = 'all'
  OR (audience = 'teachers' AND EXISTS (
        SELECT 1 FROM profiles
        WHERE profiles.id = auth.uid()
          AND profiles.role = ANY (ARRAY['teacher','admin','dept_admin','super_admin'])
      ))
  OR (audience = 'students' AND EXISTS (
        SELECT 1 FROM profiles
        WHERE profiles.id = auth.uid()
          AND profiles.role <> ALL (ARRAY['teacher','admin','dept_admin','super_admin'])
      ))
);

-- dept_messages: pin permission
DROP POLICY IF EXISTS "admin_pin" ON dept_messages;
CREATE POLICY "admin_pin" ON dept_messages FOR UPDATE USING (
  EXISTS (
    SELECT 1 FROM profiles
    WHERE profiles.id = auth.uid()
      AND profiles.role = ANY (ARRAY['admin','teacher','dept_admin','super_admin'])
  )
);

-- dept_messages: read visibility (department + audience aware)
DROP POLICY IF EXISTS "dept_members_read" ON dept_messages;
CREATE POLICY "dept_members_read" ON dept_messages FOR SELECT TO authenticated USING (
  EXISTS (
    SELECT 1 FROM profiles p JOIN dept_channels c ON (p.department = c.department)
    WHERE p.id = auth.uid() AND c.id = dept_messages.channel_id
      AND (
        c.audience = 'all'
        OR (c.audience = 'teachers' AND p.role = ANY (ARRAY['teacher','admin','dept_admin','super_admin']))
        OR (c.audience = 'students' AND p.role <> ALL (ARRAY['teacher','admin','dept_admin','super_admin']))
      )
  )
);

-- dept_messages: send permission (department + audience aware)
DROP POLICY IF EXISTS "members_send" ON dept_messages;
CREATE POLICY "members_send" ON dept_messages FOR INSERT WITH CHECK (
  auth.uid() = sender_id
  AND EXISTS (
    SELECT 1 FROM profiles p JOIN dept_channels c ON (p.department = c.department)
    WHERE p.id = auth.uid() AND c.id = dept_messages.channel_id
      AND (
        c.audience = 'all'
        OR (c.audience = 'teachers' AND p.role = ANY (ARRAY['teacher','admin','dept_admin','super_admin']))
        OR (c.audience = 'students' AND p.role <> ALL (ARRAY['teacher','admin','dept_admin','super_admin']))
      )
  )
);

-- notices: who can post
DROP POLICY IF EXISTS "admin_write_notices" ON notices;
CREATE POLICY "admin_write_notices" ON notices FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1 FROM profiles
    WHERE profiles.id = auth.uid()
      AND profiles.role = ANY (ARRAY['admin','teacher','dept_admin','super_admin'])
  )
);

-- hall_applications: hall_manager -> staff, add super_admin/dept_admin
DROP POLICY IF EXISTS "admin_hall_all" ON hall_applications;
CREATE POLICY "admin_hall_all" ON hall_applications FOR ALL USING (
  EXISTS (
    SELECT 1 FROM profiles
    WHERE profiles.id = auth.uid()
      AND profiles.role = ANY (ARRAY['admin','staff','super_admin'])
  )
);

-- exam_seat_assignments: add super_admin + exam_controller
DROP POLICY IF EXISTS "admin_seats" ON exam_seat_assignments;
CREATE POLICY "admin_seats" ON exam_seat_assignments FOR ALL USING (
  EXISTS (
    SELECT 1 FROM profiles
    WHERE profiles.id = auth.uid()
      AND profiles.role = ANY (ARRAY['admin','super_admin','exam_controller'])
  )
);

-- dept_admin gets the same department-scoped academic permissions as admin
INSERT INTO role_permissions (role_id, permission_id)
SELECT (SELECT id FROM roles WHERE name = 'dept_admin'), rp.permission_id
FROM role_permissions rp
WHERE rp.role_id = (SELECT id FROM roles WHERE name = 'admin')
ON CONFLICT DO NOTHING;
