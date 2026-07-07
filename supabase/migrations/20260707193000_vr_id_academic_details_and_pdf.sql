-- verify_vr_id_scan only ever returned profiles-level fields (name, ID,
-- department, a legacy profiles.semester column, role, avatar) — none of
-- the real academic detail (batch/section/CGPA for students, designation
-- for teachers) needed for a proper VR-ID verification PDF. Widened the
-- return shape rather than adding a second RPC, since this is still the
-- single narrow, rate-limited, SECURITY DEFINER path that's allowed to
-- resolve a scanned stranger's profile at all.
DROP FUNCTION IF EXISTS verify_vr_id_scan(uuid, text, bigint);

CREATE OR REPLACE FUNCTION verify_vr_id_scan(p_uid uuid, p_vrid text, p_exp bigint)
RETURNS TABLE (
  id text,
  full_name text,
  university_id text,
  student_id text,
  department text,
  semester int,
  role text,
  avatar_url text,
  batch_label text,
  section text,
  cgpa numeric,
  designation text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_now_ms bigint := (extract(epoch from now()) * 1000)::bigint;
  v_minute_now text := floor(extract(epoch from now()) / 60)::bigint::text;
  v_minute_prev text := (floor(extract(epoch from now()) / 60)::bigint - 1)::text;
  v_expected_now text;
  v_expected_prev text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF p_exp <= v_now_ms THEN
    RAISE EXCEPTION 'QR expired';
  END IF;

  v_expected_now  := substring(encode(digest(p_uid::text || ':' || v_minute_now  || ':afos-salt', 'sha256'), 'hex') from 1 for 16);
  v_expected_prev := substring(encode(digest(p_uid::text || ':' || v_minute_prev || ':afos-salt', 'sha256'), 'hex') from 1 for 16);

  IF p_vrid IS DISTINCT FROM v_expected_now AND p_vrid IS DISTINCT FROM v_expected_prev THEN
    RAISE EXCEPTION 'Invalid VR-ID token';
  END IF;

  INSERT INTO vr_access_log (scanned_user_id, scanned_by_id, location_note)
  VALUES (p_uid, auth.uid(), 'DIU Campus');

  RETURN QUERY
  SELECT p.id::text, p.full_name, p.university_id, p.student_id, p.department, p.semester,
         p.role, p.avatar_url, s.batch_label, s.section, s.cgpa, t.designation
  FROM profiles p
  LEFT JOIN students s ON s.profile_id = p.id
  LEFT JOIN teachers t ON t.profile_id = p.id
  WHERE p.id = p_uid;
END;
$$;

GRANT EXECUTE ON FUNCTION verify_vr_id_scan(uuid, text, bigint) TO authenticated;

-- Private bucket — the generated verification PDF contains another
-- person's academic details, so it's never public-read like avatars.
-- Scoped to the scanning user's own folder (they generated it, they view
-- it back via a signed URL immediately after) — same shape as
-- feedback-attachments.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('vr-id-verifications', 'vr-id-verifications', false, 5242880, ARRAY['application/pdf'])
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "vr_id_verifications_own_write" ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'vr-id-verifications' AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY "vr_id_verifications_own_read" ON storage.objects FOR SELECT
  USING (bucket_id = 'vr-id-verifications' AND (storage.foldername(name))[1] = auth.uid()::text);
