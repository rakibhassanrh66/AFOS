# CONTRACT_MAP — the data surface that must not change

Every later phase treats this as FROZEN. UI adapts to it; it never adapts to UI.

## Part A — repository / service methods (13 files, 53 public methods)

These are the documented contracts.

### `core/services/app_config_service.dart`
```dart
Future<void> ensureInit
Future<void> _load
Future<void> setSosEnabled
```

### `core/services/connectivity_service.dart`
```dart
Future<void> init
Future<bool> recheck
```

### `core/services/local_cache_service.dart`
```dart
Future<void> putList
Future<void> putMap
Future<void> clearIfVersionChanged
```

### `core/services/outbox_service.dart`
```dart
Future<String> enqueue
Future<bool> submitOrQueue
Future<void> flush
Future<void> retry
Future<void> discard
```

### `core/services/sos_location_service.dart`
```dart
Future<void> ping
```

### `features/assignments/data/repositories/assignments_repository.dart`
```dart
Future<void> createAssignment
Future<void> deleteAssignment
Future<void> gradeSubmission
Future<String?> signedAttachmentUrl
Future<void> submitAssignment
Future<String> uploadSubmissionFile
```

### `features/attendance/data/repositories/attendance_repository.dart`
```dart
Future<int> assignLabGroups
Future<void> setLabSubgroup
Future<String> createSession
Future<void> deleteSession
Future<void> updateRecord
Future<void> setAllStatuses
```

### `features/auth/data/repositories/auth_repository.dart`
```dart
Future<UserModel> signIn
Future<UserModel?> signUp
Future<void> forgotPassword
Future<void> signOut
Future<UserModel?> getCurrentUser
```

### `features/grades/data/repositories/marks_repository.dart`
```dart
Future<void> upsertMark
Future<int> syncAttendanceMarks
Future<void> submitResults
Future<void> reviewSubmission
```

### `features/schedule/data/repositories/academic_repository.dart`
```dart
Future<void> enroll
```

### `features/schedule/data/repositories/course_offering_repository.dart`
```dart
Future<String> resolveOrCreateCourse
Future<String> createOffering
Future<void> restoreOffering
Future<void> withdrawOffering
Future<int> approveOffering
Future<void> _pushOfferingAudience
Future<void> rejectOffering
Future<void> archiveOffering
Future<int> deleteOffering
Future<int> revokeOffering
Future<void> reopenOffering
Future<void> requestJoin
Future<void> _pushReviewers
Future<void> removeEnrollment
Future<void> reopenJoinRequest
Future<void> withdrawJoinRequest
Future<void> approveJoin
Future<void> rejectJoin
Future<void> sendCourseMessage
Future<void> deleteCourseMessage
```

### `features/schedule/data/repositories/schedule_repository.dart`
```dart
Future<ClassSlot?> findLabCounterpart
Future<void> pinSlot
Future<void> unpinSlot
Future<void> requestEmptyRoom
```

### `features/schedule/data/repositories/teaching_assignment_repository.dart`
```dart
Future<String?> fetchMyDepartment
Future<void> appointLeader
Future<void> revokeLeader
Future<void> respondToAssignment
Future<void> assign
Future<void> unassign
Future<void> markClaimed
```

## Part B — inline Supabase access (the UNDOCUMENTED contract)

33 of 62 screens bypass the repository layer and query Supabase directly. These
are just as much a contract as Part A, and they are easier to break by accident
because nothing names them. Every table/RPC touched from presentation code:

| screen | tables / rpcs touched |
|---|---|
| `admin/presentation/manage_clubs_screen.dart` | club_members club_membership_requests club_post_requests clubs  |
| `admin/presentation/manage_conference_rooms_screen.dart` | conference_room_requests  |
| `admin/presentation/manage_feedback_screen.dart` | feedback  |
| `admin/presentation/manage_users_screen.dart` | cr_requests permissions profiles roles students user_permissions  |
| `assignments/presentation/assignments_screen.dart` | assignments departments  |
| `auth/presentation/complete_profile_screen.dart` | profiles staff students teachers user_locations  |
| `clubs/presentation/club_chat_screen.dart` | club_members club_messages  |
| `clubs/presentation/clubs_screen.dart` | approve_club_membership_request club_events club_members club_membership_requests club_post_requests clubs event_registrations profiles reject_club_membership_request  |
| `conference_room/presentation/conference_room_screen.dart` | conference_room_requests  |
| `dashboard/presentation/dashboard_screen.dart` | borrowed_books club_membership_requests club_post_requests conference_room_requests course_offerings cr_requests feedback hall_applications notices offering_result_submissions profiles schedule_slots  |
| `dept_chat/presentation/dept_chat_screen.dart` | dept_channels dept_messages profiles user_settings  |
| `dept_chat/presentation/manage_dept_chat_screen.dart` | dept_channels dept_messages  |
| `exam_seat/presentation/exam_seat_screen.dart` | exam_room_allocations students  |
| `exam_seat/presentation/manage_exam_seats_screen.dart` | exam_room_allocations list_students_by_batch_section  |
| `feedback/presentation/feedback_screen.dart` | feedback  |
| `hall/presentation/hall_screen.dart` | get_hall_availability hall_applications hall_complaints profiles  |
| `hall/presentation/manage_hall_screen.dart` | hall_applications hall_complaints  |
| `library/presentation/library_screen.dart` | books borrowed_books  |
| `library/presentation/manage_library_screen.dart` | books borrowed_books profiles  |
| `lost_found/presentation/lost_found_screen.dart` | lost_found_claims lost_found_posts profiles  |
| `mentorship/presentation/mentorship_screen.dart` | mentors mentorship_bookings profiles  |
| `notifications/presentation/notification_center_screen.dart` | user_notifications  |
| `profile/presentation/profile_screen.dart` | profiles  |
| `registry/presentation/manage_notices_screen.dart` | notices  |
| `schedule/presentation/admin_upload_routine_screen.dart` | profiles  |
| `schedule/presentation/manage_course_offerings_screen.dart` | profiles  |
| `schedule/presentation/room_availability_screen.dart` | profiles  |
| `schedule/presentation/schedule_screen.dart` | profiles  |
| `settings/presentation/releases_screen.dart` | app_releases  |
| `settings/presentation/settings_screen.dart` | cr_requests profiles students user_locations user_settings  |
| `sos/presentation/sos_alert_detail_screen.dart` | profiles  |
| `transport/presentation/transport_screen.dart` | profiles  |
| `vr_id/presentation/vr_id_screen.dart` | issue_vr_id_token profiles verify_vr_id_scan vr_access_log  |

---

## DECISION — P2-04 is accepted debt, not a defect to fix here

**Taken 2026-08-15 by the project owner. Do not re-open inside a redesign phase.**

The register filed P2-04 as "data contract is undocumented and fragile: 33 of 62
screens call `SupabaseConfig.client.from(...)` inline instead of going through a
repository", effort XL. It was the last open item of the redesign. The decision
is to **leave the 33 screens as they are** and record why.

### Why not fix it

1. **It is the exact refactor that breaks this kind of app.** Moving a query
   changes who runs it, when, and under which auth context. RLS-dependent calls
   are the ones that fail *quietly* — they do not throw, they return zero rows,
   and a screen that renders an empty state on zero rows looks like it is
   working. A test suite of 310 widget and unit tests catches none of that,
   because none of them talk to Postgres.

2. **The contract is frozen by HARD RULE 2.** "Never change an inline Supabase
   query's shape." A faithful move preserves the shape exactly — at which point
   the only thing gained is where the call lives. That is a real architectural
   improvement and a poor trade during a phase whose brief is presentation.

3. **It is not blocking anything.** Part B below already enumerates the tables
   and RPCs each screen touches, which is what the phases actually needed: a
   list of what must not change. Every phase since has verified `git diff` on
   `lib/features/*/data`, `lib/core/services` and `lib/shared/models` is **0
   lines**, and it has been 0 across all of them.

### What was done instead

Part B is the deliverable: the inline-query contract, per screen, so a
"presentation-only" change can be checked against it. That is what made 12
batches of screen work safe.

### What would have to be true to revisit it

- Integration tests that run against a real Postgres with RLS enabled and a
  session per role — without those, a move is unverifiable, not merely risky.
- A reason beyond tidiness: a second consumer of the same query, an offline
  cache that needs a single choke point, or a query that has already drifted
  between two screens.
- Its own phase, one screen at a time, each verified on a device against a live
  session in every role that can reach it.

Until then the honest state is: **known, enumerated, deliberate.** An
architecture item recorded and left alone is not the same as one that was
missed, and this file is the difference.
