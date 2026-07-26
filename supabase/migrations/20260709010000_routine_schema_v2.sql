-- ══════════════════════════════════════════════════════════════════════
--  AFOS — Routine system v2: clean building/room split (parser-side fix,
--  not schema), lab rooms, retake classes, lab-subgroup splitting, a
--  student/teacher "pin a retake course to my schedule" mechanism, and a
--  self-service "this room is free, claim it" request with 24h auto-expiry.
-- ══════════════════════════════════════════════════════════════════════

ALTER TABLE schedule_slots ADD COLUMN IF NOT EXISTS room_type text;       -- raw lab-tag text e.g. 'COM LAB'; null for a normal classroom
ALTER TABLE schedule_slots ADD COLUMN IF NOT EXISTS is_lab boolean NOT NULL DEFAULT false;
ALTER TABLE schedule_slots ADD COLUMN IF NOT EXISTS is_retake boolean NOT NULL DEFAULT false;
ALTER TABLE schedule_slots ADD COLUMN IF NOT EXISTS lab_subgroup int CHECK (lab_subgroup IN (1,2));

-- lab_subgroup joins the identity key so a lab section's two halves (J1/J2,
-- same course/batch/section but different day/time/room) don't collide with
-- each other; day/time/room already disambiguate them in practice, but this
-- keeps the key self-descriptive. index.ts's batchUpsert onConflict and
-- deleteObsolete keyFields must move in lockstep with this (see
-- 006_fix_schedule_slots_constraint.sql for why a drift here is dangerous —
-- it silently made the old constraint reject almost every real routine row).
DROP INDEX IF EXISTS schedule_slots_identity;
CREATE UNIQUE INDEX IF NOT EXISTS schedule_slots_identity ON schedule_slots
  (subject_code, day_of_week, start_time, room_number, batch, section, lab_subgroup, department, semester);

-- "Add this retake course to my schedule" — a student/teacher's own pinned
-- extra slot, separate from admin-uploaded schedule_slots data. FK to the
-- real slot row (not a text-key mirror) so it always points at genuine
-- routine data; if a re-upload changes that row's identity-key fields, the
-- old row is deleted and a new one inserted (existing parser behavior),
-- which silently un-pins it — acceptable tradeoff, flagged for future
-- attention if it proves surprising in practice.
CREATE TABLE IF NOT EXISTS user_pinned_slots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  schedule_slot_id uuid NOT NULL REFERENCES schedule_slots(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, schedule_slot_id)
);
ALTER TABLE user_pinned_slots ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_pinned_slots ON user_pinned_slots FOR ALL
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
ALTER PUBLICATION supabase_realtime ADD TABLE user_pinned_slots;

-- Empty-room claim: a CR or teacher self-service "I'm using this free
-- room/period" log, no approval workflow. Deliberately not tied to a
-- specific schedule_slots row (an empty slot has none) -- room+day+time
-- identifies it directly, matching how the source routine PDF is laid out
-- (room x period grid).
CREATE TABLE IF NOT EXISTS empty_room_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  requester_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  department text NOT NULL,
  building text NOT NULL,
  room_number text NOT NULL,
  day_of_week int NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
  start_time time NOT NULL,
  end_time time NOT NULL,
  purpose text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE empty_room_requests ENABLE ROW LEVEL SECURITY;

-- Matches auth_read_schedule's openness on schedule_slots itself (any
-- authenticated user can already read the whole routine) -- an empty-room
-- claim is exactly as sensitive as the routine data it's layered on top of.
CREATE POLICY read_empty_room_requests ON empty_room_requests FOR SELECT TO authenticated USING (true);

CREATE POLICY insert_own_empty_room_request ON empty_room_requests FOR INSERT
  WITH CHECK (auth.uid() = requester_id AND (
    get_my_profile_role() = 'teacher'
    OR EXISTS (SELECT 1 FROM students s WHERE s.profile_id = auth.uid() AND s.is_cr = true)
  ));

CREATE POLICY own_delete_empty_room_request ON empty_room_requests FOR DELETE USING (auth.uid() = requester_id);

ALTER PUBLICATION supabase_realtime ADD TABLE empty_room_requests;

-- Same 24h auto-expiry pattern already running for dept_messages/
-- club_messages ("expire-dept-messages"/"expire-club-messages") -- actually
-- deletes the rows (frees storage, per the feature's own stated goal)
-- rather than a valid_until column the UI would just filter around.
SELECT cron.schedule('expire-empty-room-requests', '*/15 * * * *',
  $$DELETE FROM empty_room_requests WHERE created_at < now() - interval '24 hours'$$);
