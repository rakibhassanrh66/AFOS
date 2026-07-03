-- =====================================================================
--  AFOS — Remove edu.bd email domain restriction for testing
--  The enforce_email_domain trigger blocked every signup whose email
--  wasn't @...edu.bd or in a one-row allowlist, causing GoTrue to
--  return a generic "Database error saving new user" 500 for any
--  tester using a normal email address. Drop the restriction so
--  anyone can register during testing.
-- =====================================================================

DROP TRIGGER IF EXISTS enforce_email_domain_trigger ON auth.users;
DROP FUNCTION IF EXISTS enforce_email_domain();
