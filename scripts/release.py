"""One-command release: bump the version, commit, tag, and push.

Pushing the tag is what actually triggers everything else — the `release`
job in .github/workflows/main.yml (and the mirrored job in .gitlab-ci.yml,
if that remote is set up) picks up any push matching `v*` and automatically:
  1. builds the release APK
  2. publishes it as a GitHub Release (with generated release notes)
  3. records a "What's New" row in the app_releases table, using the
     commit messages between this tag and the last one as the highlights
     (see .github/scripts/record_release.py) — so write real, meaningful
     commit messages, since they become what users actually see.

This script only does the LOCAL half (version bump + commit + tag + push);
everything else already existed and needed no changes.

Usage (from the repo root):
    python scripts/release.py [patch|minor|major] ["commit message"]

    python scripts/release.py                          # patch bump, auto-summary, just confirm
    python scripts/release.py minor "add course offerings"
    python scripts/release.py major "v3: new architecture"

If you don't pass a message, this generates a mechanical one from `git
status` (which feature areas changed, how many files) and lets you accept
it with Enter or type your own instead. Be clear-eyed about what that
auto-summary actually is: it can only see WHICH files changed, never WHY —
it can't read intent the way a person (or Claude, if you ask directly
before running this) can. For a release users will actually read the
notes on, the better move is to ask Claude to write the message for this
specific batch of work, then paste that in when prompted — that's a
one-time interactive step, not something this standalone script can do
unsupervised without its own separate AI API key.

Safety: shows `git status` and asks for a y/n confirmation before touching
anything, so it never silently commits files you didn't expect to see.
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PUBSPEC = ROOT / "pubspec.yaml"


def run(*args: str, check: bool = True) -> str:
    result = subprocess.run(args, cwd=ROOT, capture_output=True, text=True)
    if check and result.returncode != 0:
        print(f"::error:: command failed: {' '.join(args)}\n{result.stderr}")
        sys.exit(1)
    return result.stdout.strip()


def read_version() -> tuple[int, int, int, int]:
    text = PUBSPEC.read_text(encoding="utf-8")
    m = re.search(r"^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$", text, re.MULTILINE)
    if not m:
        print("::error:: could not find a 'version: X.Y.Z+N' line in pubspec.yaml")
        sys.exit(1)
    return tuple(int(g) for g in m.groups())  # type: ignore[return-value]


def write_version(major: int, minor: int, patch: int, build: int) -> str:
    new_full = f"{major}.{minor}.{patch}+{build}"
    text = PUBSPEC.read_text(encoding="utf-8")
    text = re.sub(r"^version:\s*\d+\.\d+\.\d+\+\d+\s*$", f"version: {new_full}", text, count=1, flags=re.MULTILINE)
    PUBSPEC.write_text(text, encoding="utf-8")
    return new_full


def categorize(path: str) -> str:
    parts = path.split("/")
    if len(parts) >= 3 and parts[0] == "lib" and parts[1] == "features":
        return parts[2]
    if path.startswith("supabase/"):
        return "backend/database"
    if path.startswith(".github/") or path.startswith(".gitlab-ci"):
        return "CI/release tooling"
    if path.startswith("lib/core/") or path.startswith("lib/shared/") or path.startswith("lib/config/"):
        return "shared/core"
    return "other"


def auto_summary() -> str:
    """Best-effort, mechanical summary of what changed, grouped by feature
    area — a starting point, not a substitute for actually describing the
    change. Can only see WHICH files changed, never WHY."""
    status = run("git", "status", "--porcelain")
    if not status:
        return ""
    areas: dict[str, int] = {}
    added = removed = 0
    for line in status.splitlines():
        code, path = line[:2], line[3:].strip()
        if code.strip() in ("A", "??"):
            added += 1
        elif "D" in code:
            removed += 1
        area = categorize(path)
        areas[area] = areas.get(area, 0) + 1
    ranked = sorted(areas.items(), key=lambda kv: -kv[1])
    parts = [f"{area} ({n} file{'s' if n != 1 else ''})" for area, n in ranked[:6]]
    summary = "Update: " + ", ".join(parts)
    if len(ranked) > 6:
        summary += f", +{len(ranked) - 6} more areas"
    extras = []
    if added:
        extras.append(f"{added} new")
    if removed:
        extras.append(f"{removed} removed")
    if extras:
        summary += " (" + ", ".join(extras) + ")"
    return summary


def main() -> None:
    bump = sys.argv[1] if len(sys.argv) > 1 else "patch"
    if bump not in ("patch", "minor", "major"):
        print(f"Unknown bump type '{bump}' — use patch, minor, or major.")
        sys.exit(1)
    message = sys.argv[2] if len(sys.argv) > 2 else None

    branch = run("git", "rev-parse", "--abbrev-ref", "HEAD")

    major, minor, patch, build = read_version()
    if bump == "major":
        major, minor, patch = major + 1, 0, 0
    elif bump == "minor":
        minor, patch = minor + 1, 0
    else:
        patch += 1
    build += 1
    tag = f"v{major}.{minor}.{patch}"

    print(f"Branch: {branch}")
    print(f"Version: {major}.{minor}.{patch}+{build - 1} -> {major}.{minor}.{patch}+{build}  (tag {tag})")
    print()
    status = run("git", "status", "--short")
    if status:
        print("git status --short:")
        print(status)
    else:
        print("(working tree otherwise clean — only the version bump will be committed)")
    print()

    confirm = input(f"Commit + tag {tag} + push to origin/{branch}? [y/N] ").strip().lower()
    if confirm != "y":
        print("Aborted — nothing was changed.")
        sys.exit(0)

    if message is None:
        auto = auto_summary()
        if auto:
            print(f"Auto-generated summary (mechanical, from changed files only): {auto}")
            typed = input("Press Enter to use it, or type your own message: ").strip()
        else:
            typed = input("Commit message (describe what changed, this feeds What's New): ").strip()
        message = typed or auto or f"chore: release {tag}"

    new_full = write_version(major, minor, patch, build)
    print(f"pubspec.yaml -> version: {new_full}")

    run("git", "add", "-A")
    run("git", "commit", "-m", f"{message} ({tag})")
    run("git", "tag", "-a", tag, "-m", message)
    print(f"Committed and tagged {tag}.")

    run("git", "push", "origin", branch)
    run("git", "push", "origin", tag)
    print(f"\nPushed. {tag} will now build + release automatically via CI.")
    print("GitHub: check the Actions tab for progress.")
    print("What's New will be recorded once the release job finishes — see the highlights")
    print("that get pulled from your commit messages since the last tag.")


if __name__ == "__main__":
    main()
