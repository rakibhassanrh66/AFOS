-- schedule_screen.dart's "only my batch+section" class-routine filter reads
-- profiles.batch/profiles.section, but the required onboarding flow
-- (complete_profile_screen.dart) only ever wrote students.batch_label/section
-- — profiles.batch/section were only ever set via the separate, easy-to-miss
-- "Routine Info" fields in Settings. Fixed going forward by having onboarding
-- write both; this backfills every existing student whose profiles.batch is
-- still empty so their personalized routine works without them having to
-- rediscover and re-fill the Settings fields.
UPDATE profiles p
SET batch = s.batch_label, section = s.section
FROM students s
WHERE s.profile_id = p.id
  AND p.batch IS NULL
  AND s.batch_label IS NOT NULL;
