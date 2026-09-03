-- Four SECURITY DEFINER functions that only the service role has any business
-- calling were EXECUTE-able by `authenticated`, i.e. by any signed-in student
-- over PostgREST.
--
-- THE ONE THAT MATTERED: consume_rate_limit(bucket, key, cost).
-- The daily mail allowance is modelled as a token bucket keyed
-- ('email_provider_resend_daily', 'global') -- mailer.ts:203, a constant, and
-- this repository is public. Both arguments and the cost are caller-supplied
-- and unbounded, so a single authenticated POST to
-- /rest/v1/rpc/consume_rate_limit with cost 100 empties the entire day's mail
-- budget: no verification code, no password reset for anybody until it refills
-- at 0.069 tokens/minute (~24h). The per-address buckets (email_verify_addr,
-- registration_review_request) are keyed by the PLAIN email address, so the
-- same call locks one named person out of registration or account recovery.
--
-- Verified before applying, as `authenticated`:
--   select consume_rate_limit('email_provider_resend_daily','global',0) -> true
-- And after:
--   ERROR 42501: permission denied for function consume_rate_limit
--
-- Nothing legitimate loses access. The edge functions call it with the service
-- role. The three in-database callers -- enforce_rate_limit_course_message,
-- enforce_rate_limit_enrollment, enforce_rate_limit_offering -- are all
-- SECURITY DEFINER triggers owned by postgres, so they do not need the
-- caller's grant. No RLS policy references it (0 of them), and no Dart code
-- calls it.
revoke execute on function public.consume_rate_limit(text, text, numeric) from anon, authenticated;

-- Reports how much of today's mail allowance is left. Read-only, but it tells
-- an attacker exactly when the budget is worth attacking and when the drain
-- above has landed. Only mail_check_and_alert (definer, same owner) calls it.
revoke execute on function public.mail_budget_status() from anon, authenticated;

-- Writes mail_capacity_alerts and pushes a notification to every super_admin
-- and every holder of users:approve. Any signed-in user could fire the
-- "Email sending has stopped" alarm at the whole approver set. Called only by
-- password-reset, with the service role.
revoke execute on function public.mail_check_and_alert() from anon, authenticated;

-- A CI audit helper that enumerates internal trigger function names and their
-- defects. check_notification_audiences.py calls it with the SERVICE ROLE key,
-- so CI is unaffected.
revoke execute on function public.audit_notification_audiences() from anon, authenticated;
