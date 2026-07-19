# AFOS — Integration-Readiness Audit (evidence-based, from source)

**Repo:** `E:\FYDP\AFOS` · branch `afos/delegated-admin` · pubspec version `1.1.2+11`
**Method:** every claim below is grounded in the actual Dart/SQL/TS source, not in README/report numbers. Where I state a data source or a gap, the file/line is cited. Percentages are my engineering judgment of *production-readiness at DIU* (UI built **and** wired to a trustworthy live data source), not "screens exist."

> **Two premise corrections up front (both verified in code):**
> 1. **There is no Firebase data layer.** `pubspec.yaml` has **no** `firebase_auth`, `cloud_firestore`, or `firebase_messaging`. The only Firebase artifact is `android/app/google-services.json` (project `afos-66deadbrat`), which exists **solely** as the FCM sender OneSignal uses to deliver Android push. No app data lives in Firebase. The stack is **Flutter + Supabase**, with OneSignal (→FCM/APNs) for push.
> 2. **There is no payment gateway anywhere.** A repo-wide search for `sslcommerz|bkash|nagad|rocket|stripe|razorpay|tran_id|store_id` returns **zero** real integrations (the 4 file hits are incidental substrings like shimmer "stripe"). Payment is a WebView pointed at the DIU portal — details in the table and §3-D.

---

## 1. Repo Overview

### Project structure (top level)
```
AFOS/
├── lib/                    # Flutter app (138 .dart files)
├── supabase/
│   ├── functions/          # 6 Deno edge functions
│   └── migrations/         # ~60 SQL migrations (RLS, triggers, RBAC)
├── android/ ios/ web/ windows/ linux/ macos/   # platform shells
├── integration_test/       # overflow_smoke_test.dart (5-role route walk)
├── assets/                 # images, lottie
└── pubspec.yaml            # v1.1.2+11
```

### `lib/` tree (by feature)
```
lib/
├── main.dart                 # runApp → AFOSApp (MaterialApp.router)
├── bootstrap.dart            # Hive, Supabase.initialize, OneSignal, SOS, DI
├── config/
│   ├── app_config.dart       # appName, oneSignalAppId, diuPaymentUrl, diuLibraryUrl, email allowlist
│   ├── supabase_config.dart  # url + PUBLISHABLE key (anon), client/uid/jwt getters
│   ├── routes/app_router.dart# go_router: single redirect() guard + ShellRoute
│   └── theme/                # Liquid Glass tokens, dark/light themes
├── core/
│   ├── di/injection.dart     # GetIt — registers only 3 core services
│   ├── network/              # supabase_service, storage_upload_service
│   ├── services/             # connectivity, local_cache (Hive), outbox, sos_location, onesignal_web_bridge, badge
│   ├── auth/role_session.dart# cached role/verified/profile_completed lookups for the router guard
│   ├── data/bd_geography.dart# static BD division→district→upazila (no DB)
│   └── utils/                # validators, formatters, error_formatter, location_helper
├── features/                 # 25 feature folders (see §2)
│   └── <feature>/{data/repositories, bloc, presentation}
└── shared/                   # widgets, models (UserModel), extensions
```

### State management, routing, data layer, backend clients

| Concern | What the code actually uses |
|---|---|
| **State management** | `flutter_bloc` is a dependency but **only 3 BLoCs exist**: `AuthBloc`, `ShellBloc`, `ThemeBloc` (auth flow, nav-shell chrome, theme). **Every feature screen is a `StatefulWidget` + `setState`** — 77 `StatefulWidget`s across 48 files. There is **no** app-wide BLoC/Riverpod data architecture. |
| **Routing** | `go_router` ^14.6.2. One `GoRouter` with a single async `redirect()` (`app_router.dart:62`) doing session → profile-completed → verified → role-based route guards, plus a `ShellRoute` hosting all authenticated screens. Hash-based URLs on web (`#/route`). |
| **Data-layer pattern** | **Mixed / inconsistent.** A repository layer exists for *some* features (`auth`, `schedule`, `transport`, `grades`, `assignments`, `sos`) but **most screens call `SupabaseConfig.client.from(...)` directly inline** (clubs, hall, dept_chat, lost_found, mentorship, payment, exam_seat, vr_id, settings, notifications). Repositories are **not** registered in GetIt — they're `new`'d inline. DI (`injection.dart`) registers only `ConnectivityService`, `LocalCacheService`, `OutboxService`. |
| **Backend clients in use** | `supabase_flutter` ^2.8.0 (Postgres + Auth + Realtime + Storage + Edge Functions — the primary and near-only backend). `onesignal_flutter` ^5.2.5 (push; web via a hand-written JS-interop bridge). `webview_flutter` ^4.10.0 (payment portal + VR-ID hosted PDF). `dio` ^5.7.0 — used in **exactly 2 places** (`admin_upload_routine_screen.dart` multipart upload, `vr_id_pdf_generator.dart`), not a general HTTP layer. **No `firebase_auth` / `cloud_firestore` / `firebase_messaging`.** |

### How Firebase and Supabase split responsibilities
**They don't share the data plane.** **Supabase owns 100% of app data, auth, and business logic** (Postgres tables + RLS + SECURITY DEFINER triggers + 6 edge functions + Storage buckets `avatars`, `lost-found`, `sos-voice`). **Firebase's only role is transport for push**: OneSignal needs an FCM sender key to deliver notifications to Android, so `google-services.json` is present — but no Firebase SDK is called from Dart and no record is ever read/written to Firebase. If push were removed, Firebase would vanish from the project with zero data-layer impact.

---

## 2. Reality Audit Table

**Legend:** REAL = live Supabase/Firebase read-write · MOCK = hardcoded in-app data · SANDBOX = wired to a test endpoint only · STUB = UI exists, no backend wired.
**"Data origin" nuance (important):** many modules are technically REAL (live Supabase CRUD) but their data is **either self-declared by users at signup or manually uploaded by an admin from a PDF/Excel — not synced from DIU's authoritative systems.** The % reflects production-readiness *for real DIU use*; the last column names the real gap.

| Module | Completion % | Backend state | Key files | What's missing to reach production |
|---|---|---|---|---|
| **Authentication** | 85% | **REAL** (Supabase Auth) | `auth/data/repositories/auth_repository.dart`, `auth/presentation/register_screen.dart`, `config/routes/app_router.dart:62`, `migrations/20260715120000_delegated_admin_permissions.sql` (handle_new_user whitelist), `core/auth/role_session.dart` | Email/password only, **no DIU SSO**. Student ID / department / batch / semester are **self-declared** and never verified against a DIU roster. Domain-gated to `@diu.edu.bd` + manual super_admin approval. Role-escalation hardening (account_type whitelist, is_verified write-gate) is real but **on this unmerged branch**, not yet on `main`. |
| **Dashboard** | 90% | **REAL** | `dashboard/presentation/dashboard_screen.dart` (reads profiles, notices, schedule_slots, borrowed_books, hall_applications, club/conference/cr requests, feedback) | Fully wired; usefulness is only as good as the modules it aggregates. No independent gap. |
| **Class Schedule & Alerts** | 80% | **REAL, admin-uploaded origin** | `schedule/data/repositories/schedule_repository.dart`, `schedule/presentation/admin_upload_routine_screen.dart`, `functions/parse-routine/index.ts`, `schedule/presentation/schedule_screen.dart` | Data is populated by an **admin uploading a routine PDF/Excel per department**, parsed by the `parse-routine` edge function into `schedule_slots`. Works, but is **not synced from the DIU registrar** — every semester's routine is a manual re-upload. `exams` table is same pattern. |
| **Hall Management** | 85% | **REAL, app-internal** | `hall/presentation/hall_screen.dart`, `hall/presentation/manage_hall_screen.dart`, RPC `get_hall_availability` | Entire hall workflow (applications, room availability, complaints) lives **only in AFOS** — it is not the DIU hall office's real allocation ledger. Production = decide whether AFOS *is* the system of record or must reconcile with the hall office. |
| **Payment Gateway** | **20%** | **STUB** | `payment/presentation/payment_screen.dart`, `payment/presentation/payment_webview_screen.dart`, `AppConfig.diuPaymentUrl` | **No payment gateway integrated at all.** "Pay Now" opens a WebView to `studentportal.diu.edu.bd/payment` and injects `window.afosStudentId` + `window.afosToken` (Supabase JWT) that the DIU portal **does not consume**. **Nothing writes `payment_records`**, so the History tab is permanently empty. Needs a real gateway (SSLCommerz/bKash prod) or a DIU finance API **plus** a server-side verification/callback edge function. |
| **Transport** | 65% | **MIXED: routes/stops REAL (admin upload), live GPS STUB** | `transport/data/repositories/transport_repository.dart`, `transport/presentation/transport_screen.dart`, `functions/parse-routine` (transport type) | Routes/stops are admin-uploaded (real rows). **`transport_live_status` has zero producers** — no app screen or function ever writes it, so live-bus tracking is a dead read of an empty table. `transport_stops` rows have **no GPS coordinates** (nearest-stop is text-matched, not geospatial). Needs a real vehicle-tracking feed. |
| **Department Chat** | 90% | **REAL** (Supabase Realtime) | `dept_chat/presentation/dept_chat_screen.dart`, `dept_chat/presentation/manage_dept_chat_screen.dart` (dept_channels, dept_messages) | Fully functional realtime chat. Production polish only (moderation, attachments). No external dependency. |
| **E-Library** | 70% | **REAL, app-native catalog** | `library/presentation/library_screen.dart`, `library/presentation/manage_library_screen.dart` (books, borrowed_books) | Works as a **self-contained library the admin seeds by hand** — it is **not connected to DIU's real library catalog or circulation/fines ledger**. Fine rate (৳5/day) and 7-day loan are hardcoded. Needs the DIU library system's catalog + borrowing API to be authoritative. |
| **Lost & Found** | 90% | **REAL** | `lost_found/presentation/lost_found_screen.dart` (lost_found_posts, lost_found_claims) | Complete CRUD + claim workflow + image upload. No external dependency — a genuine finished module. |
| **Club Management** | 90% | **REAL** | `clubs/presentation/clubs_screen.dart`, `club_chat_screen.dart`, `admin/presentation/manage_clubs_screen.dart` (clubs, club_members, club_events, membership/post requests, event_registrations) | Complete: membership requests, events, registrations, president-scoped chat/notify. No external dependency. |
| **Academic Mentorship** | 85% | **REAL** | `mentorship/presentation/mentorship_screen.dart` (mentors, mentorship_bookings) | Booking + notify works. `mentors` seeded in-app. No external dependency (unless DIU wants official mentor assignments). |
| **Exam Seat Plan** | 75% | **REAL, admin-uploaded origin** | `exam_seat/presentation/exam_seat_screen.dart`, `exam_seat/presentation/manage_exam_seats_screen.dart`, `exam_seat/data/exam_room_pdf_parser.dart` | Admin uploads a seat-plan PDF → parsed into `exam_room_allocations`. Student view matches on the student's **self-declared** `batch_label`/`section` (`students` table). Not synced from the exam controller's authoritative source; correctness depends on self-declared data being right. |
| **VR-ID** | 80% | **REAL, self-contained** | `vr_id/presentation/vr_id_screen.dart`, `vr_id/data/vr_id_pdf_generator.dart` (profiles, vr_access_log) | Rotating SHA-256 token QR (60s) generated from the Supabase UID + profile. Fully works **as an app-internal digital ID** — but is **not integrated with any real DIU access system** (turnstiles, library gate, exam hall). "Verification" is one AFOS user scanning another's QR. |
| **Push Notifications** | 75% | **REAL** (OneSignal → FCM/APNs) | `functions/send-notification/index.ts`, `notifications/data/repositories/notification_service.dart`, `bootstrap.dart`, `core/services/onesignal_web_bridge*.dart` | Server-authorized fan-out (direct ≤20 / role-broadcast / club) is real and hardened. **Delivery** depends on OneSignal dashboard config: web push is **not configured** ("App not configured for web push"), and on-device delivery is only partially confirmed (checkpoint). Needs dashboard finalization + on-device confirmation. |
| **Notifications Center** | 90% | **REAL** (Realtime) | `notifications/presentation/notification_center_screen.dart`, `notification_popover.dart`, `shell/presentation/top_app_bar.dart` (user_notifications) | Complete in-app center + realtime bell badge. No external dependency. |
| **Settings / Profile** | 90% | **REAL** | `settings/presentation/settings_screen.dart`, `settings/bloc/theme_bloc.dart` (profiles, user_settings, user_locations, students) | Complete: profile edit, theme/accent, location-sharing toggle, feedback. No external dependency. |

**One-line summary:** the app is **genuinely a working Supabase product** — ~11 of 16 modules are real, end-to-end, and would function for real users today. The five that are *not* production-ready for DIU are **Payment (stub)**, **Transport live-tracking (stub)**, and the three that are "real but fed by manual upload / self-declaration instead of DIU systems" — **Schedule, Exam Seat, E-Library** (plus Auth's lack of SIS verification underlying all of them).

---

## 3. API / External-System Dependency Map

Everything below is a module that is stub/self-declared/manually-fed **because it needs a real DIU system**. For each: what's faked & where → data/endpoints needed → auth → assumed shapes → where it plugs into *this* codebase → build-myself vs university-only.

### 3-A. DIU Identity / SSO + Student Information System (SIS) — *the root dependency*
- **What's faked & where:** At signup (`auth_repository.dart:signUp` → `data: {university_id, department, semester, batch, section, account_type, ...}`), the student **types their own** ID/department/batch/semester. `handle_new_user()` (migration `20260715120000`, line ~177) writes these verbatim into `profiles`/`students`. There is **no check** that the ID belongs to a real DIU student or that the batch/section is correct. This self-declared data is what Exam Seat, Grades, Schedule filtering, and VR-ID all trust.
- **Data + endpoints needed from DIU:**
  - `GET /students/{universityId}` → canonical name, department, program, batch, section, current semester, enrollment status, photo.
  - `GET /students/{universityId}/enrollments?semester=` → course codes/sections the student is actually registered in (drives schedule/exam filtering, grade eligibility).
  - (Ideally) an **OAuth2/OIDC SSO** so students sign in with their DIU account instead of self-registering.
- **Expected auth:** OAuth2 **Authorization Code + PKCE** (for SSO login) or **client-credentials + API key** (for a server-to-server SIS lookup). Realistically DIU issues a **client_id/secret or API key** scoped to a read-only student endpoint.
- **Assumed request/response (LABELLED ASSUMPTION):**
  ```json
  GET /api/v1/students/213-15-1234   Authorization: Bearer <client-cred-token>
  → { "university_id":"213-15-1234","name":"...","department":"CSE","program":"BSc CSE",
      "batch":"61","section":"A","semester":7,"status":"active","photo_url":"..." }
  ```
- **Where it plugs into AFOS:** two clean seams — (1) a new `verify-student` **edge function** called from `register_screen`/`complete_profile_screen` before insert, or a rewrite of `handle_new_user()` to call out; (2) if SSO, replace `AuthRepository.signIn` with `signInWithOAuth`. **Change size: medium.** The `students`/`profiles` schema already has every needed column, so it's "fill from API instead of from the form," not a schema redesign.
- **Build myself vs university-only:** *I can build* the edge function, the SSO redirect handling, the verified-badge UI, and the "identity_source" column (already stubbed in the delegated-admin migration). *Only DIU can provide* the SSO endpoint / SIS read API + credentials.

### 3-B. DIU Registrar — authoritative Schedule / Exams / Grades
- **What's faked & where:** `schedule_slots` and `exams` are filled by an **admin uploading a PDF/Excel** parsed in `functions/parse-routine/index.ts`. `exam_room_allocations` similarly from a seat-plan PDF (`manage_exam_seats_screen.dart:70`). Grades are **teacher-entered** in-app (`grades_repository.dart:upsertGrade`), not the registrar's official results.
- **Data + endpoints needed:** `GET /routine?department=&semester=` (slots: course, teacher, room, day, time); `GET /exam-schedule?...`; `GET /seat-plan?...`; optionally `GET /results?studentId=` for official transcripts.
- **Expected auth:** API key / client-credentials, read-only, per-department scope.
- **Assumed shape (ASSUMPTION):** a JSON array mirroring the current `schedule_slots` columns (`subject_code, subject, teacher_initial, room, day, start, end, batch, section, department, semester`).
- **Where it plugs in:** replace the **input** of `parse-routine` — instead of parsing an uploaded file, add a `sync-routine` edge function that pulls the registrar API and upserts the same rows. **Change size: small–medium** (the write/upsert path already exists and is battle-tested; only the source changes). The UI (`schedule_screen`, `exam_seat_screen`) needs zero change.
- **Build vs university-only:** *I build* the sync function + a cron trigger. *Only DIU provides* the registrar feed.

### 3-C. DIU Library System (catalog + circulation + fines)
- **What's faked & where:** `books` and `borrowed_books` are an **in-app catalog** an admin seeds via `manage_library_screen.dart`; checkout/renewal/fines run entirely in Supabase (`library_screen.dart`, fine `৳5/day` hardcoded, 7-day loan hardcoded).
- **Data + endpoints needed:** `GET /catalog/search?q=`, `GET /patrons/{id}/loans`, `GET /patrons/{id}/fines`, and (for two-way) `POST /loans` / `POST /renew`. DIU library likely runs **Koha** or a similar ILS.
- **Expected auth:** API key or ILS session token; possibly SIP2/REST if Koha.
- **Assumed shape (ASSUMPTION):** Koha REST-style `{ "biblio_id", "title", "author", "isbn", "available" }` and `{ "checkout_id","due_date","renewals" }`.
- **Where it plugs in:** introduce a `LibraryRepository` (currently the screen calls Supabase inline) with a live-catalog backend, or an edge function proxy to the ILS. **Change size: medium** (need a real repository seam first, then swap source). Decide: mirror-into-Supabase (cache) vs live-proxy.
- **Build vs university-only:** *I build* the repository + proxy + fines display. *Only DIU provides* the ILS API/credentials and the real fine policy.

### 3-D. Payment (production gateway via Finance dept)
- **What's faked & where:** `payment_webview_screen.dart` loads `AppConfig.diuPaymentUrl` and injects a Supabase JWT the portal ignores; `payment_records` is **never written** (`payment_screen.dart` only reads it). No SSLCommerz/bKash/Nagad code exists.
- **Data + endpoints needed:** either (a) **SSLCommerz production** `store_id`/`store_passwd` + the `/gwprocess` session API + an **IPN/callback URL**, or (b) a **DIU Finance API**: `GET /dues?studentId=` (outstanding by category), `POST /payment/initiate`, and a signed webhook `POST /payment/callback`.
- **Expected auth:** gateway store credentials (server-side only, **never in the app**) + HMAC-signed IPN verification; or DIU finance API key + webhook signature.
- **Assumed shape (ASSUMPTION):** SSLCommerz `initiate → { GatewayPageURL }`, then IPN `{ tran_id, val_id, status:"VALID", amount, ... }` which the server **re-validates** via `validationserverAPI`.
- **Where it plugs in:** **new edge functions** `payment-initiate` (creates a gateway session, returns the redirect URL the WebView loads) + `payment-ipn` (verifies the callback and writes `payment_records`). The WebView should load the **gateway session URL**, not a bare portal page, and the token injection should be removed. **Change size: large** — this is the biggest real build; ~20% done means only the shell exists.
- **Build vs university-only:** *I build* both edge functions, the `payment_records` write path, and re-point the WebView. *Only DIU/Finance provides* production gateway credentials (or their finance API) and authorization to collect real money.

### 3-E. DIU Hall / Residence office
- **What's faked & where:** all hall data is app-internal (`hall_applications`, `hall_complaints`, `get_hall_availability`). No external system.
- **Needed from DIU:** authoritative room inventory + current allocation, *if* AFOS must reflect the real hall office rather than be the system of record.
- **Auth/shape:** likely a spreadsheet export or a small internal API — **ASSUMPTION**: `GET /halls/{id}/rooms → [{room_no, capacity, occupied}]`.
- **Plug-in:** seed/sync `hall_*` tables via an import edge function. **Change size: small.** *Decision needed:* is AFOS the system of record (then no API needed) or a mirror (then need the office's data).

### 3-F. Transport live tracking
- **What's faked & where:** `transport_live_status` is read (`transport_repository.dart:34`) but **written by nothing**; `transport_stops` have no coordinates.
- **Needed:** a live GPS feed per bus (device or DIU transport system) → `{ route_id, lat, lng, updated_at }`; plus stop coordinates for real proximity.
- **Auth/shape (ASSUMPTION):** an MQTT/HTTP push from a tracker, or `GET /buses/live → [{route_id,lat,lng,speed,ts}]`.
- **Plug-in:** a producer writing `transport_live_status` (edge function ingesting the feed, or a driver-app). **Change size: medium**, but only if DIU wants live tracking; schedules already work without it.
- **Build vs university-only:** *I build* the ingestion function + map rendering (already present via `flutter_map`). *Only DIU provides* the GPS feed / tracker hardware access.

**Cross-cutting "I can build myself" list:** every edge-function proxy, every repository seam, sync/cron jobs, webhook verification, verified-identity UI, and caching. **"Only the university can provide":** SSO/SIS credentials + endpoints, registrar feed, library ILS API, production payment credentials, hall office data, and the bus GPS feed. In short — **I own all the plumbing; DIU owns all the data taps.**

---

## 4. Architecture Justification (report + viva)

### 4.1 Why Supabase (BaaS) over self-hosted Django / Rails
Grounded in how the repo is actually built:

**Why it was the right call for *this* project:**
- **Team of 2, 10-week timeline.** The repo shows a huge surface (25 feature folders, ~16 modules, realtime chat, push, storage) delivered by a 2-person team. Supabase gave **hosted Postgres + Auth + Realtime + Storage + Edge Functions on day one** — a Django/Rails equivalent means writing and hosting all of that (auth, WebSocket layer, file storage, migrations infra, deploy pipeline) before the first feature ships.
- **Security lives in the database, and it's actually used.** The app leans on **Row Level Security + SECURITY DEFINER triggers** as the real authorization layer — e.g. `handle_new_user()` role whitelisting, `is_verified` write-gates, and the delegated-admin `caller_can()`/`has_permission()` RBAC (migration `20260715120000`). The Flutter router guards are explicitly documented as *defense-in-depth only* ("RLS is still the real gate"). With Django/Rails you'd reimplement all of this in app-layer middleware; Postgres RLS enforces it even against a raw token hitting the REST endpoint directly.
- **Realtime for free.** Dept chat, club chat, the notification bell, and transport all use Supabase `.stream()`/realtime publications. In Django/Rails that's Channels/ActionCable + Redis + a WebSocket host to operate.
- **Auth + OAuth built in.** Email/password, domain enforcement, password-recovery deep links, and (future) OAuth SSO are all Supabase Auth primitives already wired (`auth_repository.dart`, `bootstrap.dart` recovery listener).
- **$0 free tier + zero DevOps.** No server to patch, scale, or monitor — critical for a student team with no ops budget. Edge Functions cover the few places that genuinely need server-side secrets (push REST key, service role) without standing up a backend.

**Honest trade-offs — where Django/Rails would have been *better*:**
- **Heavy custom business logic.** The seat-plan / routine parsing already strains the model: `parse-routine` had to push PDF text-extraction **back onto the phone** because the edge function's CPU/time budget crashed on multi-page PDFs (HTTP 546, documented in the function). A Django worker with no such limit would handle that cleanly.
- **Background jobs / cron.** There's no natural home for scheduled syncs (e.g. nightly registrar/library pulls in §3). That's a first-class citizen in Rails (ActiveJob/Sidekiq) / Django (Celery); on Supabase it's `pg_cron` + edge functions, which is workable but less ergonomic.
- **Complex logic in Postgres functions.** Real business rules currently live in SQL SECURITY DEFINER functions — powerful, but harder to test/debug/version than Ruby/Python service objects. Several past bugs were exactly "SQL trigger drift" (search_path pinning, role-vocabulary typos).
- **Vendor lock-in.** RLS policies, `auth.uid()`, edge functions, and realtime publications are Supabase-shaped. It's still Postgres underneath (portable data), but the *authorization model* would be a significant rewrite to leave.

**Verdict for the viva:** for a 2-person, 10-week, breadth-first university app whose security model is naturally row-level and whose realtime needs are first-class, **Supabase is the defensible, correct choice**; the honest caveat is that the few heavy-compute / scheduled-sync paths (PDF parsing, future API syncs) are where a custom backend would have paid off, and those are exactly the paths the university-API integration will add.

### 4.2 Where do the university APIs sit relative to Supabase?
**Recommendation: proxy every university API through Supabase Edge Functions — do not call them directly from Flutter.** Justified by the current code:

- **Secrets.** The pattern is already established: `send-notification` and `parse-routine` hold the OneSignal REST key and service-role key **server-side only**, never in the client. University credentials (SIS API key, SSLCommerz `store_passwd`, ILS token) are exactly the same class of secret — a Flutter app is publicly decompilable, so any key shipped in it is compromised. `supabase_config.dart` correctly ships only the **publishable/anon** key.
- **RLS stays authoritative.** If Flutter called DIU directly and wrote results to Supabase, the client would be trusted to write authoritative data (student identity, payment status) — breaking the whole RLS model. Routing through an edge function means the **service role** writes verified data server-side (e.g. `payment-ipn` writing `payment_records` only after HMAC validation), and RLS keeps clients read-only on it.
- **Stable seam / swap point.** §3 shows every integration has a clean edge-function insertion point (`verify-student`, `sync-routine`, `payment-initiate`/`payment-ipn`). This mirrors the existing `parse-routine` "mock (upload) → live (API)" swap with minimal blast radius.
- **The one exception:** an interactive **OAuth2/OIDC SSO login redirect** is handled by `supabase_flutter`'s own `signInWithOAuth` + deep-link listener (the recovery-link flow already proves this works) — that's a client-side redirect by design, but the **token exchange** and any SIS lookups still go server-side.

So: **university APIs sit *behind* Supabase Edge Functions, which write verified data into Postgres where RLS governs it.** Flutter only ever talks to Supabase.

---

## 5. Open Questions for Rakib (couldn't determine from code alone)

1. **Does DIU actually expose any of these APIs today?** The code assumes none exist yet (all mock/upload/self-declared). Which of SSO, SIS, library ILS, finance/payment, hall, transport are *real and reachable*, vs. "must be requested/built by the university"? This determines which letters you send.
2. **Payment scope for Phase-I:** is the plan to integrate **SSLCommerz/bKash production directly** (AFOS collects money) or to **defer to DIU's existing finance portal** (AFOS just deep-links)? The current stub implies the latter, but there's no working contract with the portal either way.
3. **Is AFOS the *system of record* for Hall, Library, Clubs, Mentorship — or a mirror of DIU offices?** For the self-contained modules this is a policy decision, not a code one. If system-of-record, several §3 dependencies disappear entirely.
4. **SSO vs verified self-registration:** do you want students to **log in with their DIU account** (full OAuth), or keep self-registration but **verify the typed student ID** against a SIS lookup? Both are supported by the architecture; they need different things from DIU.
5. **The delegated-admin + signup-hardening work is on `afos/delegated-admin`, not `main`.** Is that intended to merge before the Phase-I report is finalized? The role-escalation fix (account_type whitelist) is only real once merged + the migration is applied live.
6. **Push delivery status:** OneSignal web push is unconfigured and on-device delivery was only partially confirmed. Do you want that counted as "done" or "integration-pending" in the report?
7. **VR-ID's real purpose:** is it meant to eventually gate a **real** DIU access point (turnstile/library/exam hall), or is it purely a digital ID card? That decides whether it needs a hardware/backend integration or is already complete.
8. **`transport_live_status` producer:** is live bus tracking in scope at all? If not, drop the stub from the feature list; if yes, DIU needs to provide (or you need to build) the GPS feed.
