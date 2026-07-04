<div align="center">

# AFOS — All Facilities One System

**One app for every facility at Daffodil International University.**

Class routines, transport, hall allocation, exam seating, library, lost & found, clubs, mentorship, department chat, digital ID, and push notifications — all in one place, for students, teachers, and administrators.

[![Platform](https://img.shields.io/badge/platform-Android%20%7C%20iOS%20%7C%20Web-blue)]()
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)]()
[![Backend](https://img.shields.io/badge/backend-Supabase-3ECF8E?logo=supabase)]()

[Download the latest APK](../../releases/latest) · [Report an issue](../../issues)

</div>

---

## Download

Grab the latest Android build from the **[Releases](../../releases)** page — download the `.apk`, open it on your phone, and allow "install from unknown sources" if prompted. No Play Store account needed.

> This is a university-scoped app — a university email is required to register, with a small allowlist of bootstrap accounts for testing.

## What's inside

AFOS adapts to who's using it — a student, a teacher, or an administrator see different tools built for their role.

| Area | What it does |
|---|---|
| 🏠 **Dashboard** | Live notices, quick links, role-aware overview |
| 📅 **Class Schedule** | Personal timetable filtered to your batch/section, imported straight from the university's routine PDF |
| 🚌 **Transport** | Live bus routes, stop lookup, "find my route" search, map view |
| 🏢 **Hall Allocation** | Apply for a seat, track status, cancel, file complaints — with a full admin approval workflow |
| 📚 **Library** | Catalogue, borrowing, fine tracking |
| 🔍 **Lost & Found** | Post and claim items with photos, in-app contact reveal once a claim is accepted |
| 🎓 **Clubs & Events** | Discover clubs, join, RSVP to events |
| 🧑‍🏫 **Mentorship** | Book sessions with faculty mentors, department-matched |
| 💬 **Department Chat** | Realtime per-department channels, role-scoped (student/faculty/everyone) |
| 🪪 **VR-ID** | Rotating QR digital ID card with live server-side verification and a downloadable PDF proof-of-identity for anyone who scans it |
| 🔔 **Notifications** | Push + in-app, targeted by role/department/direct action |
| ⚙️ **Settings** | Profile, avatar, routine-matching info, theme |

**For admins & super admins**, dedicated tools layer on top: hall application review, cross-department chat moderation, notices/rules publishing, faculty & department registry management, and full role-based oversight.

## Tech stack

| Layer | Technology |
|---|---|
| App | Flutter 3 (Android · iOS · Web · Windows/macOS for dev) |
| Backend | [Supabase](https://supabase.com) — Postgres, Auth, Realtime, Storage, Edge Functions, Row Level Security |
| Push notifications | [OneSignal](https://onesignal.com) |
| Maps | OpenStreetMap via `flutter_map` |

Every meaningful access rule is enforced server-side with Postgres Row Level Security — the app's UI hides things for convenience, but the database is the real gate.

---

## Developer setup

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.x
- A [Supabase](https://supabase.com) project
- [Supabase CLI](https://supabase.com/docs/guides/cli) (for migrations & edge functions)
- A [OneSignal](https://onesignal.com) app (for push notifications)

### 1. Clone and install dependencies
```bash
git clone https://github.com/rakibhassanrh66/AFOS.git
cd AFOS
flutter pub get
```

### 2. Configure your Supabase project
Update `lib/config/supabase_config.dart` with your project's URL and publishable key, and `lib/config/app_config.dart` with your OneSignal App ID.

### 3. Set up the database
```bash
supabase login
supabase link --project-ref <your-project-ref>
supabase db push
```
This applies every migration in `supabase/migrations/` in order.

### 4. Deploy edge functions
```bash
supabase functions deploy parse-routine
supabase functions deploy send-notification
supabase secrets set SUPABASE_SERVICE_ROLE_KEY=<your_service_role_key>
supabase secrets set ONESIGNAL_REST_KEY=<your_onesignal_rest_key>
```
**Never** put the service-role key or OneSignal REST key in app code — they're server-only secrets, set via `supabase secrets set` and read from the environment inside the edge functions.

### 5. Run it
```bash
flutter run -d chrome     # Web
flutter run -d android    # Android device/emulator
```

### Build a release APK
```bash
flutter clean
flutter pub get
flutter build apk --release
```
The APK lands at `build/app/outputs/flutter-apk/app-release.apk`.

## Project structure

```
lib/
  config/       # App-wide config, routing, theming
  core/         # Auth session helpers, shared network/storage utilities
  features/     # One folder per feature — bloc/presentation/data per module
  shared/       # Reusable widgets and models
supabase/
  migrations/   # Every schema/RLS change, applied in order via `supabase db push`
  functions/    # Edge functions (routine parsing, notifications)
```

## Contributing

Issues and pull requests are welcome. For anything touching the database, please add a new timestamped migration under `supabase/migrations/` rather than editing an existing one.

## License

No license has been set for this project yet — all rights reserved by default until one is added.
