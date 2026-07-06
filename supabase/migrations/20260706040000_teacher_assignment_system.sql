-- Teacher assignment system: upload with a deadline, students submit,
-- automated day-before warning + missed-deadline notice via pg_cron
-- (already installed on this project) since those need to fire on a
-- schedule, not in response to any user action.

CREATE TABLE assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  teacher_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  department_id uuid NOT NULL REFERENCES departments(id),
  course_code text NOT NULL,
  course_title text,
  batch text NOT NULL,
  section text NOT NULL,
  semester int NOT NULL,
  title text NOT NULL,
  description text,
  attachment_url text,
  deadline timestamptz NOT NULL,
  reminder_sent boolean NOT NULL DEFAULT false,
  missed_notified boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE assignments ENABLE ROW LEVEL SECURITY;

CREATE POLICY teacher_manage_own_assignments ON assignments
  FOR ALL
  USING (auth.uid() = teacher_id)
  WITH CHECK (auth.uid() = teacher_id);

-- A teacher can remove an assignment only while it's still open — once the
-- deadline passes, students may already be relying on it having existed
-- (grading, disputes), so it can no longer just disappear.
CREATE POLICY teacher_delete_before_deadline ON assignments
  FOR DELETE
  USING (auth.uid() = teacher_id AND deadline > now());

CREATE POLICY student_read_own_section_assignments ON assignments
  FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM students s
    WHERE s.profile_id = auth.uid()
      AND s.department_id = assignments.department_id
      AND s.batch_label = assignments.batch
      AND s.section = assignments.section
  ));

CREATE POLICY super_admin_observe_assignments ON assignments
  FOR SELECT
  USING (get_my_profile_role() = 'super_admin');

CREATE TABLE assignment_submissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  assignment_id uuid NOT NULL REFERENCES assignments(id) ON DELETE CASCADE,
  student_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  content text,
  attachment_url text,
  submitted_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (assignment_id, student_id)
);

ALTER TABLE assignment_submissions ENABLE ROW LEVEL SECURITY;

CREATE POLICY own_submission_insert ON assignment_submissions
  FOR INSERT WITH CHECK (auth.uid() = student_id);

CREATE POLICY own_submission_read ON assignment_submissions
  FOR SELECT USING (auth.uid() = student_id);

CREATE POLICY teacher_read_submissions_own_assignment ON assignment_submissions
  FOR SELECT
  USING (EXISTS (SELECT 1 FROM assignments a WHERE a.id = assignment_submissions.assignment_id AND a.teacher_id = auth.uid()));

CREATE POLICY super_admin_observe_submissions ON assignment_submissions
  FOR SELECT
  USING (get_my_profile_role() = 'super_admin');

-- Deadline-driven notifications, checked hourly (see cron jobs below).
-- Direct in-app inserts, not a push — the automated cron context has no
-- authenticated caller to invoke send-notification's OneSignal path as,
-- and embedding the OneSignal REST key into Postgres to call it directly
-- is a separate, deliberately-not-taken step (see checkpoint notes).
CREATE OR REPLACE FUNCTION send_assignment_reminders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  a RECORD;
  s RECORD;
BEGIN
  FOR a IN
    SELECT * FROM assignments
    WHERE reminder_sent = false
      AND deadline BETWEEN now() + interval '23 hours' AND now() + interval '25 hours'
  LOOP
    FOR s IN
      SELECT p.id FROM students st
      JOIN profiles p ON p.id = st.profile_id
      WHERE st.department_id = a.department_id
        AND st.batch_label = a.batch
        AND st.section = a.section
        AND NOT EXISTS (
          SELECT 1 FROM assignment_submissions sub
          WHERE sub.assignment_id = a.id AND sub.student_id = st.profile_id
        )
    LOOP
      INSERT INTO user_notifications (user_id, title, body, category, deep_link_route)
      VALUES (s.id, 'Assignment due tomorrow', a.title || ' is due in less than 24 hours — submit soon.', 'assignment', '/assignments');
    END LOOP;
    UPDATE assignments SET reminder_sent = true WHERE id = a.id;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION send_assignment_missed_notices()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  a RECORD;
  s RECORD;
BEGIN
  FOR a IN
    SELECT * FROM assignments
    WHERE missed_notified = false
      AND deadline BETWEEN now() - interval '2 hours' AND now()
  LOOP
    FOR s IN
      SELECT p.id FROM students st
      JOIN profiles p ON p.id = st.profile_id
      WHERE st.department_id = a.department_id
        AND st.batch_label = a.batch
        AND st.section = a.section
        AND NOT EXISTS (
          SELECT 1 FROM assignment_submissions sub
          WHERE sub.assignment_id = a.id AND sub.student_id = st.profile_id
        )
    LOOP
      INSERT INTO user_notifications (user_id, title, body, category, deep_link_route)
      VALUES (s.id, 'Assignment deadline missed', 'You did not submit "' || a.title || '" before the deadline.', 'assignment', '/assignments');
    END LOOP;
    UPDATE assignments SET missed_notified = true WHERE id = a.id;
  END LOOP;
END;
$$;

SELECT cron.schedule('assignment-reminders', '*/30 * * * *', $$SELECT send_assignment_reminders()$$);
SELECT cron.schedule('assignment-missed-notices', '*/30 * * * *', $$SELECT send_assignment_missed_notices()$$);
