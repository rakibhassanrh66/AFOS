-- =====================================================================
--  AFOS — Make the VR-ID QR token unforgeable.
--
--  THE BUG. The "rotating, signed" VR-ID token was signed with a literal
--  salt, 'afos-salt', that appears in BOTH sides of the check:
--    - the client, lib/features/vr_id/presentation/vr_id_screen.dart:61
--    - the verifier, verify_vr_id_scan (20260707193000:44-45)
--  This repository is public, and the salt also ships inside every APK, so
--  the "signature" was computable by anyone:
--      vrid = sha256(uid || ':' || minute || ':afos-salt')[0:16]
--  Since the only other field is the uid being claimed, anyone could mint a
--  valid VR-ID for ANY user and have verify_vr_id_scan return that user's
--  name, university id, department, batch/section and CGPA. The token
--  authenticated nothing; it only proved the holder could run sha256.
--
--  THE FIX. The client stops signing entirely. A server-side secret it has
--  never seen is used for a real HMAC, and issuance moves into a definer
--  RPC that signs auth.uid() -- so a caller can only ever obtain a token
--  for *themselves*, which is the property the old design was missing.
--
--  WHERE THE SECRET LIVES. A table in a `private` schema. PostgREST only
--  exposes `public` (and graphql_public), so this is unreachable over the
--  API regardless of RLS, and only SECURITY DEFINER functions owned by the
--  table owner can read it. The value is generated here by gen_random_bytes
--  rather than supplied, which means no secret is ever written into this
--  repo, into CI, or into a command someone has to run by hand -- there is
--  nothing to leak and no manual setup step to forget.
--
--  ⚠ BREAKING, DELIBERATELY: tokens minted by an older build stop verifying
--  the moment this lands. The old scheme cannot be kept as a fallback,
--  because accepting it is exactly the vulnerability. Ship this together
--  with the app build that calls issue_vr_id_token().
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM public, anon, authenticated;

CREATE TABLE IF NOT EXISTS private.app_secrets (
  name       text PRIMARY KEY,
  value      text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
REVOKE ALL ON private.app_secrets FROM public, anon, authenticated;

-- Belt and braces: the schema is unexposed and unreadable, but if a future
-- migration ever exposes it, RLS with zero policies denies everything.
ALTER TABLE private.app_secrets ENABLE ROW LEVEL SECURITY;

-- 32 random bytes, generated in-database. ON CONFLICT DO NOTHING makes this
-- migration safe to re-run without rotating the key out from under live QRs.
INSERT INTO private.app_secrets (name, value)
VALUES ('vr_id_hmac', encode(extensions.gen_random_bytes(32), 'hex'))
ON CONFLICT (name) DO NOTHING;


-- Issues a short-lived token for the CALLER only. There is no uid
-- parameter by design -- that is what stops a caller minting someone
-- else's badge, and it is the core difference from the old scheme.
CREATE OR REPLACE FUNCTION public.issue_vr_id_token()
RETURNS TABLE(uid uuid, vrid text, exp bigint)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid    uuid := auth.uid();
  v_secret text;
  v_minute text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING errcode = '42501';
  END IF;

  SELECT s.value INTO v_secret FROM private.app_secrets s WHERE s.name = 'vr_id_hmac';
  IF v_secret IS NULL THEN
    RAISE EXCEPTION 'VR-ID signing secret is not configured';
  END IF;

  -- Same minute-bucket rotation the UI already assumes (a fresh QR each
  -- minute, with the verifier accepting the previous bucket too so a scan
  -- straddling the boundary still works).
  v_minute := floor(extract(epoch FROM now()) / 60)::bigint::text;

  RETURN QUERY SELECT
    v_uid,
    substring(encode(extensions.hmac(v_uid::text || ':' || v_minute, v_secret, 'sha256'), 'hex') FROM 1 FOR 32),
    ((extract(epoch FROM now()) * 1000)::bigint + 65000);
END;
$function$;


CREATE OR REPLACE FUNCTION public.verify_vr_id_scan(p_uid uuid, p_vrid text, p_exp bigint)
RETURNS TABLE(id text, full_name text, university_id text, student_id text, department text,
              semester integer, role text, avatar_url text, batch_label text, section text,
              cgpa numeric, designation text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_now_ms       bigint := (extract(epoch FROM now()) * 1000)::bigint;
  v_minute_now   text   := floor(extract(epoch FROM now()) / 60)::bigint::text;
  v_minute_prev  text   := (floor(extract(epoch FROM now()) / 60)::bigint - 1)::text;
  v_secret       text;
  v_expected_now  text;
  v_expected_prev text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING errcode = '42501';
  END IF;

  IF p_exp <= v_now_ms THEN
    RAISE EXCEPTION 'QR expired';
  END IF;

  SELECT s.value INTO v_secret FROM private.app_secrets s WHERE s.name = 'vr_id_hmac';
  IF v_secret IS NULL THEN
    RAISE EXCEPTION 'VR-ID signing secret is not configured';
  END IF;

  v_expected_now  := substring(encode(extensions.hmac(p_uid::text || ':' || v_minute_now,  v_secret, 'sha256'), 'hex') FROM 1 FOR 32);
  v_expected_prev := substring(encode(extensions.hmac(p_uid::text || ':' || v_minute_prev, v_secret, 'sha256'), 'hex') FROM 1 FOR 32);

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
$function$;

-- Same ACL discipline as 20260721194633/20260725130000: revoke from PUBLIC
-- (which is what actually reaches anon), then grant only `authenticated`.
REVOKE ALL ON FUNCTION public.issue_vr_id_token() FROM public, anon;
REVOKE ALL ON FUNCTION public.verify_vr_id_scan(uuid, text, bigint) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.issue_vr_id_token() TO authenticated;
GRANT EXECUTE ON FUNCTION public.verify_vr_id_scan(uuid, text, bigint) TO authenticated;
