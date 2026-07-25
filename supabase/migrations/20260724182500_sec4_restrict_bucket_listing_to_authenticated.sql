-- Both buckets are public=true, so actual file downloads go through the
-- public CDN object endpoint and never touch this RLS at all -- narrowing
-- who can SELECT the storage.objects rows only closes the ability to
-- LIST every filename in the bucket (storage.from(bucket).list()), which
-- was open to anon. ALTER POLICY (not drop+recreate) preserves the USING
-- expression and leaves no unprotected window, same approach as SEC-5's
-- earlier exam_room_allocations/halls fix this session.
alter policy avatars_public_read on storage.objects to authenticated;
alter policy lost_found_public_read on storage.objects to authenticated;
