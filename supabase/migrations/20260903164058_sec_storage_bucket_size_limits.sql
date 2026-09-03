-- Three buckets had NO server-side size limit at all.
--
-- assignment-submissions is the one that matters: the storage policy lets any
-- authenticated user INSERT into their own folder, and the only thing standing
-- between that and an unbounded upload was a constant in the Flutter picker --
-- `_briefMaxBytes = 25 * 1024 * 1024` in assignments_screen.dart:136. A client
-- constant is not a limit; anyone with a session and curl ignores it, and
-- storage is billed by the gigabyte. SECURITY.md says a client-side check that
-- is the ONLY thing preventing an action is a finding, and this was one.
--
-- 25 MB is the app's own number, so nothing a student can legitimately submit
-- today starts failing.
update storage.buckets set file_size_limit = 26214400 where id = 'assignment-submissions';

-- Admin-gated (can_manage_uploads()), so this is a runaway guard rather than
-- an abuse control. Generous, because a term's backup payload is not small.
update storage.buckets set file_size_limit = 104857600 where id = 'upload-backups';

-- DELIBERATELY NOT RESTRICTING MIME TYPES ANYWHERE HERE.
--
-- assignment-submissions: the picker already limits extensions to pdf/doc/
-- docx/png/jpg/jpeg/zip/txt, and the bucket is private with per-user folders,
-- so it is not a useful hosting vector. A MIME allowlist would add nothing
-- and could reject a real submission at a deadline over a content-type
-- sniffing quirk (.doc in particular arrives as application/octet-stream from
-- some clients).
--
-- sos-voice: safety-critical and already capped at 10 MB. Mobile uploads .m4a,
-- web uploads .webm, and neither sets an explicit content type -- a rejected
-- upload here means a real emergency recording is lost, which is far worse
-- than an unexpected file type in a private, per-user, 10 MB-capped bucket.
