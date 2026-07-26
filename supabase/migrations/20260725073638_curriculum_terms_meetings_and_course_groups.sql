-- =====================================================================
--  AFOS — Curriculum data model: real terms, multi-meeting offerings,
--  per-section course groups.
--
--  WHY. A course_offerings row could hold exactly ONE
--  (day_of_week, start_time, end_time, room, building) tuple. That cannot
--  express any of the things the feature actually needs:
--    - a course meeting twice a week,
--    - a 3-hour lab (stored as two consecutive schedule_slots rows),
--    - a lab split into J1/J2 subgroups at different times,
--  and it left theory-vs-lab entirely unmodelled on the offering even
--  though schedule_slots has carried is_lab/lab_subgroup/room_type since
--  20260709010000. An offering is a container; its meetings are rows.
--
--  ON REUSING `semesters` INSTEAD OF A NEW `academic_terms`. The plan
--  called for a new table, but `semesters` already exists with exactly the
--  right shape (id, name, start_date, end_date, is_active) AND
--  course_offerings.semester_id already references it. It was simply never
--  used by any code path. Adding a parallel table would have left two
--  tables meaning "term" and kept the dead one; reviving this one removes
--  the dead table instead of adding to it, and needs no new FK.
--
--  Note `semesters` (the academic term, "Summer 2026") and
--  course_offerings.semester (int 1..12, which semester of the programme a
--  course belongs to) are genuinely different things. Both are kept.
--
--  The legacy day_of_week/start_time/end_time/room_number/building columns
--  on course_offerings are deliberately LEFT IN PLACE here: the Dart code
--  still reads and writes them. They are dropped in the follow-up
--  migration once the repository writes meetings instead -- standard
--  expand/migrate/contract, so no intermediate state has a broken app.
-- =====================================================================


-- ---------------------------------------------------------------
-- 1. `semesters` becomes the real academic-term registry
-- ---------------------------------------------------------------
ALTER TABLE semesters
  ADD COLUMN IF NOT EXISTS code       text,
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();

-- Exactly one term may be active at a time; "the current term" has to be a
-- single unambiguous answer or every downstream default becomes a guess.
CREATE UNIQUE INDEX IF NOT EXISTS semesters_single_active
  ON semesters (is_active) WHERE is_active;

-- RLS was ENABLED on this table with ZERO policies, which in Postgres means
-- fully locked -- not even readable. That is why nothing could ever use it.
-- Same failure mode `permissions`/`role_permissions` had before 20260724135546.
DROP POLICY IF EXISTS "public_read_semesters"  ON semesters;
DROP POLICY IF EXISTS "admin_manage_semesters" ON semesters;

CREATE POLICY "public_read_semesters" ON semesters
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "admin_manage_semesters" ON semesters
  FOR ALL USING (
    get_my_profile_role() = ANY (ARRAY['admin','dept_admin','super_admin'])
    OR caller_can('course_offerings','manage')
  ) WITH CHECK (
    get_my_profile_role() = ANY (ARRAY['admin','dept_admin','super_admin'])
    OR caller_can('course_offerings','manage')
  );

-- Seed a current term so the default-term trigger below always has an
-- answer. Named for the DIU tri-semester calendar; an admin can rename it.
INSERT INTO semesters (name, code, is_active)
SELECT 'Summer 2026', 'SUM2026', true
WHERE NOT EXISTS (SELECT 1 FROM semesters);


-- ---------------------------------------------------------------
-- 2. course_offerings: term, outline, capacity, archival
-- ---------------------------------------------------------------
ALTER TABLE course_offerings
  ADD COLUMN IF NOT EXISTS outline_text  text,
  ADD COLUMN IF NOT EXISTS outline_url   text,
  ADD COLUMN IF NOT EXISTS max_students  integer,
  ADD COLUMN IF NOT EXISTS is_archived   boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS archived_at   timestamptz;

ALTER TABLE course_offerings
  DROP CONSTRAINT IF EXISTS course_offerings_max_students_check;
ALTER TABLE course_offerings
  ADD CONSTRAINT course_offerings_max_students_check
  CHECK (max_students IS NULL OR (max_students > 0 AND max_students <= 500));

-- Default the term server-side so a client never has to know which term is
-- current, and so semester_id can be trusted to be populated.
CREATE OR REPLACE FUNCTION public.set_offering_default_term()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  IF NEW.semester_id IS NULL THEN
    SELECT id INTO NEW.semester_id FROM semesters WHERE is_active LIMIT 1;
    IF NEW.semester_id IS NULL THEN
      RAISE EXCEPTION 'No active academic term is configured. An admin must mark one semester as active.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_offering_default_term ON course_offerings;
CREATE TRIGGER trg_offering_default_term
  BEFORE INSERT ON course_offerings
  FOR EACH ROW EXECUTE FUNCTION public.set_offering_default_term();

-- The old UNIQUE(course_id, semester_id, section) never fired even once:
-- semester_id was always NULL, and NULL <> NULL in a unique constraint, so
-- a teacher could submit the identical offering unlimited times. Replaced
-- with a key that includes batch (section "A" of batch 63 and of batch 64
-- are different offerings) and ignores rejected rows so a teacher can
-- resubmit a corrected version of something that was declined.
ALTER TABLE course_offerings
  DROP CONSTRAINT IF EXISTS course_offerings_course_id_semester_id_section_key;

CREATE UNIQUE INDEX IF NOT EXISTS course_offerings_term_course_batch_section_uniq
  ON course_offerings (semester_id, course_id, batch, section)
  WHERE status <> 'rejected' AND NOT is_archived;

CREATE INDEX IF NOT EXISTS course_offerings_lookup_idx
  ON course_offerings (semester_id, status, department, batch, section)
  WHERE NOT is_archived;


-- ---------------------------------------------------------------
-- 3. course_offering_meetings -- the multi-meeting fix
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS course_offering_meetings (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  offering_id       uuid NOT NULL REFERENCES course_offerings(id) ON DELETE CASCADE,
  -- Sat=0 .. Fri=6, the DIU convention schedule_slots already uses. NOT ISO.
  day_of_week       integer NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
  start_time        time NOT NULL,
  end_time          time NOT NULL,
  room_number       text,
  building          text,
  class_type        text NOT NULL DEFAULT 'theory' CHECK (class_type IN ('theory','lab')),
  -- 0 = not a lab subgroup (the sentinel schedule_slots.lab_subgroup uses),
  -- 1/2 = the J1/J2 halves a lab is split into.
  lab_subgroup      integer NOT NULL DEFAULT 0 CHECK (lab_subgroup IN (0,1,2)),
  -- The schedule_slots row generated from this meeting on approval.
  -- SET NULL rather than CASCADE: losing the slot must not silently delete
  -- the teacher's declared meeting.
  schedule_slot_id  uuid REFERENCES schedule_slots(id) ON DELETE SET NULL,
  created_at        timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT course_offering_meetings_time_order CHECK (end_time > start_time),
  CONSTRAINT course_offering_meetings_unique
    UNIQUE (offering_id, day_of_week, start_time, lab_subgroup)
);

CREATE INDEX IF NOT EXISTS course_offering_meetings_offering_idx
  ON course_offering_meetings (offering_id);
CREATE INDEX IF NOT EXISTS course_offering_meetings_slot_idx
  ON course_offering_meetings (schedule_slot_id);

ALTER TABLE course_offering_meetings ENABLE ROW LEVEL SECURITY;

-- Readable by any authenticated user, matching course_offerings'
-- public_read_offerings -- a meeting carries no more sensitive information
-- than the offering it belongs to.
DROP POLICY IF EXISTS "public_read_offering_meetings" ON course_offering_meetings;
CREATE POLICY "public_read_offering_meetings" ON course_offering_meetings
  FOR SELECT TO authenticated USING (true);

-- A teacher edits their own meetings only while the offering is still
-- pending -- same rule as teacher_update_own_pending_offering, since after
-- approval the generated schedule_slots rows would drift out of sync.
DROP POLICY IF EXISTS "teacher_manage_own_pending_meetings" ON course_offering_meetings;
CREATE POLICY "teacher_manage_own_pending_meetings" ON course_offering_meetings
  FOR ALL USING (
    EXISTS (SELECT 1 FROM course_offerings co
            WHERE co.id = course_offering_meetings.offering_id
              AND co.teacher_id = (SELECT auth.uid())
              AND co.status = 'pending')
  ) WITH CHECK (
    EXISTS (SELECT 1 FROM course_offerings co
            WHERE co.id = course_offering_meetings.offering_id
              AND co.teacher_id = (SELECT auth.uid())
              AND co.status = 'pending')
  );

DROP POLICY IF EXISTS "admin_manage_offering_meetings" ON course_offering_meetings;
CREATE POLICY "admin_manage_offering_meetings" ON course_offering_meetings
  FOR ALL USING (
    get_my_profile_role() = ANY (ARRAY['admin','dept_admin','super_admin'])
    OR caller_can('course_offerings','manage')
  ) WITH CHECK (
    get_my_profile_role() = ANY (ARRAY['admin','dept_admin','super_admin'])
    OR caller_can('course_offerings','manage')
  );


-- ---------------------------------------------------------------
-- 4. enrollments: let a declined student re-apply
-- ---------------------------------------------------------------
-- UNIQUE(student_id, offering_id) meant a rejected request permanently
-- blocked that student from ever requesting the same course again -- the
-- insert failed with a raw 23505. Scope the uniqueness to live rows.
ALTER TABLE enrollments
  DROP CONSTRAINT IF EXISTS enrollments_student_id_offering_id_key;

CREATE UNIQUE INDEX IF NOT EXISTS enrollments_active_request_uniq
  ON enrollments (student_id, offering_id) WHERE status <> 'rejected';

CREATE INDEX IF NOT EXISTS enrollments_offering_status_idx
  ON enrollments (offering_id, status);


-- ---------------------------------------------------------------
-- 5. course_messages -- one group per section (keyed on offering)
-- ---------------------------------------------------------------
-- Structural clone of club_messages (20260707183000): membership-table
-- driven RLS, with `enrollments` playing the role club_members plays there.
-- Keyed on offering_id, not course_id, so a teacher running 4 sections gets
-- 4 separate groups rather than one ~140-student room.
CREATE TABLE IF NOT EXISTS course_messages (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  offering_id  uuid NOT NULL REFERENCES course_offerings(id) ON DELETE CASCADE,
  sender_id    uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  content      text NOT NULL CHECK (length(btrim(content)) BETWEEN 1 AND 2000),
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS course_messages_offering_created_idx
  ON course_messages (offering_id, created_at DESC);
CREATE INDEX IF NOT EXISTS course_messages_sender_idx ON course_messages (sender_id);

ALTER TABLE course_messages ENABLE ROW LEVEL SECURITY;

-- Membership = an approved enrollment, or being the offering's teacher.
-- Kept as a standalone SQL function so read/insert/delete policies cannot
-- drift apart from each other the way hand-copied EXISTS clauses do.
CREATE OR REPLACE FUNCTION public.can_access_course_group(p_offering_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT (SELECT auth.uid()) IS NOT NULL AND (
    EXISTS (SELECT 1 FROM enrollments e
            WHERE e.offering_id = p_offering_id
              AND e.student_id = (SELECT auth.uid())
              AND e.status = 'approved')
    OR EXISTS (SELECT 1 FROM course_offerings co
               WHERE co.id = p_offering_id
                 AND co.teacher_id = (SELECT auth.uid()))
  );
$$;

REVOKE ALL ON FUNCTION public.can_access_course_group(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.can_access_course_group(uuid) TO authenticated;

DROP POLICY IF EXISTS "course_group_read"       ON course_messages;
DROP POLICY IF EXISTS "course_group_send"       ON course_messages;
DROP POLICY IF EXISTS "course_group_delete_own" ON course_messages;

CREATE POLICY "course_group_read" ON course_messages
  FOR SELECT TO authenticated USING (can_access_course_group(offering_id));

CREATE POLICY "course_group_send" ON course_messages
  FOR INSERT TO authenticated
  WITH CHECK (sender_id = (SELECT auth.uid()) AND can_access_course_group(offering_id));

CREATE POLICY "course_group_delete_own" ON course_messages
  FOR DELETE TO authenticated USING (sender_id = (SELECT auth.uid()));

-- Same 24h retention + 15-minute sweep as the dept and club chats.
-- Unschedule first so re-running this migration doesn't fail on a
-- duplicate job name.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'expire-course-messages') THEN
    PERFORM cron.unschedule('expire-course-messages');
  END IF;
END $$;

SELECT cron.schedule('expire-course-messages', '*/15 * * * *',
  $$DELETE FROM course_messages WHERE created_at < now() - interval '24 hours'$$);


-- ---------------------------------------------------------------
-- 6. Keep profiles.batch/section in step with the authoritative pair
-- ---------------------------------------------------------------
-- students.batch_label/students.section is what every RPC and RLS policy
-- reads; profiles.batch/section is a denormalised mirror that only
-- schedule_screen reads. Today only settings_screen writes both, so any
-- other path (admin edits, future code) silently drifts the two apart and
-- a student's routine stops matching their real section. Mirror it in the
-- database instead of relying on every call site to remember.
CREATE OR REPLACE FUNCTION public.sync_profile_batch_section()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  IF NEW.batch_label IS DISTINCT FROM OLD.batch_label
     OR NEW.section IS DISTINCT FROM OLD.section
     OR TG_OP = 'INSERT' THEN
    UPDATE profiles
       SET batch = COALESCE(NEW.batch_label, batch),
           section = COALESCE(NEW.section, section)
     WHERE id = NEW.profile_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_profile_batch_section ON students;
CREATE TRIGGER trg_sync_profile_batch_section
  AFTER INSERT OR UPDATE OF batch_label, section ON students
  FOR EACH ROW EXECUTE FUNCTION public.sync_profile_batch_section();

-- One-time reconciliation for rows that already drifted.
UPDATE profiles p
   SET batch = COALESCE(s.batch_label, p.batch),
       section = COALESCE(s.section, p.section)
  FROM students s
 WHERE s.profile_id = p.id
   AND (p.batch IS DISTINCT FROM s.batch_label OR p.section IS DISTINCT FROM s.section)
   AND (s.batch_label IS NOT NULL OR s.section IS NOT NULL);


-- ---------------------------------------------------------------
-- 7. Realtime
-- ---------------------------------------------------------------
-- Neither course_offerings nor enrollments was published, which is why an
-- admin approving an offering never reached the teacher's open screen --
-- only the push notification did.
-- ADD TABLE errors if the table is already a member, so add only what's
-- missing (same defensive shape as 20260706110000_add_missing_realtime_tables).
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['course_offerings','enrollments','course_offering_meetings','course_messages']
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = t
    ) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);
    END IF;
  END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';
