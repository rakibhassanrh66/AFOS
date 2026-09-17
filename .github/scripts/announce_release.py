#!/usr/bin/env python3
"""Insert one row into app_releases, so the in-app updater offers a release.

Driven only by .github/workflows/announce-release.yml, which is
workflow_dispatch-only. Every value here is typed by a person; nothing is
derived from commits. See that workflow's header for why that distinction
matters.

WHAT THE ROW ACTUALLY DOES. AppUpdateService reads the newest app_releases row
and compares it to the installed version; with no row, "Check for Updates"
correctly reports nothing, because as far as the database is concerned nothing
newer exists. The insert also fires notify_new_release(), which writes the
durable in-app notification for every profile and calls the announce-release
edge function for push. So this one statement is the entire difference between
a published APK and a user being told about it.
"""

import json
import os
import re
import sys
import urllib.error
import urllib.request

PROJECT_URL = "https://dtsptjallznnvattadlu.supabase.co"


def fail(msg):
    print("FAILED: %s" % msg, file=sys.stderr)
    sys.exit(1)


key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
if not key:
    fail("SUPABASE_SERVICE_ROLE_KEY is not set")

version = os.environ["VERSION"].strip()
release_date = os.environ["RELEASE_DATE"].strip()
title = os.environ["TITLE"].strip()
platforms = [p.strip() for p in os.environ["PLATFORMS"].split(",") if p.strip()]
highlights = [h.strip() for h in os.environ["HIGHLIGHTS"].splitlines() if h.strip()]

# A '+build' suffix in this column is the single most repeated mistake against
# this table -- six rows already in it carry one. It breaks BOTH things the
# column feeds: the download URL becomes .../v2.3.2+21/AFOS-v2.3.2+21.apk, which
# is a 404, and the version compare splits on '.' so the last segment parses as
# 0, making 2.3.2+21 compare as 2.3.0 -- OLDER than the release it describes.
if "+" in version:
    fail("version must not carry a +build suffix: got %r" % version)
if not re.fullmatch(r"\d+\.\d+\.\d+", version):
    fail("version must look like 2.14.0: got %r" % version)
if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", release_date):
    fail("release_date must be YYYY-MM-DD: got %r" % release_date)
if not highlights:
    fail("at least one highlight is required")
for p in platforms:
    if p not in ("android", "web", "ios"):
        fail("unknown platform %r" % p)

headers = {
    "apikey": key,
    "Authorization": "Bearer %s" % key,
    "Content-Type": "application/json",
}


def request(method, path, body=None, extra=None):
    req = urllib.request.Request(
        PROJECT_URL + path, method=method,
        data=json.dumps(body).encode() if body is not None else None)
    for k, v in list(headers.items()) + list((extra or {}).items()):
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read().decode()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        fail("%s %s -> %s %s" % (method, path, e.code, e.read().decode()[:400]))


# Idempotent by intent: app_releases has a unique index on version, so a second
# run would be a 409. Checking first turns that into a clear message instead of
# a stack trace, and makes a re-run after a partial failure safe.
existing = request(
    "GET", "/rest/v1/app_releases?select=version&version=eq.%s" % version)
if existing:
    print("Row for %s already exists. Nothing to do." % version)
    sys.exit(0)

request("POST", "/rest/v1/app_releases", {
    "version": version,
    "release_date": release_date,
    "title": title,
    "highlights": highlights,
    "platforms": platforms,
}, extra={"Prefer": "return=minimal"})

# Read it back and, more importantly, confirm it is the row the app will now
# resolve -- inserting a row that is not the newest announces nothing.
newest = request(
    "GET",
    "/rest/v1/app_releases?select=version,title,release_date"
    "&order=release_date.desc,created_at.desc&limit=1")
if not newest or newest[0]["version"] != version:
    fail("inserted %s but the newest row is %r -- the app will not offer it"
         % (version, newest))

print("Inserted and verified newest: %s - %s (%s)"
      % (newest[0]["version"], newest[0]["title"], newest[0]["release_date"]))
for h in highlights:
    print("  - %s" % h)
