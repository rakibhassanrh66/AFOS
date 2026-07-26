-- =====================================================================
--  AFOS — Give the SOS bucket a burst allowance before trigger-sos-alert
--  switches from its hardcoded window to this policy.
--
--  The function's old rule was "reject if this user already has an ACTIVE
--  alert created in the last 5 minutes" -- so an alert that had been
--  RESOLVED did not block a new one. A plain 1-token/5-minute bucket is
--  stricter than that: it would also block someone whose first emergency
--  was resolved and who then needs help again.
--
--  Capacity 2 keeps the sustained rate identical to the old behaviour
--  (refill 0.2/min = one alert per 5 minutes) while leaving one spare
--  token so a genuine second emergency is never swallowed. This is a
--  safety feature; the failure mode of being slightly too permissive is
--  much cheaper than the failure mode of being too strict.
-- =====================================================================

UPDATE rate_limit_policies
   SET capacity = 2,
       description = 'SOS alerts per user (sustained ~1 per 5 min, burst of 2)',
       updated_at = now()
 WHERE bucket = 'sos_alert';

INSERT INTO rate_limit_policies (bucket, capacity, refill_per_minute, description) VALUES
  ('routine_upload', 5, 0.5, 'Routine/exam/transport PDF uploads per user')
ON CONFLICT (bucket) DO NOTHING;
