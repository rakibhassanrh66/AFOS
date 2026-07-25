-- =====================================================================
--  AFOS — Declare the sos-voice storage bucket.
--
--  THIS IS A BUG FIX, NOT JUST HYGIENE. The audit listed this as "bucket
--  exists but has no migration". It does not exist at all: the project has
--  only avatars, feedback-attachments, lost-found and vr-id-verifications.
--  sos_floating_button.dart:122 uploads every SOS voice note to
--  storage.from('sos-voice') and swallows the failure in a bare `catch (_)`
--  two lines later, so the upload has ALWAYS failed silently, voice_path has
--  always been null, and the "Play voice note" button in
--  sos_alert_detail_screen has never had anything to play. Nobody would have
--  seen an error.
--
--  MIME TYPES ARE DELIBERATELY UNRESTRICTED. The client calls uploadBinary()
--  without FileOptions, so it does not set a Content-Type. An allowlist here
--  would reject those uploads and silently re-break the feature in exactly
--  the way this migration exists to fix. The size cap still bounds abuse,
--  and the INSERT policy still confines each user to their own folder.
-- =====================================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES ('sos-voice', 'sos-voice', false, 10485760)
ON CONFLICT (id) DO UPDATE
  SET public = false, file_size_limit = 10485760;

-- Upload: only into a folder named after your own uid, matching the
-- '<uid>/<timestamp>.<ext>' path the client builds.
DROP POLICY IF EXISTS "upload_own_sos_voice" ON storage.objects;
CREATE POLICY "upload_own_sos_voice" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'sos-voice'
    AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
  );

-- Read: whoever may see the ALERT may hear its voice note.
--
-- The EXISTS subquery reads sos_alerts as the calling user, so sos_alerts'
-- own RLS (owner / admin+staff / within 5km with location sharing on /
-- actually notified about it) filters it. That means this policy cannot
-- drift from the alert visibility rules -- it has no copy of them to drift
-- from -- and a future change to who can see an alert automatically applies
-- to the audio too.
DROP POLICY IF EXISTS "read_sos_voice_for_visible_alerts" ON storage.objects;
CREATE POLICY "read_sos_voice_for_visible_alerts" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'sos-voice'
    AND (
      (storage.foldername(name))[1] = (SELECT auth.uid())::text
      OR EXISTS (SELECT 1 FROM sos_alerts a WHERE a.voice_path = storage.objects.name)
    )
  );

-- Cleanup: the uploader, or an SOS admin, may remove a recording.
DROP POLICY IF EXISTS "delete_own_or_admin_sos_voice" ON storage.objects;
CREATE POLICY "delete_own_or_admin_sos_voice" ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'sos-voice'
    AND (
      (storage.foldername(name))[1] = (SELECT auth.uid())::text
      OR get_my_profile_role() = ANY (ARRAY['admin','super_admin','staff'])
      OR caller_can('sos','manage')
    )
  );
