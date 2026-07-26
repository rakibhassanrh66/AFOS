-- =====================================================================
--  AFOS — Auto-confirm new accounts so they can sign in immediately
--  after registration, without waiting on the email confirmation link
--  (Supabase's built-in email sender is unreliable on this project's
--  free tier, so gating sign-in on it blocks real users).
-- =====================================================================

CREATE OR REPLACE FUNCTION auto_confirm_email()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  NEW.email_confirmed_at := COALESCE(NEW.email_confirmed_at, now());
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS auto_confirm_email_trigger ON auth.users;
CREATE TRIGGER auto_confirm_email_trigger
  BEFORE INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION auto_confirm_email();

-- Also confirm any existing accounts stuck pending confirmation.
UPDATE auth.users SET email_confirmed_at = now() WHERE email_confirmed_at IS NULL;
