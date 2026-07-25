"""Fails CI if any SECURITY DEFINER function in `public` is executable by
`anon` without being explicitly allowlisted.

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

    req = urllib.request.Request(
        f"{SUPABASE_URL}/rest/v1/rpc/audit_definer_acls",
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
            offenders = json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        # Unlike record_release.py, a failure here IS fatal: this is a
        # security assertion, and "we couldn't tell" must not read as "fine".
        print(f"::error::definer-ACL audit could not run ({e.code}): {e.read().decode()}")
        sys.exit(1)

    if not offenders:
        print("definer-ACL audit clean: no SECURITY DEFINER function is anon-executable.")
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
