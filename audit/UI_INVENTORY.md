# UI_INVENTORY — every screen in AFOS

Generated 2026-08-15 by static analysis of `lib/features/**/*_screen.dart`.
Counts are measured, not estimated.

## How to read this

- **data** — `DIRECT` means the screen calls `SupabaseConfig.client.from(...)`
  or `.rpc(...)` inline. `repo` means it goes through a repository. A screen can
  do both. **`DIRECT` is the contract risk**: those queries are not covered by
  `CONTRACT_MAP.md`'s repository signatures, so a "presentation-only" refactor
  can still break data by touching them.
- **states** — which of the four required states are present:
  `L`=loading skeleton, `E`=empty, `R`=error. `-` means none found.
  A screen missing `L` will layout-shift when data lands.
- **slop** — count of hardcoded `Color(0x`, `LinearGradient`,
  `BorderRadius.circular(`, and `Duration(milliseconds:` in that file. This is
  the Phase 2 migration effort proxy.

| screen | LOC | state mgmt | data | states | slop |
|---|---:|---|---|---|---:|
| `admin/presentation/manage_clubs_screen.dart` | 335 | stateful | DIRECT | LER | 0 |
| `admin/presentation/manage_conference_rooms_screen.dart` | 231 | stateful | DIRECT | LER | 0 |
| `admin/presentation/manage_course_offerings_admin_screen.dart` | 491 | stateful | none+repo | ER | 1 |
| `admin/presentation/manage_feedback_screen.dart` | 202 | stateful | DIRECT | LER | 3 |
| `admin/presentation/manage_users_screen.dart` | 747 | stateful | DIRECT | LER | 3 |
| `assignments/presentation/assignment_submissions_screen.dart` | 340 | stateful | none+repo | LER | 6 |
| `assignments/presentation/assignments_screen.dart` | 522 | stateful | DIRECT+repo | LER | 6 |
| `attendance/presentation/attendance_register_screen.dart` | 498 | stateful | none+repo | LER | 6 |
| `attendance/presentation/attendance_screen.dart` | 609 | stateful | none+repo | LER | 5 |
| `attendance/presentation/my_attendance_screen.dart` | 256 | stateful | none+repo | LER | 2 |
| `auth/presentation/complete_profile_screen.dart` | 594 | stateful | DIRECT+repo | R | 5 |
| `auth/presentation/forgot_password_screen.dart` | 158 | stateful+bloc | none+repo | - | 0 |
| `auth/presentation/login_screen.dart` | 466 | stateful+bloc | none+repo | R | 6 |
| `auth/presentation/pending_approval_screen.dart` | 84 | stateful | none | - | 0 |
| `auth/presentation/register_screen.dart` | 678 | stateful+bloc | none+repo | R | 10 |
| `auth/presentation/reset_password_screen.dart` | 119 | stateful | none | - | 0 |
| `auth/presentation/unlock_screen.dart` | 150 | stateful | none | - | 0 |
| `clubs/presentation/club_chat_screen.dart` | 294 | stateful | DIRECT | LR | 4 |
| `clubs/presentation/clubs_screen.dart` | 849 | stateful | DIRECT | LER | 15 |
| `conference_room/presentation/conference_room_screen.dart` | 232 | stateful | DIRECT | LER | 3 |
| `dashboard/presentation/dashboard_screen.dart` | 1001 | stateful | DIRECT | L | 24 |
| `dept_chat/presentation/dept_chat_screen.dart` | 473 | stateful | DIRECT | LR | 13 |
| `dept_chat/presentation/manage_dept_chat_screen.dart` | 180 | stateful | DIRECT | LE | 5 |
| `exam_seat/presentation/exam_seat_screen.dart` | 200 | stateful | DIRECT | LER | 7 |
| `exam_seat/presentation/manage_exam_seats_screen.dart` | 165 | stateful | DIRECT | R | 1 |
| `feedback/presentation/feedback_screen.dart` | 185 | stateful | DIRECT | LER | 3 |
| `grades/presentation/grades_screen.dart` | 636 | stateful | none+repo | LER | 10 |
| `grades/presentation/marks_entry_screen.dart` | 564 | stateful | none+repo | LER | 6 |
| `hall/presentation/hall_screen.dart` | 657 | stateful | DIRECT | LR | 9 |
| `hall/presentation/manage_hall_screen.dart` | 598 | stateful | DIRECT | LER | 4 |
| `library/presentation/library_screen.dart` | 498 | stateful | DIRECT | LER | 19 |
| `library/presentation/manage_library_screen.dart` | 272 | stateful | DIRECT | LER | 5 |
| `lost_found/presentation/lost_found_screen.dart` | 696 | stateful | DIRECT | LER | 13 |
| `mentorship/presentation/mentorship_screen.dart` | 575 | stateful | DIRECT | LER | 13 |
| `notifications/presentation/notification_center_screen.dart` | 275 | stateful | DIRECT | LER | 5 |
| `payment/presentation/payment_screen.dart` | 277 | stateful | none | LR | 10 |
| `payment/presentation/payment_webview_screen.dart` | 164 | stateful | none | - | 0 |
| `portal/presentation/diu_portal_hub_screen.dart` | 106 | stateless | none | - | 0 |
| `portal/presentation/diu_portal_screen.dart` | 233 | stateful | none | R | 0 |
| `profile/presentation/profile_screen.dart` | 83 | stateful | DIRECT | L | 0 |
| `registry/presentation/manage_notices_screen.dart` | 247 | stateful | DIRECT | LER | 5 |
| `registry/presentation/registry_list_screen.dart` | 254 | stateful | none | LER | 4 |
| `schedule/presentation/admin_upload_routine_screen.dart` | 452 | stateful | DIRECT+repo | R | 5 |
| `schedule/presentation/browse_courses_screen.dart` | 405 | stateful | none+repo | ER | 2 |
| `schedule/presentation/course_group_screen.dart` | 397 | stateful | none+repo | LR | 1 |
| `schedule/presentation/join_request_detail_screen.dart` | 316 | stateful | none | R | 1 |
| `schedule/presentation/join_requests_screen.dart` | 986 | stateful | none+repo | LER | 5 |
| `schedule/presentation/manage_course_offerings_screen.dart` | 1129 | stateful | DIRECT+repo | ER | 9 |
| `schedule/presentation/module_leader_screen.dart` | 1167 | stateful | none+repo | LER | 5 |
| `schedule/presentation/room_availability_screen.dart` | 344 | stateful | DIRECT+repo | LR | 12 |
| `schedule/presentation/schedule_screen.dart` | 765 | stateful | DIRECT+repo | LER | 14 |
| `search/presentation/global_search_screen.dart` | 204 | stateful | none | LER | 1 |
| `settings/presentation/releases_screen.dart` | 263 | stateful | DIRECT | LE | 6 |
| `settings/presentation/settings_screen.dart` | 869 | stateful+bloc | DIRECT | LR | 9 |
| `sos/presentation/manage_sos_screen.dart` | 199 | stateful | none | LER | 4 |
| `sos/presentation/nearby_sos_screen.dart` | 121 | stateful | none | LER | 1 |
| `sos/presentation/sos_alert_detail_screen.dart` | 327 | stateful | DIRECT | LR | 2 |
| `splash/presentation/splash_screen.dart` | 377 | stateful | none | - | 12 |
| `transport/presentation/manage_stop_times_screen.dart` | 306 | stateful | none | LR | 4 |
| `transport/presentation/transport_import_preview_screen.dart` | 724 | stateful | none | R | 12 |
| `transport/presentation/transport_screen.dart` | 2357 | stateful | DIRECT+repo | LR | 20 |
| `vr_id/presentation/vr_id_screen.dart` | 388 | stateful | DIRECT | LR | 5 |
