"""Writes the in-app "What's New" row (Supabase `app_releases` table) for the
tag currently being released. Run only from the `release` job in
.github/workflows/main.yml, after the GitHub Release itself has already
been published successfully — see that workflow for why (a failed build
must never produce a What's New entry for a release that doesn't exist).

Requires env vars:
  GITHUB_REF_NAME          - set automatically by GitHub Actions (the tag, e.g. "v2.3.10")
  SUPABASE_SERVICE_ROLE_KEY - set by the workflow step from the repo secret

A failure here is reported as a workflow warning, not a failure: the GitHub
Release is the source of truth for whether this version actually shipped,
and this script only mirrors a summary of it into the app's own database.
"""
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request

SUPABASE_URL = "https://dtsptjallznnvattadlu.supabase.co"


def git_output(*args: str) -> str:
    result = subprocess.run(
        ["git", *args], capture_output=True, text=True, check=False
    )
    return result.stdout.strip()


def main() -> None:
    tag = os.environ["GITHUB_REF_NAME"]  # e.g. "v2.3.10"
    version = re.sub(r"^v", "", tag)  # -> "2.3.10", matches AppConfig.appVersion

    # Previous tag reachable from this commit's parent, if any — defines the
    # commit range used for "what changed" highlights. The repo's first-ever
    # tag has no predecessor, and that's fine: falls back to the last few
    # commits instead of a range.
    prev_tag = git_output("describe", "--tags", "--abbrev=0", "HEAD^")

    if prev_tag:
        log = git_output("log", "--no-merges", "--pretty=%s", f"{prev_tag}..HEAD")
    else:
        log = git_output("log", "--no-merges", "--pretty=%s", "-12")
    subjects = [line for line in log.splitlines() if line.strip()]

    # "chore: bump version" commits are noise for a user-facing What's New
    # list, not a real change — drop them, then cap at 10 lines so one
    # release with an unusually long history doesn't produce a wall of text
    # in the app.
    highlights = [s for s in subjects if "bump version" not in s.lower()][:10]
    if not highlights:
        highlights = [f"AFOS {version} released."]

    release_date = git_output("log", "-1", "--format=%cs")  # "%cs" = committer date, YYYY-MM-DD

    payload = json.dumps(
        {
            "version": version,
            "release_date": release_date,
            "title": f"AFOS {version}",
            "highlights": highlights,
            "platforms": ["android"],
        }
    ).encode()

    service_key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
    req = urllib.request.Request(
        f"{SUPABASE_URL}/rest/v1/app_releases",
        data=payload,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "apikey": service_key,
            "Authorization": f"Bearer {service_key}",
            "Prefer": "return=minimal",
        },
    )
    try:
        urllib.request.urlopen(req)
        print(f"app_releases row inserted for {version}: {highlights}")
    except urllib.error.HTTPError as e:
        print(f"::warning::app_releases insert failed ({e.code}): {e.read().decode()}")
        sys.exit(0)  # best-effort — never fail the release job over this


if __name__ == "__main__":
    main()
