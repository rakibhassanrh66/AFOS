-- profiles ended up with two avatar columns: avatar_url (original,
-- 001_init.sql) and photo_url (added later, 20260623160352_init_v8_schema.sql).
-- Every upload path (AvatarPicker) only ever writes avatar_url, but
-- UserModel.fromJson and complete_profile_screen read `photo_url ?? avatar_url`,
-- so a stale non-null photo_url on any row permanently masks a freshly
-- uploaded avatar_url — this is the "two different pictures" bug reported
-- live testing. Consolidate to the single column every writer actually uses.

UPDATE profiles SET avatar_url = photo_url
WHERE avatar_url IS NULL AND photo_url IS NOT NULL;

-- verify_vr_id_scan returns photo_url alongside avatar_url; drop+recreate
-- without it before dropping the column (CREATE OR REPLACE can't change the
-- RETURNS TABLE column list).
DROP FUNCTION IF EXISTS verify_vr_id_scan(uuid, text, bigint);

ALTER TABLE profiles DROP COLUMN IF EXISTS photo_url;

CREATE OR REPLACE FUNCTION verify_vr_id_scan(p_uid uuid, p_vrid text, p_exp bigint)
RETURNS TABLE (
  id text,
  full_name text,
  university_id text,
  student_id text,
  department text,
  semester int,
  role text,
  avatar_url text
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
         p.role, p.avatar_url
  FROM profiles p WHERE p.id = p_uid;
END;
$$;

GRANT EXECUTE ON FUNCTION verify_vr_id_scan(uuid, text, bigint) TO authenticated;
