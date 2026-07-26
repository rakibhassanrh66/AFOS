-- =====================================================================
--  AFOS — Restore the DIU-only email restriction, scoped correctly this
--  time and with the allowlist actually populated.
--
--  The original enforce_email_domain trigger (20260702130000) was
--  dropped entirely in 20260703030000 because its allowlist only had
--  one row (rakibhassan.rh68@gmail.com), so every QA/tester account
--  using a normal email got a generic "Database error saving new user"
--  500 with no indication why. Since then app_config.dart grew a
--  5-entry AppConfig.emailDomainAllowlist that documents itself as
--  "mirrors ... auth_email_domain_allowlist" but the DB table was never
--  actually updated to match — restoring the trigger without fixing
--  that first would reproduce the exact bug that got it dropped.
--
--  Also tightens the domain check itself: the original used
--  `email NOT ILIKE '%edu.bd'`, which matches anything ending in the
--  literal string "edu.bd" with no boundary -- "fake-edu.bd" or a
--  different university's "buet.edu.bd" both would have passed. Checked
--  live: every real account in profiles is on diu.edu.bd (plus the
--  known test/admin domains), so restricting to that exact domain
--  (with a proper '@' boundary) doesn't lock out anyone real.
-- =====================================================================

INSERT INTO auth_email_domain_allowlist (email) VALUES
  ('rakibhassan.rh68@gmail.com'),
  ('qa_student@afos.test'),
  ('qa_teacher@afos.test'),
  ('qa_staff@afos.test'),
  ('rakibhassan.rh68+qaadmin@gmail.com'),
  ('rakibhassan.rh68+qasuperadmin@gmail.com')
ON CONFLICT (email) DO NOTHING;

CREATE OR REPLACE FUNCTION enforce_email_domain()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NEW.email NOT ILIKE '%@diu.edu.bd' AND NOT EXISTS (
    SELECT 1 FROM auth_email_domain_allowlist WHERE email = NEW.email
  ) THEN
    RAISE EXCEPTION 'Registration is restricted to DIU (@diu.edu.bd) email addresses.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_email_domain_trigger ON auth.users;
CREATE TRIGGER enforce_email_domain_trigger
  BEFORE INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION enforce_email_domain();
