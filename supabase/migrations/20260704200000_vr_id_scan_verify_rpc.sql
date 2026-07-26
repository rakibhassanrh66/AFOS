-- ═══════════════════════════════════════════════════════════════════════
--  VR-ID scan verification — narrow, purpose-built RPC
--
--  Root cause fixed: no `profiles` SELECT policy lets an arbitrary
--  student/teacher read another arbitrary student's profile row, so the
--  scan screen's direct `profiles.select().eq('id',uid).single()` always
--  returned 0 rows under RLS and the scan silently showed nothing. A
--  blanket "read all profiles" policy would be a real security
--  regression, so instead this is a SECURITY DEFINER function scoped
--  specifically to the "verify a scanned VR-ID token" action, which also
--  re-validates the HMAC/expiry server-side (defense in depth — the
--  client previously only checked expiry before querying, and never
--  re-derived the hash at all).
-- ═══════════════════════════════════════════════════════════════════════

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE OR REPLACE FUNCTION verify_vr_id_scan(p_uid uuid, p_vrid text, p_exp bigint)
RETURNS TABLE (
  full_name text,
  university_id text,
  student_id text,
  department text,
  semester int,
  role text,
  avatar_url text,
  photo_url text
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

  -- Re-derive the same hash the client computes
  -- (sha256('$uid:$minute:afos-salt').substring(0,16)), for the current
  -- and immediately-prior 60s bucket to tolerate clock-edge scans.
  v_expected_now  := substring(encode(digest(p_uid::text || ':' || v_minute_now  || ':afos-salt', 'sha256'), 'hex') from 1 for 16);
  v_expected_prev := substring(encode(digest(p_uid::text || ':' || v_minute_prev || ':afos-salt', 'sha256'), 'hex') from 1 for 16);

  IF p_vrid IS DISTINCT FROM v_expected_now AND p_vrid IS DISTINCT FROM v_expected_prev THEN
    RAISE EXCEPTION 'Invalid VR-ID token';
  END IF;

  INSERT INTO vr_access_log (scanned_user_id, scanned_by_id, location_note)
  VALUES (p_uid, auth.uid(), 'DIU Campus');

  RETURN QUERY
  SELECT p.full_name, p.university_id, p.student_id, p.department, p.semester,
         p.role, p.avatar_url, p.photo_url
  FROM profiles p WHERE p.id = p_uid;
END;
$$;

GRANT EXECUTE ON FUNCTION verify_vr_id_scan(uuid, text, bigint) TO authenticated;
