"""Fails CI if any SECURITY DEFINER function in `public` is executable by
`anon` without being explicitly allowlisted, or if a function on the
service-role-only list is executable by `anon` or `authenticated`.

WHY THIS CHECK EXISTS. `CREATE FUNCTION` grants EXECUTE to PUBLIC by default,
so every new SECURITY DEFINER RPC is reachable by anonymous callers unless the
author remembers to REVOKE it. Those functions bypass RLS by definition, so
forgetting is a real data-exposure bug rather than a style nit — and it has
already happened three separate times in this project (migrations
20260721194633, 20260721200547 and 20260725071319 are all cleanups of exactly
this). Code review kept missing it; this does not.

The check runs entirely server-side in `audit_definer_acls()` (see
sec_definer_acl_audit_and_allowlist) and is reached over PostgREST with the
service-role key CI already holds, so no raw database credentials are needed.

To allow a genuine exception, insert into `definer_acl_allowlist` with a
reason — the reason is required, so an exception has to be justified in the
database rather than silently added here.

Requires env vars:
  SUPABASE_SERVICE_ROLE_KEY - set by the workflow step from the repo secret
"""
import json
import os
import sys
import urllib.error
import urllib.request

SUPABASE_URL = "https://dtsptjallznnvattadlu.supabase.co"


def main() -> None:
    service_key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    if not service_key:
        # Secrets are not exposed to pull_request runs from forks, so a
        # missing key means "cannot check here", not "check failed".
        print("::warning::SUPABASE_SERVICE_ROLE_KEY not set, skipping definer-ACL audit.")
        sys.exit(0)

    def audit(fn):
        req = urllib.request.Request(
            f"{SUPABASE_URL}/rest/v1/rpc/{fn}",
            data=b"{}",
            method="POST",
            headers={
                "Content-Type": "application/json",
                "apikey": service_key,
                "Authorization": f"Bearer {service_key}",
            },
        )
        try:
            with urllib.request.urlopen(req) as resp:
                return json.loads(resp.read().decode())
        except urllib.error.HTTPError as e:
            # A failure here IS fatal: this is a security assertion, and
            # "we couldn't tell" must not read as "fine".
            print(f"::error::{fn} could not run ({e.code}): {e.read().decode()}")
            sys.exit(1)

    offenders = audit("audit_definer_acls")

    # SECOND ASSERTION: the service-role-only list.
    #
    # The anon check above says nothing about `authenticated`, and that is
    # where the hole actually was. consume_rate_limit(bucket, key, cost) was
    # executable by every signed-in student; its daily-mail bucket key is the
    # constant 'global', published in this repository, so one POST with cost
    # 100 emptied the university's mail allowance for the day -- no
    # verification codes, no password resets, until it refilled ~24h later.
    # See migration 20260903162048.
    service_only = audit("audit_service_role_only_acls")
    if service_only:
        print("::error::Functions reserved for the service role are reachable by ordinary callers:")
        for row in service_only:
            print(f"::error::  {row.get('function_signature')} - granted to {row.get('granted_to')}")
        print("::error::Fix with:  REVOKE EXECUTE ON FUNCTION public.<fn> FROM anon, authenticated;")
        print("::error::or, if a caller genuinely needs it, delete the row from service_role_only_functions and say why in the commit.")
        sys.exit(1)

    if not offenders:
        print("definer-ACL audit clean: no SECURITY DEFINER function is anon-executable,")
        print("and every service-role-only function is unreachable by anon and authenticated.")
        return

    print("::error::SECURITY DEFINER functions are executable by `anon`:")
    for row in offenders:
        sig = row.get("function_signature")
        default_grant = row.get("relies_on_default_public_grant")
        why = (
            "never revoked after CREATE (still has the default PUBLIC grant)"
            if default_grant
            else "explicitly granted"
        )
        print(f"::error::  {sig} - {why}")
    print("::error::Fix with:  REVOKE ALL ON FUNCTION public.<fn> FROM public, anon;")
    print("::error::or, if the exposure is intentional, add it to definer_acl_allowlist with a reason.")
    sys.exit(1)


if __name__ == "__main__":
    main()
