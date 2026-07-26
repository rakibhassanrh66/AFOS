-- =====================================================================
--  AFOS — Move image uploads from third-party imgBB to Supabase Storage
--
--  Confirmed: no storage buckets existed at all; avatar photos and lost &
--  found item photos were uploaded to a hardcoded third-party imgBB API
--  key from the client. Per requirements, images must live in Supabase
--  Storage with only the URL/metadata in Postgres.
--
--  Path convention: {bucket}/{auth.uid()}/{filename} — RLS restricts
--  writes to the caller's own folder; both buckets are public-read since
--  avatars and lost&found photos are shown across the app (dept chat,
--  mentorship, the lost & found feed) the same way the imgBB URLs were.
-- =====================================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
  ('avatars', 'avatars', true, 5242880, ARRAY['image/jpeg','image/png','image/webp']),
  ('lost-found', 'lost-found', true, 5242880, ARRAY['image/jpeg','image/png','image/webp'])
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "avatars_public_read" ON storage.objects FOR SELECT
  USING (bucket_id = 'avatars');

CREATE POLICY "avatars_own_write" ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY "avatars_own_update" ON storage.objects FOR UPDATE
  USING (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY "avatars_own_delete" ON storage.objects FOR DELETE
  USING (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY "lost_found_public_read" ON storage.objects FOR SELECT
  USING (bucket_id = 'lost-found');

CREATE POLICY "lost_found_own_write" ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'lost-found' AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY "lost_found_own_update" ON storage.objects FOR UPDATE
  USING (bucket_id = 'lost-found' AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY "lost_found_own_delete" ON storage.objects FOR DELETE
  USING (bucket_id = 'lost-found' AND (storage.foldername(name))[1] = auth.uid()::text);
