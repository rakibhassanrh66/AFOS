"""Fails CI if a notification's in-app audience and its push audience can drift.

WHY THIS CHECK EXISTS. Almost every notification in this app is written twice: a
database trigger inserts the durable `user_notifications` row, and the Flutter
client sends the OneSignal banner — because the OneSignal REST key lives in an
edge function's environment, not in the database. Two implementations of one
rule is exactly the shape that rots, and it already had, twice, without anyone
noticing:

  * offering submitted — the trigger scoped `dept_admin` to the offering's own
    department; the client pushed to EVERY dept_admin in the university.
  * results submitted — the trigger included a scoped `dept_admin`; the client
    omitted dept_admin from the push entirely, so they would have received the
    in-app row and never a banner.

Neither was visible on this project because it currently has no dept_admin at
all, so a test that counted recipients passed while the rule was wrong. That is
the trap: counting is not enough, the two sides have to resolve through the
SAME definition.

The rule enforced is structural, which is what makes it cheap and reliable: a
trigger that writes user_notifications must not carry its own hardcoded role
membership test. If it needs a role-based audience it calls one of the shared
audience functions (offering_reviewer_audience / offering_section_audience),
which the client also calls over RPC — so both sides read one definition and
cannot disagree. Single-recipient triggers ("tell this student") have no role
list and are not flagged.

ONE TRIGGER IS EXEMPT BY CONSTRUCTION. notify_new_release() sends its own push
rather than leaving it to the client, via pg_net -> the announce-release edge
function (see 20260804180927). It cannot drift: its in-app audience is "every
profile" with no role test at all, and announce-release resolves its push
audience from that same table. There is no second definition to disagree with.

Mirrors check_definer_acls.py: the audit itself runs server-side in
audit_notification_audiences() and is reached over PostgREST with the
service-role key CI already holds, so no raw database credentials are needed.

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
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    if not key:
        # Matches check_definer_acls.py: a missing secret on a fork PR must not
        # look like a passing audit, but it must not fail the build either.
        print("SUPABASE_SERVICE_ROLE_KEY not set - skipping audience audit.")
        sys.exit(0)

    req = urllib.request.Request(
        f"{SUPABASE_URL}/rest/v1/rpc/audit_notification_audiences",
        data=b"{}",
        method="POST",
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
        },
    )

    try:
        with urllib.request.urlopen(req) as resp:
            rows = json.load(resp)
    except urllib.error.HTTPError as e:
        print(f"::error::Audience audit request failed: {e.code} {e.read().decode()}")
        sys.exit(1)

    if not rows:
        print("Notification audiences OK - no trigger carries its own role list.")
        sys.exit(0)

    print("::error::Notification in-app and push audiences can drift apart.")
    for r in rows:
        print(f"::error::  {r['function_name']}: {r['problem']}")
    print(
        "::error::Route the audience through offering_reviewer_audience() or "
        "offering_section_audience() and have the client call the same RPC."
    )
    sys.exit(1)


if __name__ == "__main__":
    main()
