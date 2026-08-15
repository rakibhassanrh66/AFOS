# Security Policy

AFOS holds real student records — results, hall allocations, attendance, ID
scans and location data for a live university. Please treat anything you find
here as affecting real people.

## Reporting a vulnerability

**Use GitHub's private reporting**, so a fix can ship before the details are
public: [Report a vulnerability](https://github.com/rakibhassanrh66/AFOS/security/advisories/new)

Please do not open a public issue for a security problem.

Include what you can — the affected screen or endpoint, what you did, what you
expected, and what happened instead. A proof of concept helps, but a clear
description of the flaw is worth more than a working exploit.

**Please do not** test against real accounts other than your own, run automated
scanners against the production database, or access data belonging to another
student to demonstrate an issue. If a flaw would require that to prove, describe
it and we will reproduce it ourselves.

## What is in scope

- Authentication and session handling
- Row Level Security — anything letting one user read or write another's data
- The delegated-permission model (`user_permissions`, `permission_audit`) and
  any way to grant yourself or someone else more than intended
- VR-ID token issuing and verification
- The release/update path, including APK signing

## What is not a vulnerability

**The Google API key in `android/app/google-services.json`.** Firebase client
keys are identifiers, not secrets — they ship inside every Android APK and can
be read out of any published build. Firebase's security comes from Security
Rules and App Check, not from hiding this value. It is committed deliberately so
the app builds from a fresh clone.

What *would* be a real issue is that key being **unrestricted** in Google Cloud
Console, or Firebase rules that allow access the app does not need. Those are in
scope.

## Architecture notes for reviewers

Authorization is enforced in **Postgres**, not in Flutter. Every table has RLS,
and the client-side checks exist to avoid offering a door the database will slam
— never as the control itself. If you find a client-side check that is the *only*
thing preventing an action, that is a finding worth reporting.

Two invariants the project holds itself to:

- A delegate may grant only permissions they themselves hold, and never to
  themselves.
- `permission_audit` is append-only, written by a trigger, with no UPDATE or
  DELETE policy for anyone.

If you find a way around either, please report it.

## Supported versions

Only the latest release. Updates ship through the app itself and from
[Releases](https://github.com/rakibhassanrh66/AFOS/releases).
