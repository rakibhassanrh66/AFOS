# Mandatory Profile Completion + Role-Grouped User Directory — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Collect the identity data AFOS is missing (intake term, ID-card join date, address, personal phone) from every user — new and existing — by making profile completeness a fact the SERVER computes, then group the admin user directory by role with real per-role hierarchies.

**Architecture:** `profile_completed` stops being a boolean the client sets and becomes a value a `BEFORE INSERT OR UPDATE` trigger computes from the actual columns, per role. The router gate that already exists (`if (!completed) return '/complete-profile'`) then does the forcing for free — the moment the trigger recomputes an existing user as incomplete, that user is redirected on their next navigation, with no migration of user state and no new gate to build. The directory groups on the columns this fills.

**Tech Stack:** Flutter (Dart, `afos_v7`), Supabase Postgres 17 + RLS, `go_router`, pg_trgm.

**Spec:** This document. Requirements captured from the owner 2026-08-22 (see "Requirements as stated" below).

---

## Global Constraints

Copied from `CLAUDE.md`; every task inherits these.

- **NEVER change a repository/service method signature or return type**, and never change an inline Supabase query's shape. UI adapts to existing data.
- Migrations are allowed during feature work. Each one must be (a) mirrored into `supabase/migrations/` named with the version the **REMOTE LEDGER** assigned, not wall clock, (b) verified **behaviourally**, not by reading the definition back, (c) reported exactly.
- **Never bulk-rewrite Dart with PowerShell** `Get-Content`/`Set-Content` — it mojibakes non-ASCII and adds a BOM while `analyze` stays green. Use the Edit tool.
- Radius scale ONLY: 4 / 10 / 20 / full. Spacing ONLY: 4 / 8 / 12 / 16 / 24 / 32 / 48. Motion tokens only. No inline `Color(0x...)` outside the theme.
- No emoji in UI copy. Touch targets >= 48dp. Contrast >= 4.5:1. Responsive to 320px.
- `flutter analyze` must report **0 issues** and the full `flutter test` suite must pass (**506 tests** at plan time) before any task is called done.
- The repo is **PUBLIC**. No real student records, IDs, or personal data in tests, fixtures, or commits.

---

## Requirements as stated

> "all new user need to mention on the register page with total details also address and home details personal number, also mention that in future those numbers could be verified using the code and manual direct call confirmation, but make it mock so user forced to share their original data without fake data. also existing user will immediately ask to fulfil these so once they complete they don't have to worry, anything can use all things, without these they can't. so the moment they add, automatically the database should grab them and show what we need."

> "same as we asked and also teacher joined too, and also for student will asked to add the join date based on their ID card time mentioned"

Directory (answered separately): **grouped sections**, a separate place per role — teacher grouped department-wise then year; staff/officer by sector/management then year then role; student by season (Fall/Summer/Spring) then year then batch. Scope: **directory + approval queue**.

---

## Measured starting state (2026-08-22, live DB)

Do not re-derive these; they are why the plan is shaped this way.

| Fact | Value |
|---|---|
| `profiles` rows | 14 |
| Flagged `profile_completed` | **14 / 14** |
| Has `phone` | 7 / 14 |
| Has `permanent_division` / `district` / `upazila` | 7 / 14 |
| Has `permanent_thana` | 3 / 14 |
| Has `emergency_contact` | 3 / 14 |
| Has `gender` | 14 / 14 |
| `teachers.joining_date` / `staff.joining_date` populated | **0 / 6** |
| Student admission season/year column | **does not exist** |
| `batches` rows (and NOT linked to `profiles.batch`) | 3 |
| `staff.category` populated | yes ("Executive Leadership & Top Administration") |

**The core defect:** every account is marked complete while half the required data is absent, because the client writes `profile_completed: true` at `complete_profile_screen.dart:271`. Completeness is currently an opinion held by the client, not a fact about the row.

**Existing machinery to reuse, not rebuild:**
- `app_router.dart:106-111` — the gate: `/complete-profile` is exempt, everything else redirects when incomplete.
- `role_session.dart:61-65` — loads the flag; `?? true` means a fetch failure fails OPEN.
- `complete_profile_screen.dart` (599 lines) — already collects name, phone, emergency contact, division/district/upazila/thana, gender, department, designation, batch/section/semester.

---

## File Structure

**Phase A — the data and the gate**
- Create: `supabase/migrations/<ledger>_profile_completeness_is_a_fact_not_a_claim.sql` — new columns, the completeness function, the trigger, the mirror to `teachers`/`staff`.
- Modify: `lib/features/auth/presentation/complete_profile_screen.dart` — add intake term, ID-card join date, make emergency contact required; add the mock-verification notice.
- Modify: `lib/core/auth/role_session.dart:65` — `?? true` must become `?? false` for the completeness flag only.
- Create: `test/profile_completeness_test.dart` — the required-field matrix per role.

**Phase B — the directory** (separate plan, depends on Phase A columns)
- Create: `lib/features/admin/presentation/widgets/user_group_tree.dart` — the grouped-section list.
- Modify: `lib/features/admin/presentation/manage_users_screen.dart` — role segmentation + approval queue restyle.
- Create: `supabase/migrations/<ledger>_admin_user_groups.sql` — a grouping/count RPC.

> **Scope note:** Phase B is a genuinely separate subsystem and should be split into its own plan file once Phase A lands, since Phase A changes the columns Phase B groups on. Phase A alone produces working, shippable software.

---

## PHASE A

### Task 1: The columns the requirement needs

**Files:**
- Create: `supabase/migrations/<ledger>_profile_completeness_is_a_fact_not_a_claim.sql`

**Interfaces:**
- Produces: `profiles.admission_season text`, `profiles.admission_year int`, `profiles.joined_on date`, and `profile_is_complete(profiles) -> boolean`.

Three new columns on `profiles`. **`joined_on` is deliberately ONE column, not one per role table** — `teachers.joining_date` and `staff.joining_date` already exist and are 100% NULL, and this project has already been burned once by exactly this shape: `set_teacher_initial()` wrote `teachers.teacher_initial` while the directory read `profiles.teacher_initial`, so two teachers silently had no duties. One writer, mirrored outward.

- [ ] **Step 1: Write the migration**

```sql
alter table profiles
  add column if not exists admission_season text
    check (admission_season is null or admission_season in ('spring','summer','fall')),
  add column if not exists admission_year int
    check (admission_year is null or (admission_year between 2000 and 2100)),
  -- "the join date based on their ID card time mentioned" — for a student this
  -- is the date printed on the card; for a teacher or officer it is the date
  -- they joined the university. One concept, one column, mirrored below.
  add column if not exists joined_on date;

comment on column profiles.joined_on is
  'Date printed on the ID card (student) or date of joining (teacher/staff). '
  'SOURCE OF TRUTH. teachers.joining_date and staff.joining_date are mirrors '
  'kept in sync by trg_profile_completeness -- never write them directly.';
```

- [ ] **Step 2: Apply it and verify the columns exist and the CHECKs bite**

Run, as a real authenticated admin inside a transaction that rolls back:

```sql
begin;
insert into profiles (id, full_name, role, admission_season)
values (gen_random_uuid(), 'probe', 'student', 'autumn');
rollback;
```

Expected: FAILS on the `admission_season` check ('autumn' is not one of spring/summer/fall). If it succeeds, the check did not apply — stop and fix before continuing.

- [ ] **Step 3: Mirror the file into `supabase/migrations/` under the LEDGER version**

```sql
select version from supabase_migrations.schema_migrations order by version desc limit 1;
```

Name the file with **that** value, not the wall clock.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/
git commit -m "Profile intake term, ID-card join date, and one column for both"
```

---

### Task 2: Completeness becomes a fact the server computes

**Files:**
- Modify: the same migration (or a follow-on migration if Task 1 is already applied)
- Test: `test/profile_completeness_test.dart`

**Interfaces:**
- Consumes: the columns from Task 1.
- Produces: `profile_is_complete(p profiles) returns boolean`, trigger `trg_profile_completeness`.

The required set, per role. Confirm this table with the owner before implementing — it is the whole contract:

| Field | Student | Teacher | Staff/Officer | Admin roles |
|---|:--:|:--:|:--:|:--:|
| full_name, phone, gender | ✅ | ✅ | ✅ | ✅ |
| emergency_contact | ✅ | ✅ | ✅ | ✅ |
| permanent_division / district / upazila | ✅ | ✅ | ✅ | ✅ |
| permanent_thana | optional | optional | optional | optional |
| department_id | ✅ | ✅ | — | — |
| batch, section, semester | ✅ | — | — | — |
| admission_season, admission_year | ✅ | — | — | — |
| joined_on | ✅ | ✅ | ✅ | — |
| designation | — | ✅ | ✅ | — |

`permanent_thana` stays optional because it only applies to city-corporation addresses — 3 of 14 have it, and requiring it would wedge every rural address permanently.

- [ ] **Step 1: Write the failing test**

`test/profile_completeness_test.dart` — a pure Dart mirror of the rule, so the matrix is pinned somewhere a reviewer can read without a database. No real personal data (public repo).

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:afos_v7/core/auth/profile_completeness.dart';

void main() {
  Map<String, dynamic> base(String role) => {
        'role': role,
        'full_name': 'A Name', 'phone': '01700000000', 'gender': 'male',
        'emergency_contact': 'Someone 01700000001',
        'permanent_division': 'Dhaka', 'permanent_district': 'Dhaka',
        'permanent_upazila': 'Savar',
        'department_id': 'd0000000-0000-0000-0000-000000000000',
        'batch': '68', 'section': 'D', 'semester': 5,
        'admission_season': 'summer', 'admission_year': 2026,
        'joined_on': '2026-01-15', 'designation': 'Lecturer',
      };

  test('a fully filled student is complete', () {
    expect(isProfileComplete(base('student')), isTrue);
  });

  test('a student with no intake term is NOT complete', () {
    final p = base('student')..['admission_season'] = null;
    expect(isProfileComplete(p), isFalse);
  });

  test('a student with no ID-card join date is NOT complete', () {
    final p = base('student')..['joined_on'] = null;
    expect(isProfileComplete(p), isFalse);
  });

  test('a blank string is not a filled field', () {
    final p = base('student')..['phone'] = '   ';
    expect(isProfileComplete(p), isFalse);
  });

  test('a teacher needs joined_on and designation but NOT batch', () {
    final p = base('teacher')..['batch'] = null..['section'] = null;
    expect(isProfileComplete(p), isTrue);
    expect(isProfileComplete(base('teacher')..['joined_on'] = null), isFalse);
  });

  test('thana is optional for everyone', () {
    expect(isProfileComplete(base('student')..['permanent_thana'] = null), isTrue);
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `C:\RakibFlutter\bin\flutter.bat test test/profile_completeness_test.dart`
Expected: FAIL — `profile_completeness.dart` does not exist.

- [ ] **Step 3: Write the Dart rule**

Create `lib/core/auth/profile_completeness.dart`. **A blank string is not null** — this project has already shipped that bug once (`department = ''` defeated `?? 'default'` and rendered an empty chip), so the helper normalises before testing.

```dart
/// Mirrors `profile_is_complete()` in Postgres. The DATABASE is the authority
/// -- this exists so the client can grey out "Save" and so the rule is pinned
/// by a test without a live connection. If the two ever disagree, the SQL wins
/// and this file is the bug.
bool _has(Object? v) => v != null && v.toString().trim().isNotEmpty;

bool isProfileComplete(Map<String, dynamic> p) {
  final role = (p['role'] ?? '').toString();
  final everyone = _has(p['full_name']) && _has(p['phone']) &&
      _has(p['gender']) && _has(p['emergency_contact']) &&
      _has(p['permanent_division']) && _has(p['permanent_district']) &&
      _has(p['permanent_upazila']);
  if (!everyone) return false;

  switch (role) {
    case 'student':
      return _has(p['department_id']) && _has(p['batch']) &&
          _has(p['section']) && _has(p['semester']) &&
          _has(p['admission_season']) && _has(p['admission_year']) &&
          _has(p['joined_on']);
    case 'teacher':
      return _has(p['department_id']) && _has(p['designation']) &&
          _has(p['joined_on']);
    case 'staff':
      return _has(p['designation']) && _has(p['joined_on']);
    default:
      return true; // admin/super_admin carry no academic identity
  }
}
```

- [ ] **Step 4: Run the test — expect PASS**

Run: `C:\RakibFlutter\bin\flutter.bat test test/profile_completeness_test.dart`

- [ ] **Step 5: Write the Postgres authority + trigger**

`designation` lives in `teachers`/`staff`, not `profiles`, so the SQL reads across. A **BEFORE INSERT OR UPDATE trigger**, not a `GENERATED` column and not a `CHECK`: the client at `complete_profile_screen.dart:271` still writes `profile_completed: true`, and a generated column would make that write throw. The trigger silently overwrites the claim with the truth, so no client breaks. (A `NOT VALID CHECK` is also wrong here — this project already learned it still blocks UPDATEs and makes violating rows permanently un-editable.)

```sql
create or replace function profile_is_complete(p profiles)
returns boolean language sql stable set search_path to 'public' as $$
  select
    nullif(btrim(coalesce(p.full_name,'')),'')          is not null
    and nullif(btrim(coalesce(p.phone,'')),'')          is not null
    and nullif(btrim(coalesce(p.gender,'')),'')         is not null
    and nullif(btrim(coalesce(p.emergency_contact,'')),'') is not null
    and nullif(btrim(coalesce(p.permanent_division,'')),'')  is not null
    and nullif(btrim(coalesce(p.permanent_district,'')),'')  is not null
    and nullif(btrim(coalesce(p.permanent_upazila,'')),'')   is not null
    and case p.role
      when 'student' then
        p.department_id is not null
        and nullif(btrim(coalesce(p.batch,'')),'')   is not null
        and nullif(btrim(coalesce(p.section,'')),'') is not null
        and p.semester is not null
        and p.admission_season is not null
        and p.admission_year  is not null
        and p.joined_on       is not null
      when 'teacher' then
        p.department_id is not null and p.joined_on is not null
        and exists (select 1 from teachers t
                     where t.profile_id = p.id
                       and nullif(btrim(coalesce(t.designation,'')),'') is not null)
      when 'staff' then
        p.joined_on is not null
        and exists (select 1 from staff s
                     where s.profile_id = p.id
                       and nullif(btrim(coalesce(s.designation,'')),'') is not null)
      else true
    end
$$;

create or replace function tg_profile_completeness()
returns trigger language plpgsql set search_path to 'public' as $$
begin
  -- The client's claim is ignored; the row decides.
  new.profile_completed := profile_is_complete(new);

  -- ONE writer for the join date. teachers/staff keep their own column so
  -- existing readers do not break, but they are mirrors, never sources.
  if new.joined_on is distinct from coalesce(old.joined_on, null) then
    update teachers t set joining_date = new.joined_on where t.profile_id = new.id;
    update staff    s set joining_date = new.joined_on where s.profile_id = new.id;
  end if;
  return new;
end $$;

drop trigger if exists trg_profile_completeness on profiles;
create trigger trg_profile_completeness
  before insert or update on profiles
  for each row execute function tg_profile_completeness();
```

- [ ] **Step 6: Verify BEHAVIOURALLY that a client cannot lie**

```sql
begin;
set local role authenticated;
-- pick a real incomplete profile id first
update profiles set profile_completed = true
 where id = '<an incomplete profile id>';
select profile_completed from profiles where id = '<same id>';
rollback;
```

Expected: `profile_completed` reads **false** despite the update setting it true. If it reads true, the trigger is not firing — stop.

- [ ] **Step 7: Re-seat every existing row through the trigger**

```sql
update profiles set updated_at = updated_at;  -- no-op write, fires the trigger
select role, count(*) filter (where profile_completed) as complete, count(*) as total
  from profiles group by role order by role;
```

Expected: the 14/14 becomes a smaller number. **Record the before and after and report both** — this is the moment every existing user is asked to fill their details, so its size is the blast radius.

- [ ] **Step 8: Commit**

```bash
git add supabase/migrations/ lib/core/auth/profile_completeness.dart test/profile_completeness_test.dart
git commit -m "Profile completeness is computed from the row, not claimed by the client"
```

---

### Task 3: Close the fail-open hole in the gate

**Files:**
- Modify: `lib/core/auth/role_session.dart:65`

`_profileCompleted = row?['profile_completed'] as bool? ?? true;` fails **open**: if the fetch throws or the row is missing, the user is treated as complete and walks straight past the gate. That was defensible when the flag was cosmetic; now it is the enforcement point.

- [ ] **Step 1: Write the failing test**

Add to `test/profile_completeness_test.dart`:

```dart
test('a missing profile row is NOT treated as complete', () {
  expect(isProfileComplete(<String, dynamic>{}), isFalse);
});
```

- [ ] **Step 2: Run it**

Run: `C:\RakibFlutter\bin\flutter.bat test test/profile_completeness_test.dart`
Expected: FAIL — an empty map currently falls to `default: return true`.

- [ ] **Step 3: Fix both the Dart rule and the session default**

In `profile_completeness.dart`, an absent role is not an admin:

```dart
    default:
      // An absent role is an unknown row, not a privileged one.
      return _has(p['role']);
```

In `role_session.dart:65`, change **only the completeness line** (leave `_isVerified ?? true` alone — verified fails open deliberately, to grandfather pre-gate accounts):

```dart
      // Fails CLOSED. An unreadable profile must not walk past the completion
      // gate; the worst case is one extra trip through a form they can fill.
      _profileCompleted = row?['profile_completed'] as bool? ?? false;
```

- [ ] **Step 4: Run the full suite**

Run: `C:\RakibFlutter\bin\flutter.bat test`
Expected: **507 passing** (506 + the new file's cases), 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/core/auth/role_session.dart lib/core/auth/profile_completeness.dart test/profile_completeness_test.dart
git commit -m "The completion gate fails closed"
```

---

### Task 4: Collect the new fields, and say the numbers will be checked

**Files:**
- Modify: `lib/features/auth/presentation/complete_profile_screen.dart`

Three additions, plus one notice. Keep the existing `AfosTextField` / `_AddressDropdown` / `_GenderChip` patterns — do not introduce a second form vocabulary.

- [ ] **Step 1: Make emergency contact required**

At `complete_profile_screen.dart:363` it has no validator. Add one, matching the phone field's shape:

```dart
AfosTextField(hint: 'Emergency contact (name + phone)', controller: _emergencyCtrl,
    validator: (v) => AppValidators.required(v, f: 'Emergency contact')),
```

- [ ] **Step 2: Add the intake term (students only)**

Inside the existing `if (_role == 'student')` block that holds batch/section/semester:

```dart
Row(children: [
  Expanded(
    child: DropdownButtonFormField<String>(
      value: _admissionSeason,
      decoration: InputDecoration(hintText: 'Admission season', filled: true,
          border: OutlineInputBorder(borderRadius: AppDepth.radius(1))),
      items: const [
        DropdownMenuItem(value: 'spring', child: Text('Spring')),
        DropdownMenuItem(value: 'summer', child: Text('Summer')),
        DropdownMenuItem(value: 'fall',   child: Text('Fall')),
      ],
      onChanged: (v) => setState(() => _admissionSeason = v),
      validator: (v) => v == null ? 'Admission season is required' : null,
    ),
  ),
  const SizedBox(width: AppSpace.sm),
  Expanded(
    child: AfosTextField(hint: 'Admission year (e.g. 2023)',
        controller: _admissionYearCtrl, keyboardType: TextInputType.number,
        validator: (v) {
          final y = int.tryParse((v ?? '').trim());
          if (y == null) return 'Admission year is required';
          if (y < 2000 || y > 2100) return 'Enter a 4-digit year';
          return null;
        }),
  ),
]),
```

- [ ] **Step 3: Add the ID-card join date (all roles except admin)**

A date picker, not a free-text field — a typed date is the single most reliable way to get garbage into this column.

```dart
// Students read this off the date printed on their ID card; teachers and
// officers enter the date they joined.
InkWell(
  borderRadius: AppDepth.radius(1),
  onTap: () async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _joinedOn ?? DateTime(DateTime.now().year - 1),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      helpText: _role == 'student'
          ? 'Date printed on your ID card'
          : 'Date you joined the university',
    );
    if (picked != null) setState(() => _joinedOn = picked);
  },
  child: InputDecorator(
    decoration: InputDecoration(filled: true,
        border: OutlineInputBorder(borderRadius: AppDepth.radius(1)),
        errorText: _joinedOnError),
    child: Text(_joinedOn == null
        ? (_role == 'student' ? 'Join date (from your ID card)' : 'Joining date')
        : DateFormat('d MMMM yyyy').format(_joinedOn!)),
  ),
),
```

Validate in `_save()` before the update — `InputDecorator` is not a `FormField`, so it is not covered by `_formKey.currentState!.validate()`:

```dart
if (_role != 'admin' && _role != 'super_admin' && _joinedOn == null) {
  setState(() => _joinedOnError = 'Join date is required');
  return;
}
```

- [ ] **Step 4: Add the verification notice**

Placed directly above the phone field so it is read before the number is typed. **It must describe a future check, never claim one happened** — no fake "verified" badge, no fake code entry that always succeeds. Stating the intent is what discourages a fake number; simulating a check that does not exist would be a lie in the product.

```dart
// The check is NOT built. This says so in the future tense on purpose --
// a mock that pretends to verify would be a false claim in the UI, and the
// deterrent here comes from the person believing it will be checked later.
Container(
  padding: const EdgeInsets.all(AppSpace.sm),
  decoration: BoxDecoration(
    color: AppColors.surfaceOf(context),
    borderRadius: AppDepth.radius(1),
    border: Border.all(color: AppColors.borderOf(context)),
  ),
  child: Row(children: [
    Icon(Icons.verified_user_outlined, size: 16,
        color: AppColors.textSecondaryOf(context)),
    const SizedBox(width: AppSpace.xs),
    Expanded(child: Text(
      'These details will be checked later by a code sent to your number and '
      'by a direct call from the university. Enter the number you actually use.',
      style: AppTextStyles.labelSmall
          .copyWith(color: AppColors.textSecondaryOf(context)))),
  ]),
),
```

- [ ] **Step 5: Send the new fields in the update**

At `complete_profile_screen.dart:260`, add to the `update({...})` map. Leave `'profile_completed': true` in place — the trigger now overrules it, and removing it is an unnecessary client change:

```dart
  'admission_season': _role == 'student' ? _admissionSeason : null,
  'admission_year':   _role == 'student'
      ? int.tryParse(_admissionYearCtrl.text.trim()) : null,
  'joined_on': _joinedOn?.toIso8601String().split('T').first,
```

- [ ] **Step 6: Verify it end to end in a browser, not just in tests**

```bash
C:\RakibFlutter\bin\flutter.bat build web --release
```

Serve `build/web`, sign in as a user the Task 2 backfill made incomplete, and confirm: the app redirects to `/complete-profile` on its own; the form refuses to save with the term or join date blank; after saving, the app lets you through and does not bounce back. Then confirm in SQL that `profile_completed` is now true **for the right reason**:

```sql
select admission_season, admission_year, joined_on, profile_completed
  from profiles where id = '<that user>';
```

- [ ] **Step 7: Run analyze + full suite, then commit**

```bash
C:\RakibFlutter\bin\flutter.bat analyze     # expect: No issues found!
C:\RakibFlutter\bin\flutter.bat test        # expect: All tests passed!
git add lib/features/auth/presentation/complete_profile_screen.dart
git commit -m "Collect intake term, ID-card join date and a real emergency contact"
```

---

### Task 5: The registration page asks for the same things

**Files:**
- Modify: the signup screen under `lib/features/auth/presentation/`

The owner asked for this on the **register** page. The completion screen already exists and now enforces the full set, so the honest minimum is that a brand-new signup lands on `/complete-profile` immediately (it will, because the trigger computes a fresh row as incomplete) and cannot escape it.

- [ ] **Step 1: Verify a brand-new account is computed incomplete**

```sql
begin;
insert into profiles (id, full_name, email, role)
values (gen_random_uuid(), 'Probe', 'probe@example.com', 'student')
returning profile_completed;
rollback;
```

Expected: **false**. If true, the trigger is not covering INSERT — fix Task 2 before continuing.

- [ ] **Step 2: Confirm the router sends a new signup to the form**

Sign up a throwaway account in the browser and confirm it lands on `/complete-profile` with no way past it. Record what happened.

- [ ] **Step 3: Commit any wiring needed**

```bash
git commit -m "A new signup cannot reach the app before its profile is filled"
```

---

## PHASE B — the role-grouped directory (separate plan)

Depends on Phase A's `admission_season`, `admission_year`, `joined_on`. Write this as its own plan file once Phase A is merged; it is specified here only so Phase A is built toward it.

**Grouping hierarchies** (owner-specified):

| Role tab | Level 1 | Level 2 | Level 3 |
|---|---|---|---|
| Student | Season + year (`admission_season` + `admission_year`) | Batch | Section |
| Teacher | Department | Join year (`joined_on`) | Designation |
| Staff / Officer | Sector (`staff.category`) | Join year | Designation / office |
| Management | Grant | — | — |

**Design rules carried in** (from the dashboard correction, `afos_dashboard_requirements_from_owner`): a declared grid with aligned heights, never per-panel arbitrary sizing; every group header carries a real count; animate on first mount only, within motion tokens; and where a group has no data, say so rather than dropping it silently.

**Also in scope** (owner: "directory + approval queue"): restyle the approval queue to the same system. Do **not** touch the delete-everywhere or role-change actions.

---

## Self-Review

**Spec coverage**

| Requirement | Task |
|---|---|
| Total details incl. address + personal number on register | 4, 5 |
| Future verification by code + direct call, stated not faked | 4 Step 4 |
| Existing users immediately asked | 2 Step 7 (re-seat) + existing router gate |
| "Without these they can't" use the app | 3 (gate fails closed) |
| DB grabs it the moment they add it | 2 (trigger computes on write) |
| Teacher joining date | 1, 2, 4 |
| Student join date from ID card | 1, 2, 4 Step 3 |
| Season/year grouping for students | 1 (columns), Phase B (grouping) |
| Grouped sections, per-role places | Phase B |
| Directory + approval queue scope | Phase B |

**Open question for the owner — confirm before Task 2:** the required-field matrix. Specifically: should `emergency_contact` be mandatory for **admins** too, and should `joined_on` be required for `admin`/`super_admin` (currently exempt)?

**Placeholder scan:** no TBDs; every code step carries real code; the two `<ledger>` markers are deliberate — the version is only knowable after applying, per the hard rule.

**Type consistency:** `isProfileComplete(Map<String, dynamic>)` is used identically in Tasks 2 and 3. `profile_is_complete(profiles)` and `tg_profile_completeness()` are referenced only in Task 2. `joined_on` (not `joining_date`) is the profiles-side name throughout; `teachers.joining_date`/`staff.joining_date` appear only as mirrors.

**Risk called out:** Task 2 Step 7 is the irreversible-feeling moment — it locks every under-filled account out of the app until its owner fills the form. It is exactly what was asked for, but it should be run when someone is available to answer questions, not last thing at night. `profile_completed` can be restored for a single person by filling their row, never by setting the flag.
