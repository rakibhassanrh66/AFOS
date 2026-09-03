-- A standing assertion for the OTHER half of the definer-ACL problem.
--
-- audit_definer_acls() (20260725071319) asks "is any SECURITY DEFINER function
-- reachable by anon?" and has caught three regressions. It says nothing about
-- `authenticated`, and that is where the real hole was: consume_rate_limit was
-- EXECUTE-able by every signed-in student, and its bucket key
-- ('email_provider_resend_daily','global') is a constant published in this
-- repository, so one POST with cost 100 emptied the day's mail budget for the
-- whole university.
--
-- A blanket "no definer function may be authenticated-executable" rule is
-- useless here -- 60 of them are meant to be, that is how the app works. So
-- this is a named list instead: the functions that ONLY the service role (or
-- another definer function running as its owner) has any business calling.
-- Same shape as definer_acl_allowlist: a reason is required, so adding one is
-- an argument, not a checkbox.

create table if not exists public.service_role_only_functions (
  function_signature text primary key,
  reason             text not null,
  added_at           timestamptz not null default now()
);

alter table public.service_role_only_functions enable row level security;
-- No policies: service-role reads only, like every other table in this family.

comment on table public.service_role_only_functions is
  'Functions that must never be EXECUTE-able by anon or authenticated. Asserted in CI by audit_service_role_only_acls().';

insert into public.service_role_only_functions (function_signature, reason) values
  ('public.consume_rate_limit(text,text,numeric)',
   'Caller-supplied bucket, key and cost. The daily mail bucket key is the constant ''global'' and is public in this repo, so one authenticated call with cost 100 drains the whole university''s daily mail allowance; the per-address buckets are keyed by plain email, so the same call locks one named person out of registration and password reset.'),
  ('public.mail_budget_status()',
   'Tells the caller how much mail allowance is left, i.e. when the drain above is worth attempting and whether it landed.'),
  ('public.mail_check_and_alert()',
   'Writes mail_capacity_alerts and pushes a notification to every super_admin and every holder of users:approve.'),
  ('public.audit_notification_audiences()',
   'CI audit helper. Enumerates internal trigger function names and their defects; CI calls it with the service-role key.')
on conflict (function_signature) do update set reason = excluded.reason;

create or replace function public.audit_service_role_only_acls()
returns table (function_signature text, granted_to text)
language sql
security definer
set search_path = public, pg_catalog
as $$
  select s.function_signature,
         string_agg(r.rolname, ', ' order by r.rolname)
  from public.service_role_only_functions s
  cross join lateral (values ('anon'), ('authenticated')) as r(rolname)
  where to_regprocedure(s.function_signature) is not null
    and has_function_privilege(r.rolname, to_regprocedure(s.function_signature), 'EXECUTE')
  group by s.function_signature;
$$;

revoke execute on function public.audit_service_role_only_acls() from public, anon, authenticated;
grant execute on function public.audit_service_role_only_acls() to service_role;
