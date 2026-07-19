# AFOS — UI Structure Report

> Read-only analysis of the existing Flutter app, prepared as input for a full UI redesign (Google Stitch). No code was modified. Screens/routes/paths are taken from live source; one-line purposes are inferred from the router, README, and slide-menu wiring where a screen file was not opened in full (flagged as *inferred*).

---

## 1. App Overview

- **App name:** AFOS — *All Facilities One System* (pubspec `name: afos_v7`, `AppConfig.appName = 'AFOS'`). Current version `1.1.2+11`.
- **Purpose:** A single, role-aware campus super-app for **Daffodil International University** that replaces scattered Google Forms / notice boards / WhatsApp with one login. Modules: class schedule, transport, hall allocation, library, lost & found, clubs, mentorship, department chat, grades/assignments, exam seating, payment, a rotating-QR digital ID (VR-ID), campus SOS, and push notifications. Backend is Supabase (Postgres + RLS + Auth + Realtime + Storage + Edge Functions); push via OneSignal; maps via OpenStreetMap/flutter_map.
- **Roles:** `student`, `teacher`, `staff`, `exam_controller`, `admin`, `dept_admin`, `super_admin`, plus a per-section `is_cr` (Class Representative) flag. UI (menu, dashboard, routes) adapts per role; RLS is the real gate.

### Target platforms actually built out
| Platform | Status | Evidence |
|---|---|---|
| **Android** | **Primary / production** | Full `AndroidManifest.xml` (location/foreground-service/audio perms, `afos://` password-reset deep link, Impeller disabled → Skia fallback, singleTop), custom `launch_background.xml`, launcher icons. |
| **Web** | **Primary / actively supported** | Hand-authored `web/index.html`: OneSignal Web SDK wiring, passkeys bootstrap shim, pre-boot canvas color, per-screen browser title (`web_title_web.dart`). Desktop-width responsive layouts (nav rail, login split-pane). |
| **iOS** | Configured / planned | `ios/Runner/Info.plist` + `LaunchScreen.storyboard` present; launcher-icon config in pubspec. README roadmap lists iOS store release for 2026. |
| **Windows / macOS / Linux** | Dev-only scaffold | Default runner files present (`main.cpp`, `my_application.cc`, `Info.plist`); `generated_plugin_registrant`/`generated_plugins` are the only changed files (plugin churn). Push/native features are best-effort no-ops on desktop (see `bootstrap.dart`). |

### State management
**Hybrid, BLoC-light.** `flutter_bloc` is used for three cross-cutting concerns only:
- `ThemeBloc` (`features/settings/bloc/theme_bloc.dart`) — theme mode + accent color, Hive-cached and Supabase-synced.
- `AuthBloc` (`features/auth/bloc/`) — login/auth flow (with `auth_event.dart` / `auth_state.dart`, `equatable`).
- `ShellBloc` (`features/shell/bloc/shell_bloc.dart`) — slide-menu open/close + selected index.

**Everything else is `StatefulWidget` + `setState`** calling Supabase directly from the widget (see `dashboard_screen.dart`, `settings_screen.dart`, `complete_profile_screen.dart`). `get_it` (`core/di/injection.dart`, `configureDependencies()`) provides DI. Some features add a `data/repositories/` layer (auth, schedule, grades, assignments, sos, transport, marks) but most screens skip it and query Supabase inline. `rxdart` + custom services back offline caching/outbox.

### Architecture pattern
**Feature-first**, with shared cross-cutting layers:
```
lib/
├── main.dart, bootstrap.dart          # entry + shared init sequence
├── config/
│   ├── app_config.dart, supabase_config.dart
│   ├── routes/app_router.dart         # single GoRouter
│   └── theme/                         # Liquid Glass design system (see §4)
├── core/                              # auth session, network, services (connectivity,
│                                        cache, outbox, badge, sos location), utils, di, data
├── shared/
│   ├── widgets/                       # reusable design-system components (see §4)
│   ├── models/user_model.dart
│   ├── animations/page_transitions.dart
│   └── extensions/
└── features/<feature>/
    ├── bloc/          (only auth, settings, shell)
    ├── data/          (models + repositories, where present)
    └── presentation/  (screens + feature widgets)
```
Feature folders: `admin, assignments, auth, clubs, conference_room, dashboard, dept_chat, exam_seat, feedback, grades, hall, library, lost_found, mentorship, notifications, payment, registry, schedule, settings, shell, sos, splash, transport, vr_id` (~138 Dart files total).

---

## 2. Screen Inventory

Shared building blocks used across nearly every screen: **`AfosAppBar`** (top bar w/ hamburger + notification bell + super-admin badge), **`GlassCard` / `SurfaceCard` / `GlassSheet`** (Liquid Glass surfaces), **`AfosButton`**, **`AfosTextField`**, **`ShimmerCard/List/Grid`** (loading), **`EmptyState`**, **`SupernovaLoader`**, **`PillBadge`**, **`AdminTabPill`**. Screens live inside `AppShell` (slide menu + offline banner + SOS floating button) unless noted.

### Auth & onboarding (outside the shell)
| Screen (class) | File | Route | Purpose | Notable UI |
|---|---|---|---|---|
| SplashScreen | `features/splash/presentation/splash_screen.dart` | `/splash` | Animated brand splash + session/last-route routing | See §7. Particle field, holo glow, animated A-F-O-S letters, scan bar. |
| LoginScreen | `features/auth/presentation/login_screen.dart` | `/auth/login` | Email/password sign-in | Two-pane on ≥1024px (`AuthBrandPanel` + capped form); glass card w/ animated entrance, grid-line CustomPaint backdrop, `flutter_animate` staggered fields. |
| RegisterScreen | `features/auth/presentation/register_screen.dart` | `/auth/register` | Multi-step signup (dept/role/address) | *Inferred* — multi-step form; grouped dropdowns; `slideUpPage` transition. |
| ForgotPasswordScreen | `features/auth/presentation/forgot_password_screen.dart` | `/auth/forgot-password` | Request password-reset email | *Inferred* — single-field form. |
| ResetPasswordScreen | `features/auth/presentation/reset_password_screen.dart` | `/reset-password` | Set new password after recovery link | Reachable outside `/auth` guard; triggered by `passwordRecovery` auth event. |
| CompleteProfileScreen | `features/auth/presentation/complete_profile_screen.dart` | `/complete-profile` | Forced profile-completion gate | See §8 (doubles as the app's Edit-Profile screen). Avatar, BD geography cascading dropdowns, GPS capture, gender chips, semester slider. |
| PendingApprovalScreen | `features/auth/presentation/pending_approval_screen.dart` | `/pending-approval` | "Awaiting super-admin approval" wall for new signups | *Inferred* — status/wait screen; gated by `RoleSession.ensureVerifiedLoaded()`. |

### Core / student modules (inside shell)
| Screen (class) | File | Route | Purpose | Notable UI |
|---|---|---|---|---|
| DashboardScreen | `features/dashboard/presentation/dashboard_screen.dart` | `/home` | Role-aware home: greeting, quick stats, live class status, module grid, latest notices | Hero `GlassCard`, `_LiteCard` module tiles (no per-row blur — perf budget), responsive max-extent grid, super-admin pending-queue strip, `flutter_animate` staggering, `RefreshIndicator`. |
| ScheduleScreen | `features/schedule/presentation/schedule_screen.dart` | `/schedule` | Personal class routine (batch/section or teacher initials) | *Inferred* — day/slot list filtered to user; search; parsed from routine PDF. |
| HallScreen | `features/hall/presentation/hall_screen.dart` | `/hall` | Hall seat apply / status / cancel / complaints (student-only) | *Inferred* — application status cards + forms. |
| TransportScreen | `features/transport/presentation/transport_screen.dart` | `/transport` | Bus routes, stop lookup, "find my route", map | *Inferred* — `flutter_map` (OSM) + route lists. |
| PaymentScreen | `features/payment/presentation/payment_screen.dart` | `/payment` | Fees/dues entry point (student-only) | *Inferred* — opens `PaymentWebViewScreen`. |
| PaymentWebViewScreen | `features/payment/presentation/payment_webview_screen.dart` | *(pushed, not in router)* | DIU student-portal payment in-app webview | `webview_flutter`; hardened token injection (recent commit). |
| LibraryScreen | `features/library/presentation/library_screen.dart` | `/library` | Catalogue, borrowing, fines (student-only) | *Inferred* — list + fine tracking (`libraryFinePerDay`). |
| LostFoundScreen | `features/lost_found/presentation/lost_found_screen.dart` | `/lost-found` | Post/claim lost & found items with photos | *Inferred* — image cards; contact reveal on accepted claim. |
| ClubsScreen | `features/clubs/presentation/clubs_screen.dart` | `/clubs` | Browse/join clubs, RSVP events | *Inferred* — club cards; role-gated actions. |
| ClubChatScreen | `features/clubs/presentation/club_chat_screen.dart` | *(pushed)* | Per-club realtime chat | *Inferred* — realtime message list. |
| MentorshipScreen | `features/mentorship/presentation/mentorship_screen.dart` | `/mentorship` | Book faculty mentor sessions (dept-matched) | *Inferred* — booking list/forms; outbox-queued requests. |
| ExamSeatScreen | `features/exam_seat/presentation/exam_seat_screen.dart` | `/exam-seat` | Personal exam seat plan (student-only) | *Inferred* — seat lookup from parsed PDF. |
| GradesScreen | `features/grades/presentation/grades_screen.dart` | `/grades` | Results / transcript (menu label "Results") | *Inferred* — results list; PDF transcript generation (`transcript_generator.dart`). |
| AssignmentsScreen | `features/assignments/presentation/assignments_screen.dart` | `/assignments` | Assignments list/submissions | *Inferred*. |
| DeptChatScreen | `features/dept_chat/presentation/dept_chat_screen.dart` | `/dept-chat` | Realtime department channels (role-scoped) | *Inferred* — realtime chat; chat-background setting. |
| VrIdScreen | `features/vr_id/presentation/vr_id_screen.dart` | `/vr-id` | Rotating-QR digital ID card + PDF proof | *Inferred* — QR card (`qr_flutter`), floating-tier glass, server-verified token, `pdf`/`printing`. Signature feature. |
| NotificationCenterScreen | `features/notifications/presentation/notification_center_screen.dart` | `/notifications` | Full notification history / notices | *Inferred* — list; realtime unread sync. |
| SettingsScreen | `features/settings/presentation/settings_screen.dart` | `/settings` | Profile + routine info + appearance + safety + account | See §8. Profile `GlassCard`, theme/accent pickers, notification-sound & chat-bg pickers, location-sharing switch, change-password/feedback sheets. |
| ReleasesScreen | `features/settings/presentation/releases_screen.dart` | `/releases` | "What's New" changelog | *Inferred*. |
| FeedbackScreen | `features/feedback/presentation/feedback_screen.dart` | `/feedback` | Feedback & contribution ideas | *Inferred* — form w/ optional file attach (also offered as a Settings sheet). |
| ConferenceRoomScreen | `features/conference_room/presentation/conference_room_screen.dart` | `/conference-room` | Conference-room booking (teacher/staff) | *Inferred*. |
| RoomAvailabilityScreen | `features/schedule/presentation/room_availability_screen.dart` | `/room-availability` | Free-room finder (teacher/CR) | *Inferred*. |
| NearbySosScreen | `features/sos/presentation/nearby_sos_screen.dart` | `/sos/nearby` | Nearby active SOS alerts | *Inferred* — map/list of nearby alerts. |
| SosAlertDetailScreen | `features/sos/presentation/sos_alert_detail_screen.dart` | `/sos/:id` | Single SOS alert detail | Takes `alertId` path param; *inferred* map + responder actions. |

### Admin / oversight (inside shell, role-guarded in router)
| Screen (class) | File | Route | Purpose (all *inferred* from name/menu) |
|---|---|---|---|
| AdminUploadRoutineScreen | `features/schedule/presentation/admin_upload_routine_screen.dart` | `/admin/upload` | Upload & parse routine/transport PDFs (edge fn `parse-routine`). |
| ManageHallScreen | `features/hall/presentation/manage_hall_screen.dart` | `/admin/hall` | Review/approve hall applications. |
| ManageLibraryScreen | `features/library/presentation/manage_library_screen.dart` | `/admin/library` | Library desk / checkout (admin + staff). |
| ManageUsersScreen | `features/admin/presentation/manage_users_screen.dart` | `/admin/users` | Approve/reject signups, CR requests, delete accounts (super_admin only). |
| ManageClubsScreen | `features/admin/presentation/manage_clubs_screen.dart` | `/admin/clubs` | Club management (super_admin). |
| ManageConferenceRoomsScreen | `features/admin/presentation/manage_conference_rooms_screen.dart` | `/admin/conference-rooms` | Conference-room admin (super_admin). |
| ManageFeedbackScreen | `features/admin/presentation/manage_feedback_screen.dart` | `/admin/feedback` | Triage feedback/contributions (super_admin). |
| ManageDeptChatScreen | `features/dept_chat/presentation/manage_dept_chat_screen.dart` | `/admin/dept-chat` | Moderate department chats. |
| ManageSosScreen | `features/sos/presentation/manage_sos_screen.dart` | `/admin/sos` | SOS alert oversight (admin + staff). |
| ManageNoticesScreen | `features/registry/presentation/manage_notices_screen.dart` | `/manage-notices` | Publish notices & rules (admin + teacher). |
| ManageExamSeatsScreen | `features/exam_seat/presentation/manage_exam_seats_screen.dart` | `/manage-exam-seats` | Assign exam seats (admin + exam_controller). |
| RegistryListScreen | `features/registry/presentation/registry_list_screen.dart` | `/admin/faculties`, `/admin/departments` | Generic CRUD list over a Supabase table (parametrized by `tableName`/`title`/`displayFields`). |

### Non-screen presentation widgets (part of the shell/chrome)
`shell/presentation/app_shell.dart` (`AppShell`), `slide_menu.dart` (`SlideMenu`), `top_app_bar.dart` (`AfosAppBar`), `notifications/presentation/notification_popover.dart` (bell tray), `sos/presentation/sos_floating_button.dart`, `auth/presentation/widgets/auth_brand_panel.dart`.

---

## 3. Navigation

- **Routing package:** `go_router: ^14.6.2`, single `GoRouter` in `config/routes/app_router.dart` (root + shell navigator keys). One `ShellRoute` wraps all authenticated screens in `AppShell`. Custom transitions via `shared/animations/page_transitions.dart` (`fadeScalePage`, `slideUpPage`, `slideRightPage`) plus a global `LiquidPageTransitionsBuilder` (fade + slight scale, reduced-motion aware).
- **Deep links:** `afos://` scheme (Android manifest) for password reset; OneSignal push taps route via `deep_link_route` payload (`bootstrap.dart`).

### Redirect / guard flow (`redirect` in app_router.dart)
1. `/splash` and `/reset-password` always pass.
2. No session → clear role, bounce to `/auth/login` (unless already under `/auth`).
3. Logged-in on `/auth/*` → `/home`.
4. Profile not completed → `/complete-profile` (forced).
5. Not verified → `/pending-approval` (new-signup approval gate).
6. Role guards: `/admin/*` requires admin-tier (staff allowed on `/admin/library` & `/admin/sos`); `/admin/users|clubs|conference-rooms|feedback` are super_admin-only; `/manage-notices` admin+teacher; `/manage-exam-seats` admin+exam_controller; `/hall`, `/exam-seat`, `/payment` hidden from teachers.
7. Current location saved via `saveLastRoute` for force-close resume.

### Entry-point flow
```
/splash ──(no session)──────────────► /auth/login ──► /auth/register / forgot-password
   │                                       └──► (password-reset email) ──► /reset-password
   └──(session)──► profile complete? ─no─► /complete-profile
                        │yes
                   verified? ─no─► /pending-approval
                        │yes
                   loadLastRoute() ?? /home  ──►  AppShell (SlideMenu ⇄ 40+ module routes)
```

### Navigation graph (how users move)
- **`AfosAppBar`** hamburger toggles **`SlideMenu`** (overlay drawer on mobile/tablet; fixed 248px rail on web ≥1024px) → pushes any module route. Menu contents are role-computed (`_effectiveItems` in `slide_menu.dart`).
- **Dashboard** module grid + featured/recommended card + "See all →" push into module & notification routes.
- **Notification bell** (`AfosAppBar`) → `notification_popover` tray → `/notifications`.
- **VR-ID** reachable from slide-menu header CTA and dashboard tile.
- **SOS floating button** (persistent on every shell screen) → SOS send flow; `/sos/nearby`, `/sos/:id`.
- **Back handling** (`AppShell._handleBack`): capped at 3 pops then jump to `/home`; back on `/home` asks exit-confirm.

---

## 4. Current Design System

The app has a **cohesive, deliberately-engineered "Liquid Glass" design system** — this is not an ad-hoc theme. Redesign work should treat these tokens as the current source of truth.

### Theme setup (`config/theme/`)
- `MaterialApp.router` in `main.dart` builds `buildLightTheme(accent:)` / `buildDarkTheme(accent:)`; `themeMode` driven by `ThemeBloc`. Material 3 (`useMaterial3: true`).
- **`liquid_glass_tokens.dart`** — single numeric source of truth: blur sigmas (`blurBase 10`, `blurRaised 18`, `blurFloating 24`), saturation boost 1.6, radii (`radiusCard 22`, `radiusCut 8`, `radiusSheet 28`, `radiusControl 14`), motion timings, and the **signature silhouette** (`signatureRadius()`: three corners rounded, top-right cut to 8px). `frost(sigma)` = blur + Rec.709 saturation matrix.
- **`liquid_glass_theme.dart`** — `LiquidGlassTheme` `ThemeExtension` (canvas/glassFill/glassBorder/ambientShadow/accent/accentSecondary), read via `LiquidGlassTheme.of(context)`; plus `LiquidPageTransitionsBuilder`.

### Color scheme (`config/theme/app_colors.dart` + `liquid_glass_tokens.dart`)
- **Two-accent cap:** brand **teal `#3ECF8E`** (primary, doubles as success) + **blue** family. Rainbow accents were intentionally removed — legacy names (`gold`, `pink`, `coral`, `orange`, `indigo`) now all resolve to teal/blue tints. **Do not reintroduce rainbow accents.**
- **Semantic hues kept:** `red #E25C74` (error/destructive), `amber #E0A83C` (warning/pending).
- **Functional violet:** `purple #8B7CD8` (`holoviolet`) reserved **only** as the super-admin/oversight signal.
- **Dark canvas ladder:** `background #0B1120` < `surface #101A2D` < `card #152238` < `cardHover #1B2B46`; borders `#25384F`/`#32506E`. **Light:** `lightBg #F4F6FB`, `lightCard #FFF`, tinted hairline borders.
- Tinted glass fills/borders (never grey), ambient teal/blue glow (never black drop shadow). Gradients: `heroGradient`, `holoGradient` (blue→teal→teal), `cardGlass`, etc. `moduleColors` map keys modules to (now tonal) accents.
- **Theme-aware helpers:** `textPrimaryOf/textSecondaryOf/surfaceOf/borderOf/glassFill/glassBorder(context)` — screens call these instead of raw hex so both modes read correctly.

### Typography (`config/theme/app_text_styles.dart` + theme builders)
- **Family: DM Sans** for everything (display → body), via `google_fonts` (runtime-fetched, **no bundled font files**). Display/headline tier is DM Sans at heavier weights (w700/w800) — a previous "Syne" display face was deliberately removed for consistency.
- **Mono: JetBrains Mono** (`monoMedium`, `monoSmall`) for IDs/version strings.
- Scale: `displayLarge 32/w800`, `displayMedium 24/w700`, `headlineLarge 20/w700`, `headlineMed 18/w700`, `titleLarge 16/w600`, `titleMedium 14/w600`, `bodyLarge 15`, `bodyMedium 13`, `labelSmall 11`. Negative letter-spacing on display sizes.

### Spacing / sizing (`config/theme/app_spacing.dart`)
- `AppSpacing`: xs 4 / sm 8 / md 16 / lg 24 / xl 32 / xxl 48.
- `AppRadius`: xs 4 / sm 8 / md 12 / lg 16 / xl 24 / full 999 (note: coexists with the Liquid Glass `radius*` tokens — two overlapping radius scales, see §10).
- **Responsive** (`core/utils/responsive.dart`): breakpoints medium 600 / expanded 1024; `AdaptiveContentWidth` (maxWidth 1100) letterboxes mobile-first content on wide screens.

### Design-token files
`config/theme/liquid_glass_tokens.dart`, `liquid_glass_theme.dart`, `app_colors.dart`, `app_text_styles.dart`, `app_spacing.dart`, `app_icons.dart` (centralized `IconData` registry, keyed to `moduleColors`), plus `dark_theme.dart` / `light_theme.dart` builders.

### Dark mode
**Yes — full light + dark + system**, first-class. `ThemeBloc` persists mode to Hive and accent color to Hive **+ Supabase `user_settings`** (follows the user across devices). User-selectable accent swatches in Settings. Both themes fully specified (colors, text, inputs, buttons, chips, sheets), and web pages are theme-styled.

### Reusable UI components (`lib/shared/widgets/`)
| Component | File | Role |
|---|---|---|
| `GlassCard` (+ `GlassTier` base/raised/floating) | `glass_card.dart` | Signature frosted card (BackdropFilter + saturation, tinted border/glow, press scale, entrance). Hero/summary panels. |
| `SurfaceCard` | `surface_card.dart` | Base-tier glass **without** BackdropFilter — for repeated list/grid rows (perf budget). |
| `GlassSheet` + `showGlassSheet()` | `glass_sheet.dart` | Floating-tier bottom sheet (heaviest frost, grab handle, entrance scale). |
| `AfosButton` | `afos_button.dart` | Primary CTA — gradient fill, hover/press scale, glow, loading `SupernovaLoader`, outlined variant, luminance-picked text color. |
| `AfosTextField` | `afos_text_field.dart` | Text field w/ focus glow, animated prefix icon, password toggle, obscure-aware autocorrect. |
| `AvatarPicker` | `avatar_picker.dart` | Avatar display + gallery pick/upload/remove (Supabase storage `avatars`). |
| `SupernovaLoader` / `SupernovaBusy` | `supernova_loader.dart` | Custom-painted rotating starburst spinner (replaces plain `CircularProgressIndicator`). |
| `ShimmerCard/List/Grid` | `shimmer_card.dart` | Skeleton loading (uses `shimmer`). |
| `EmptyState` | `empty_state.dart` | Icon + title + subtitle + optional action. |
| `ErrorView` | `error_view.dart` | Error state. |
| `PillBadge` | `pill_badge.dart` | Standard all-caps status/role/category pill (tight text-box centering). |
| `AdminTabPill` | `admin_tab_pill.dart` | Gradient pill tab selector for admin screens. |
| `LiquidBackdrop` | `liquid_backdrop.dart` | App canvas: flat color + two static low-alpha teal/blue radial washes (behind all shell content). |
| `OfflineBanner` | `offline_banner.dart` | Offline + outbox/pending-actions banner + queued-actions sheet. |
| `UserDetailsSheet` | `user_details_sheet.dart` | Shared user-detail bottom sheet. |

Feature-level shared chrome: `AfosAppBar` (`shell/presentation/top_app_bar.dart`), `SlideMenu`, `AppShell`, `AuthBrandPanel`, `notification_popover`, `SosFloatingButton`.

---

## 5. Assets & Media

- **Declared asset dirs (pubspec):** `assets/lottie/`, `assets/images/`. `uses-material-design: true`.
- **Image assets** (`assets/images/`): `diu_logo.png` (used on login + auth brand panel, with letter-fallback), `app_icon_source.png` (launcher-icon source for all platforms via `flutter_launcher_icons`), `.gitkeep`. Very small hand-authored image set; most real imagery is **remote** via `cached_network_image` (avatars, lost&found, club photos).
- **Icon set:** **Material rounded icons** throughout, centralized in `config/theme/app_icons.dart` (`AppIcons`). `cupertino_icons` is a dependency but Material is the actual style. `qr_flutter` renders the VR-ID QR. **No custom SVGs / icon font.**
- **Fonts:** **None bundled.** DM Sans + JetBrains Mono are pulled at runtime by `google_fonts`. No `fonts:` section in pubspec.
- **Lottie/Rive/animation asset files:** `assets/lottie/success.json` exists **but is an orphan** — there is **no `lottie` (or `rive`) package dependency and no code reference** to it anywhere in `lib/`. Motion is code-driven (`flutter_animate` + CustomPainters), not Lottie. *(Flag for redesign: either wire up or drop this asset.)*

---

## 6. Animation & Motion

- **Packages:** `flutter_animate: ^4.5.0` (primary — staggered fade/slide/scale entrances across login, dashboard, slide menu, notices, splash), `shimmer: ^3.0.0` (skeletons). **No `lottie`, `rive`, or `animations` package.** Hero animations not prominently used; page transitions are custom.
- **Custom-painted motion:** `SupernovaLoader` (rotating starburst), splash particle field / glow pulse / scan bar, login grid-line backdrop, auth brand-panel floating glow blobs.
- **Design-system motion:** `LiquidPageTransitionsBuilder` (global page fade+scale), `GlassCard`/`GlassSheet` press-scale + entrance, `AfosButton`/`_MenuTile`/`_ModuleCard` hover/press micro-interactions. All honor `MediaQuery.disableAnimations` (reduced motion).
- **Where used:** `splash_screen.dart`, `login_screen.dart`, `auth_brand_panel.dart`, `dashboard_screen.dart`, `slide_menu.dart`, `top_app_bar.dart` (bell pulse), plus most feature screens import `flutter_animate` for list entrances.
- **Perf caveat baked into the code:** the app has a documented jank history around app-wide `BackdropFilter`. Blur is budgeted — real frost only on hero cards/sheets (`GlassCard` raised/floating, `GlassSheet`); repeated rows use `SurfaceCard`/`_LiteCard` (no blur); `LiquidBackdrop` washes are static; `RepaintBoundary` used liberally.

---

## 7. Splash Screen (detail)

- **File:** `features/splash/presentation/splash_screen.dart` — route `/splash` (`initialLocation`). `StatefulWidget` + `TickerProviderStateMixin`.
- **Implementation summary:** Full-screen `Stack` on `AppColors.background (#0B1120)`:
  - Animated **particle field** (60 drifting dots, `_ParticlePainter`, 10s repeat).
  - **Radial holo-glow** pulse behind logo (`_glowCtrl`, 3s reverse).
  - **A-F-O-S letter tiles** (64×64, per-letter colored radial-gradient boxes) staggered in via `flutter_animate` (`slideY` + `fadeIn`, 300ms delays).
  - Sequential `AnimatedOpacity` reveals: tagline "All Facilities One System" (holo `ShaderMask`), "Daffodil International University", then a **scan bar** (`_ScanBarPainter`, sweeping highlight) + hardcoded `AFOS v7.2.9` label.
- **Duration & navigation trigger:** `_animate()` runs a fixed sequence — 2000ms → tagline, +500ms → sub, +500ms → team, +1500ms → navigate ≈ **~4.5s total**. Then: no session → `context.go('/auth/login')`; session present → `loadLastRoute() ?? '/home'` (router guards re-run on the target).
- **Native splash config:** No `flutter_native_splash` package. Native launch screens are hand-set to the canvas color to avoid a white flash:
  - Android: `android/app/src/main/res/drawable/launch_background.xml` (+ `-v21`) = solid `#FF0B1120`.
  - iOS: `ios/Runner/Base.lproj/LaunchScreen.storyboard` (default scaffold).
  - Web: `web/index.html` sets `html,body { background:#0B1120 }` pre-boot.
- ⚠️ **Redesign flags:** hardcoded version string `AFOS v7.2.9` (out of sync with pubspec `1.1.2+11` and `AppConfig.appVersion`); still uses deprecated `.withOpacity()`; per-letter colors are the old rainbow palette (teal/indigo/violet/red), inconsistent with the two-accent cap.

---

## 8. Profile Screen (detail)

Profile is split across **two screens** — a settings hub with an embedded profile card, and a dedicated editable form (which also serves as the onboarding gate).

### A) SettingsScreen — profile hub
- **File:** `features/settings/presentation/settings_screen.dart` — route `/settings`. `StatefulWidget` + direct Supabase.
- **Displays (read-only profile `GlassCard`):** `AvatarPicker` (tap to change/remove photo), then `_InfoTile`s — Name, Student/University ID, Email, Department, Semester (student) *or* Designation (teacher/staff), Role. "Edit Profile" button → pushes `/complete-profile`.
- **Also on this screen:** Routine Info (batch/section for students, teacher initials for teachers → writes `profiles` + mirrors `students`), Class Representative apply/status (students), Appearance (light/dark/auto chips + 7 accent swatches), Notification Sound, Chat Background, Campus Safety (location-sharing switch), Account (change password / send feedback / fix push — bottom sheets), App Info (version, What's New), and a gradient Log Out row.

### B) CompleteProfileScreen — the editable profile form
- **File:** `features/auth/presentation/complete_profile_screen.dart` — route `/complete-profile`. Forced gate for incomplete profiles; also the "Edit Profile" target.
- **Fields displayed/edited:** avatar (`AvatarPicker`), read-only Student/University ID + Email, **Full name**, **Phone**, Emergency contact, **Permanent address** via cascading BD-geography dropdowns (Division → District → Upazila → Thana for Dhaka Mahanagar, from `core/data/bd_geography.dart`), **Gender** chips, **Department** (`DropdownButtonFormField` from DB), role-specific: teacher **Designation** / staff **Designation** (grouped dropdown) / student **Batch + Section + Semester slider (1–12)** / admin-tier none, and **mandatory live GPS capture** ("Confirm my location", stored to `user_locations`). Saves across `profiles`/`students`/`teachers`/`staff`; every field individually try/caught (hardening against partial-load bugs).
- **Avatar/image handling:** centralized in `shared/widgets/avatar_picker.dart` — `image_picker` (gallery, quality 70) → `StorageUploadService.uploadImage(bucket:'avatars')` (uses `flutter_image_compress`) → writes `profiles.avatar_url`; remove sets it null. Display via `cached_network_image` with initials fallback. Same widget reused in Settings, Complete-Profile, and the slide-menu header avatar.

---

## 9. Dependencies Relevant to UI

From `pubspec.yaml` (`version: 1.1.2+11`, SDK `>=3.3.0 <4.0.0`):

```yaml
# Navigation
go_router: ^14.6.2

# State / DI (used by a few blocs)
flutter_bloc: ^8.1.6
equatable: ^2.0.5
get_it: ^8.0.2

# UI / theming / typography
google_fonts: ^6.2.1          # DM Sans + JetBrains Mono (runtime-fetched, none bundled)
cupertino_icons: ^1.0.8       # dependency present; Material icons actually used

# Animation / loading
flutter_animate: ^4.5.0       # primary motion system
shimmer: ^3.0.0               # skeleton loaders
# (NO lottie / rive / animations package — but assets/lottie/success.json exists, unused)

# Images / media
cached_network_image: ^3.4.1  # all remote imagery (avatars, items, clubs)
image_picker: ^1.1.2          # avatar / photo capture
flutter_image_compress: ^2.3.0

# Feature-UI-adjacent
qr_flutter: ^4.1.0            # VR-ID QR rendering
mobile_scanner: ^6.0.2        # QR scanning
webview_flutter: ^4.10.0      # payment portal webview
flutter_map: ^7.0.2           # transport / SOS maps (OpenStreetMap)
latlong2: ^0.9.1
pdf: ^3.11.1                  # VR-ID proof / transcripts
printing: ^5.13.2
syncfusion_flutter_pdf: ^27.2.5  # PDF parsing (routine/exam-room)
file_picker: ^8.1.2          # feedback attachments
open_file: ^3.5.8

# Platform / plumbing that touches UX
onesignal_flutter: ^5.2.5    # push (native); web push wired in web/index.html
supabase_flutter: ^2.8.0     # backend + realtime
hive_flutter: ^1.1.0         # local settings/cache (theme, accent, offline)
connectivity_plus: ^6.1.1    # drives OfflineBanner
app_badge_plus: ^1.1.3       # app icon unread badge
flutter_background_service: ^5.1.0  # SOS ambient location
geolocator: ^13.0.2          # location capture
intl / timeago                # date + relative-time formatting in UI
```
`flutter_launcher_icons: ^0.14.3` (dev) generates icons for android/ios/web/windows/macos from `assets/images/app_icon_source.png` (web/theme color `#060D1F`).

---

## 10. Pain Points / Inconsistencies

1. **Deprecated `Color.withOpacity()` still widespread** — **80 occurrences across 19 files** (splash, login, dashboard, slide_menu, settings, transport, vr_id, empty_state, etc.), mixed alongside the newer `.withValues(alpha:)` used elsewhere in the *same* files. Inconsistent and deprecation-warning-prone; the redesign should standardize on `.withValues()`.
2. **Two overlapping radius/spacing scales.** `AppRadius`/`AppSpacing` (`app_spacing.dart`) coexist with the Liquid Glass `radiusCard/radiusControl/...` tokens. Screens mix both plus ad-hoc literals (`BorderRadius.circular(10/12/14/16/18/20/22)` seen across dashboard, settings, slide_menu). No single radius truth.
3. **Palette drift / legacy names.** `AppColors.gold/pink/coral/orange/indigo` are historical rainbow names now folded to teal/blue tints — but call sites still *read* as rainbow (e.g. dashboard `moduleColors`, menu item colors, `_NoticeCard` category colors), and the **splash letters + login logo fallback still use genuinely different hues** (teal/indigo/violet/red), contradicting the documented two-accent cap. Easy to accidentally reintroduce rainbow.
4. **Hardcoded/stale version strings.** Splash shows `AFOS v7.2.9` while pubspec is `1.1.2+11`; `AppConfig.appVersion` fallback is `1.1.1` (corrected at runtime via `PackageInfo`, but the splash string is never updated).
5. **Orphan Lottie asset.** `assets/lottie/success.json` is declared and shipped but has no package/consumer — dead weight.
6. **Duplicated inline patterns instead of shared widgets.** The gradient "Log Out" row is hand-rolled nearly identically in both `settings_screen.dart` and `slide_menu.dart`; several screens hand-roll `_Section`/`_InfoTile`/`_ActionTile`/`_Chip`/`_ThemeChip`/`_GenderChip` locally rather than via `shared/widgets` — the design system exists but isn't uniformly adopted.
7. **Inconsistent loading & state widgets.** `SupernovaLoader` is the intended spinner, yet `complete_profile_screen.dart` still uses plain `CircularProgressIndicator` in multiple spots; loading states mix `ShimmerList/Grid` vs raw spinners across screens.
8. **State-management inconsistency.** BLoC for theme/auth/shell but `setState` + inline Supabase queries everywhere else; a `data/repositories` layer exists for some features and is bypassed by others — no consistent data-access pattern for the UI to bind to.
9. **Text-box vertical-centering worked around repeatedly.** Many widgets carry the same `TextHeightBehavior(applyHeightToFirstAscent:false, applyHeightToLastDescent:false)` + `height:1.0` fix for all-caps pills/badges (PillBadge, AdminTabPill, top_app_bar badge, notice category tag, notification count) — a recurring symptom that a redesign could solve once at the type-scale level.
10. **`AppSpacing`/`AppRadius` under-used.** Despite existing, most padding/margins are literal `EdgeInsets.all(12/14/16/20/24)` rather than the tokens — spacing rhythm is effectively ad-hoc per screen.
11. **Icon style dependency mismatch.** `cupertino_icons` is declared but the app is Material-rounded throughout; a couple of module colors/icons are defined in both `AppColors.moduleColors`/`AppIcons.moduleIcons` *and* re-specified inline per screen (dashboard `_allModules`, slide_menu `_MenuItem`s) — three parallel sources for the same module identity.
