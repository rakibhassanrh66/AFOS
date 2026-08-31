"""Fails CI if Dart code names a Postgres column that does not exist.

WHY THIS CHECK EXISTS. It has now cost this project twice, both times silently:

  * `profile_inspection_screen.dart` selected `profiles.designation`. There is
    no such column, and PostgREST rejects the WHOLE select when one name is
    unknown (42703) -- so the screen rendered its error state on every single
    open and listed nobody, for as long as it shipped. Nothing pointed at the
    column; the error just said the request failed.

  * `upload_backup_pdf.dart` asked schedule_slots for `course_code`,
    `course_title` and `room` (really `subject_code`, `subject`,
    `room_number`), and transport for `start_point`/`end_point`/`arrival_time`
    (two of which do not exist at all). That file drops any column no row
    carries a value for, so the misnamed ones did not render blank -- they
    VANISHED. The backup PDF a person restores from after deleting an upload
    printed a class routine with no course and no room, and looked complete.

Both were written on the belief that a column existed. Reviews did not catch
either. This does.

WHAT IT CHECKS. Two shapes, because the second bug was invisible to a checker
that only understood the first:
  1. `.from('t').select('a, b, c')` -- column lists sent to PostgREST.
  2. the `_columns` map in upload_backup_pdf.dart -- column names used to
     render a document rather than to query.

Comments are stripped BEFORE matching. This repo writes comments BETWEEN the
concatenated string pieces of a select list, and an early version of this
parser that only tolerated whitespace there matched ZERO selects in the very
file carrying the bug while reporting "all clean". The self-test below pins
that case so it cannot come back.

The live schema comes from PostgREST's own OpenAPI document (GET /rest/v1/),
which lists every exposed table and its properties -- no new RPC and no raw
database credentials.

Requires env vars:
  SUPABASE_SERVICE_ROLE_KEY - set by the workflow step from the repo secret
"""
import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

SUPABASE_URL = "https://dtsptjallznnvattadlu.supabase.co"
LIB = Path(__file__).resolve().parents[2] / "lib"


# ---------------------------------------------------------------- dart parsing
def strip_comments(src: str) -> str:
    """Blank // and /* */ comments, keeping string literals intact.

    The select list IS a string literal here, so unlike the row-starve guard
    this must NOT blank strings.
    """
    out, i, n = [], 0, len(src)
    while i < n:
        two = src[i:i + 2]
        if two == "//":
            while i < n and src[i] != "\n":
                out.append(" ")
                i += 1
            continue
        if two == "/*":
            while i < n and src[i:i + 2] != "*/":
                out.append("\n" if src[i] == "\n" else " ")
                i += 1
            i += 2
            out.append("  ")
            continue
        if src[i] == "'":
            out.append(src[i])
            i += 1
            while i < n and src[i] != "'":
                if src[i] == "\\":
                    out.append(src[i])
                    i += 1
                    if i < n:
                        out.append(src[i])
                        i += 1
                    continue
                out.append(src[i])
                i += 1
            if i < n:
                out.append(src[i])
                i += 1
            continue
        out.append(src[i])
        i += 1
    return "".join(out)


SELECT_RE = re.compile(
    r"\.from\(\s*'([a-z_0-9]+)'\s*\)\s*(?:\.\w+\([^()]*\)\s*)*?"
    r"\.select\(\s*((?:'[^']*'\s*)+)\)",
    re.S,
)


def split_top_level(sel: str):
    """Split a select list on top-level commas, keeping embeds intact."""
    parts, depth, buf = [], 0, ""
    for ch in sel:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append(buf)
            buf = ""
        else:
            buf += ch
    parts.append(buf)
    return parts


def plain_columns(sel: str):
    """Bare column names from a select list: no embeds, no '*', no casts."""
    for p in split_top_level(sel):
        p = p.strip()
        if not p or p == "*" or "(" in p:
            continue
        if ":" in p:                       # alias:column
            p = p.split(":", 1)[1].strip()
        p = p.split("::")[0].strip().rstrip("!").strip()
        if p and p != "*" and re.fullmatch(r"[a-z_0-9]+", p):
            yield p


def selects_in(src: str):
    """Yield (table, [columns]) for every .select() in one file's source."""
    for m in SELECT_RE.finditer(strip_comments(src)):
        sel = "".join(re.findall(r"'([^']*)'", m.group(2)))
        yield m.group(1), list(plain_columns(sel))


COLMAP_RE = re.compile(r"'([a-z_0-9]+)'\s*:\s*\[([^\]]*)\]", re.S)


def backup_pdf_columns(src: str):
    """Yield (table, [columns]) from upload_backup_pdf.dart's _columns map."""
    src = strip_comments(src)
    m = re.search(r"_columns\s*=\s*<String,\s*List<String>>\{(.*?)\n  \};", src, re.S)
    if not m:
        return
    for entry in COLMAP_RE.finditer(m.group(1)):
        cols = re.findall(r"'([a-z_0-9]+)'", entry.group(2))
        yield entry.group(1), cols


# ------------------------------------------------------------------- self-test
def _selftest():
    commented = (
        ".from('profiles')\n.select('id, full_name, '\n"
        "// a comment sitting between the string pieces\n"
        "'designation, is_verified')\n"
    )
    got = list(selects_in(commented))
    assert got and "designation" in got[0][1], (
        "SELFTEST FAILED: cannot see a column in a select whose pieces are "
        "separated by a comment -- the exact shape that hid the original bug"
    )
    embed = ".from('profiles').select('id, teachers(designation), staff(designation)')"
    cols = list(selects_in(embed))[0][1]
    assert cols == ["id"], f"SELFTEST FAILED: embeds must not be treated as columns, got {cols}"
    pdf = (
        "  static const _columns = <String, List<String>>{\n"
        "    'schedule_slots': [\n      'subject', 'room_number',\n    ],\n"
        "  };\n"
    )
    assert list(backup_pdf_columns(pdf)) == [("schedule_slots", ["subject", "room_number"])], \
        "SELFTEST FAILED: cannot read the backup PDF column map"
    print("selftest: parser sees commented selects, ignores embeds, reads the column map -- OK")


# ------------------------------------------------------------------------ main
def live_schema(service_key: str):
    """{table: {columns}} from PostgREST's OpenAPI document."""
    req = urllib.request.Request(
        f"{SUPABASE_URL}/rest/v1/",
        headers={"apikey": service_key, "Authorization": f"Bearer {service_key}"},
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        spec = json.load(r)
    return {
        name: set(body.get("properties", {}).keys())
        for name, body in spec.get("definitions", {}).items()
    }


def main() -> None:
    _selftest()

    service_key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    if not service_key:
        # Secrets are not exposed to pull_request runs from forks, so a
        # missing key means "cannot check here", not "check failed".
        print("::warning::SUPABASE_SERVICE_ROLE_KEY not set, skipping column-name audit.")
        sys.exit(0)

    try:
        schema = live_schema(service_key)
    except urllib.error.URLError as e:
        print(f"::error::could not read the PostgREST schema: {e}")
        sys.exit(1)

    if not schema:
        print("::error::PostgREST returned no table definitions; refusing to pass vacuously.")
        sys.exit(1)

    problems, checked = [], 0
    for f in sorted(LIB.rglob("*.dart")):
        src = f.read_text(encoding="utf-8", errors="replace")
        rel = f.relative_to(LIB.parent).as_posix()

        sources = list(selects_in(src))
        if f.name == "upload_backup_pdf.dart":
            sources += list(backup_pdf_columns(src))

        for table, cols in sources:
            if table not in schema:      # a view or RPC PostgREST does not expose
                continue
            for col in cols:
                checked += 1
                if col not in schema[table]:
                    problems.append(f"  {rel}: {table}.{col} does not exist")

    print(f"checked {checked} column references against {len(schema)} live tables")
    if problems:
        print("::error::Dart code names columns that do not exist:")
        for p in sorted(set(problems)):
            print(f"::error::{p}")
        print("::error::PostgREST rejects a whole select on one bad name (42703), "
              "and the backup PDF silently drops the column instead.")
        sys.exit(1)
    print("no unknown column names")


if __name__ == "__main__":
    main()
