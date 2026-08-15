# Releasing AFOS — the whole ritual, in order

Every command needed to ship a build and have installed phones actually offer it
as an update. Copy-paste top to bottom.

**Current state at time of writing:** `2.8.5+5000`, tag `v2.8.5`.

> **Flutter on this machine is `C:\RakibFlutter\bin\flutter.bat`.** Plain
> `flutter` may not resolve. Every command below uses the full path.

---

## The order matters, and here is why

```
1. bump version   →  2. verify  →  3. commit + push  →  4. tag + push tag
                                                              ↓
                                                    5. WAIT for CI to publish
                                                              ↓
                                          6. verify the APK really is there
                                                              ↓
                                     7. THEN insert the app_releases row
```

**Step 5 is not optional.** Inserting the row is what tells every installed
phone an update exists, and the URL the app builds from it —
`.../releases/download/v2.8.6/AFOS-v2.8.6.apk` — does not exist until CI has
uploaded it. Announce first and everyone who taps Update gets an error until CI
catches up.

---

## 1 · Bump the version

Edit `pubspec.yaml`, line 4. Two rules, both learned the hard way:

```yaml
version: 2.8.6+5001
```

- **The build number must always go UP.** Never reuse or lower it. Android
  refuses a lower `versionCode` as a downgrade — that is what
  `INSTALL_FAILED_VERSION_DOWNGRADE` means.
- **Numbering starts at 5000** because releases 2.8.3/2.8.4 shipped split APKs
  carrying Flutter's multiplied codes (up to 4069). Anything below 5000 is a
  downgrade for those users. Just keep incrementing: 5001, 5002, …

## 2 · Verify before you tag

```bash
C:\RakibFlutter\bin\flutter.bat analyze
C:\RakibFlutter\bin\flutter.bat test
```

Both must be clean — **0 issues**, all tests passing. A tag triggers a real
publish; there is no undo that does not confuse users who already downloaded.

Optional but wise before a big release:

```bash
C:\RakibFlutter\bin\flutter.bat build apk --release
```

## 3 · Commit and push

```bash
git add -A
git commit -m "Bump to 2.8.6+5001: <what actually changed, for a human>"
git push origin main
```

## 4 · Tag it — this is what triggers the release build

```bash
git tag -a v2.8.6 -m "AFOS v2.8.6 — <one line>"
git push origin v2.8.6
```

**The tag must be `v` + the version WITHOUT the build number.**
`version: 2.8.6+5001` → tag `v2.8.6`. The app builds its download URL from the
release part only, so `v2.8.6+5001` as a tag produces a 404 for every user.

## 5 · Wait for CI

```bash
gh run list --limit 3
gh run watch <RUN_ID> --exit-status
```

Or watch it in the browser: <https://github.com/rakibhassanrh66/AFOS/actions>

The `release` job builds the APK, **verifies its signature against the pinned
certificate**, and refuses to publish if it does not match. That check is why
updates install cleanly over each other — let it finish.

## 6 · Verify the APK is really published

```bash
gh release view v2.8.6 --json assets -q '[.assets[].name] | join("\n")'
```

Expect four files:

```
AFOS-v2.8.6.apk                 ~91 MB   universal — what the in-app updater fetches
AFOS-v2.8.6-arm64-v8a.apk       ~33 MB   most modern phones
AFOS-v2.8.6-armeabi-v7a.apk     ~31 MB   older 32-bit phones
AFOS-v2.8.6-x86_64.apk          ~36 MB   emulators
```

And confirm the exact URL the app will request actually resolves:

```bash
curl -sIL "https://github.com/rakibhassanrh66/AFOS/releases/download/v2.8.6/AFOS-v2.8.6.apk" \
  -o /dev/null -w "status=%{http_code} type=%{content_type}\n"
```

Expect `status=200` and `type=application/vnd.android.package-archive`.
**Anything else means stop — do not run step 7.**

## 7 · Announce it — this is what makes the Update button light up

Run in the Supabase SQL editor
(<https://supabase.com/dashboard/project/dtsptjallznnvattadlu/sql>):

```sql
INSERT INTO app_releases (version, release_date, title, highlights, platforms)
VALUES (
  '2.8.6',
  current_date,
  'A Short Title People Will Read',
  ARRAY[
    'What changed, written for a student deciding whether to install — not a commit message.',
    'One sentence per line. Say what is different for THEM.'
  ],
  ARRAY['android','web']
);
```

**`version` must NOT carry the `+build` suffix.** Write `'2.8.6'`, never
`'2.8.6+5001'`. A trigger rejects it now, because twelve historical rows were
written that way and every one produced a 404 download URL *and* compared as
older than the release it was announcing.

That single INSERT does all of this, in one transaction:

- writes an in-app notification for every account (trigger),
- queues the OneSignal push so phones with AFOS **closed** get a banner,
- pushes over realtime so an app that is **open** raises its update card.

**Do not also send a manual broadcast.** It is already done.

## 8 · Confirm it reached people

```sql
select version, release_date, title from app_releases
order by release_date desc, created_at desc limit 3;
```

Then on a phone running an older build: **Settings → Check for Updates**.

---

## Writing the release notes

The `app_releases` row is written **by hand, on purpose**. Automating it from
commit messages was tried and removed: v2.5.3's entire What's New read
*"fix: PostgREST profiles embeds on enrollments/course_offerings (v2.5.3)"* —
shown to students.

Commit subjects are written for `git log`. Release notes are written for someone
deciding whether to install. They are not the same text and one cannot be
derived from the other.

- Say what is different **for the user**, not what you changed in the code.
- No emoji, no exclamation marks.
- If a bug is fixed, describe the symptom they experienced, not the cause.

`tool/publish_release.sql` holds every past release's notes as worked examples.

---

## When something goes wrong

| Symptom | Cause | Fix |
|---|---|---|
| **"App not installed as package conflicts with an existing package"** | Signature mismatch — a differently signed AFOS is on the phone. | Uninstall AFOS first, **including from Secure Folder / Vault / Second Space**, then install. `adb uninstall com.example.afos_v7` clears every profile at once. |
| **Update button does nothing** | The installed build has a higher `versionCode` than the new one. | Check with `adb shell dumpsys package com.example.afos_v7 \| grep versionCode`. Bump the build number above it. |
| **Downloads, then "problem parsing the package"** | Truncated download, or the release asset was not published yet. | Re-run step 6. If the URL 404s, CI has not finished. |
| **CI fails: "APK is signed with the WRONG key"** | Keystore secrets in GitHub do not match `android/app/afos-release.jks`. | Re-set `ANDROID_KEYSTORE_BASE64` and the password/alias secrets from the current keystore. |
| **CI fails: scratch dirs or secrets tracked** | A `.codex/`, `.claude/`, `.jks`, `.env` etc. got committed. | `git rm -r --cached <path>`, commit. It is in `.gitignore` already. |

---

## Things that must never change

- **The signing key.** `2f49802b7533aa2f193b30de86edd7f124c3ebbf0e6196fb0c05ca614a03623f`.
  Lose `android/app/afos-release.jks` and no existing install can ever be
  updated again — every user would have to uninstall and reinstall.
  **Back it up somewhere that is not this machine.**
- **The universal APK's filename.** `AFOS-v<version>.apk`. The in-app updater
  builds that exact string.
- **`android/key.properties` and `*.jks` stay gitignored.** This repo is public.
