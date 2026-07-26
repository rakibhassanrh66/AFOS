-- Let a club's president approve/reject membership requests for their own
-- club directly, instead of every single request needing super_admin to
-- act on it manually. super_admin keeps full override access; this only
-- *adds* a narrower path for the president of the specific club involved.

-- Presidents need to see the pending requests for their own club (previously
-- only super_admin and the requesting student could read a request row).
CREATE POLICY president_read_own_club_membership_requests ON club_membership_requests
  FOR SELECT
  USING (
    EXISTS (SELECT 1 FROM club_members cm
            WHERE cm.club_id = club_membership_requests.club_id
              AND cm.member_id = auth.uid()
              AND cm.role = 'president')
  );

-- SECURITY DEFINER so the actual club_members insert/update (locked to
-- super_admin-only by `super_admin_manage_club_members`) can happen without
-- widening that policy — the authorization check (caller is the club's
-- president) lives inside the function body instead.
CREATE OR REPLACE FUNCTION approve_club_membership_request(p_request_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_club_id uuid;
  v_student_id uuid;
BEGIN
  SELECT club_id, student_id INTO v_club_id, v_student_id
  FROM club_membership_requests WHERE id = p_request_id AND status = 'pending';

  IF v_club_id IS NULL THEN
    RAISE EXCEPTION 'Request not found or already reviewed';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM club_members
                 WHERE club_id = v_club_id AND member_id = auth.uid() AND role = 'president')
     AND get_my_profile_role() <> 'super_admin' THEN
    RAISE EXCEPTION 'Only the club president or super_admin can approve this request';
  END IF;

  UPDATE club_membership_requests
    SET status = 'approved', reviewed_by = auth.uid(), reviewed_at = now()
    WHERE id = p_request_id;

  INSERT INTO club_members (club_id, member_id, role)
    VALUES (v_club_id, v_student_id, 'member')
    ON CONFLICT (club_id, member_id) DO NOTHING;
END;
$$;

CREATE OR REPLACE FUNCTION reject_club_membership_request(p_request_id uuid, p_reason text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_club_id uuid;
BEGIN
  SELECT club_id INTO v_club_id
  FROM club_membership_requests WHERE id = p_request_id AND status = 'pending';

  IF v_club_id IS NULL THEN
    RAISE EXCEPTION 'Request not found or already reviewed';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM club_members
                 WHERE club_id = v_club_id AND member_id = auth.uid() AND role = 'president')
     AND get_my_profile_role() <> 'super_admin' THEN
    RAISE EXCEPTION 'Only the club president or super_admin can reject this request';
  END IF;

  UPDATE club_membership_requests
    SET status = 'rejected', rejection_reason = p_reason, reviewed_by = auth.uid(), reviewed_at = now()
    WHERE id = p_request_id;
END;
$$;

GRANT EXECUTE ON FUNCTION approve_club_membership_request(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION reject_club_membership_request(uuid, text) TO authenticated;
