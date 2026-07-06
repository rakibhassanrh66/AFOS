-- Conference room booking for teacher/staff — request purpose+date+time,
-- super_admin approves and assigns the actual room number (no separate
-- room inventory table exists yet, so the room number is just set at
-- approval time, same pattern as Hall Allocation's assigned_room).

CREATE TABLE conference_room_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  requester_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  purpose text NOT NULL,
  requested_date date NOT NULL,
  start_time time NOT NULL,
  end_time time NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
  assigned_room text,
  rejection_reason text,
  reviewed_by uuid REFERENCES profiles(id) ON DELETE SET NULL,
  reviewed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE conference_room_requests ENABLE ROW LEVEL SECURITY;

-- Only teacher/staff can request — students have no reason to, and
-- admin-tier roles act through the approval side, not as requesters.
CREATE POLICY own_conference_request_insert ON conference_room_requests
  FOR INSERT
  WITH CHECK (
    auth.uid() = requester_id
    AND get_my_profile_role() = ANY (ARRAY['teacher', 'staff'])
  );

CREATE POLICY own_conference_request_read ON conference_room_requests
  FOR SELECT USING (auth.uid() = requester_id);

-- Self-cancel while still pending — same shape as Hall's pre-allocation cancel.
CREATE POLICY own_conference_request_cancel ON conference_room_requests
  FOR UPDATE
  USING (auth.uid() = requester_id AND status = 'pending')
  WITH CHECK (auth.uid() = requester_id AND status = 'cancelled');

CREATE POLICY super_admin_manage_conference_requests ON conference_room_requests
  FOR ALL
  USING (get_my_profile_role() = 'super_admin')
  WITH CHECK (get_my_profile_role() = 'super_admin');
