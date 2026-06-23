# AFOS — All Facilities One System
### Daffodil International University

A complete university management app built with Flutter 3 (Web + Android + iOS), Supabase, and OneSignal.

## 🚀 Quick Start

```bash
# 1. Get dependencies
flutter pub get

# 2. Run on Chrome (web)
flutter run -d chrome

# 3. Run on Android
flutter run -d android

# 4. Build release APK
flutter build apk --release

# 5. Build web
flutter build web --release
```

## 🔑 Keys Reference

| Service | Key Location |
|---------|-------------|
| Supabase URL | `lib/config/supabase_config.dart` |
| Supabase anon | `lib/config/supabase_config.dart` |
| OneSignal App ID | `lib/config/app_config.dart` |
| imgBB API Key | `lib/config/app_config.dart` |
| Service Role JWT | `supabase secrets set` only |

## 🗂️ Database Setup

Run `supabase/migrations/001_init.sql` in your Supabase SQL Editor.

## 📦 Deploy Edge Functions

```bash
supabase login
supabase link --project-ref dtsptjallznnvattadlu
supabase functions deploy parse-routine
supabase functions deploy send-notification
supabase secrets set SUPABASE_SERVICE_ROLE=<your_service_role_jwt>
supabase secrets set ONESIGNAL_REST_KEY=<your_onesignal_rest_key>
```

## 🌐 Deploy to Vercel

1. Push to GitHub: `git push origin main`
2. Import repo at vercel.com
3. Add env vars: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `ONESIGNAL_APP_ID`, `IMGBB_API_KEY`

## 📱 Modules

| Module | Route | Description |
|--------|-------|-------------|
| Splash | `/splash` | Animated launch screen |
| Auth | `/auth/login` | Supabase Auth |
| Dashboard | `/home` | Overview with live data |
| Schedule | `/schedule` | Timetable + PDF parser |
| Hall | `/hall` | Seat application |
| Transport | `/transport` | Bus routes + map |
| Payment | `/payment` | WebView bridge |
| Library | `/library` | Books + fine calculator |
| Lost & Found | `/lost-found` | imgBB photo posts |
| Clubs | `/clubs` | Join & manage clubs |
| Mentorship | `/mentorship` | Faculty bookings |
| Exam Seats | `/exam-seat` | Seat plan + admit card |
| Dept Chat | `/dept-chat` | Supabase Realtime |
| VR-ID | `/vr-id` | QR identity system |
| Notifications | `/notifications` | OneSignal push center |
| Settings | `/settings` | Profile + theme |

## 🛠️ Stack

- **Frontend**: Flutter 3 (Web + Android + iOS)
- **Backend**: Supabase (Auth + PostgreSQL + Realtime + Storage + Edge Functions)
- **Push**: OneSignal (free tier, 10k subscribers)
- **Images**: imgBB API (unlimited free)
- **Hosting**: Vercel (free tier)
- **CI/CD**: GitHub Actions

**Total cost: ৳0 / $0**
