import 'package:flutter/material.dart';

import 'package:afos_v7/config/theme/app_colors.dart';
import 'package:afos_v7/shared/widgets/afos_text_field.dart';
import 'package:afos_v7/shared/widgets/glass_tab_bar.dart';

import 'package:afos_v7/shared/widgets/glass_card.dart';
import 'package:afos_v7/shared/widgets/surface_card.dart';
import 'package:afos_v7/core/services/weather_service.dart';
import 'package:afos_v7/features/admin/presentation/widgets/user_card.dart';
// GroupSectionHeader lives in user_group_tree.dart alongside UserGroupTree,
// which is itself not probeable (see the note at its case below).
import 'package:afos_v7/features/admin/presentation/widgets/user_group_tree.dart';
import 'package:afos_v7/features/auth/presentation/widgets/auth_brand_panel.dart';
import 'package:afos_v7/features/dashboard/presentation/widgets/exam_pulse_band.dart';

import 'package:afos_v7/features/dashboard/presentation/widgets/my_completeness_ring.dart';
import 'package:afos_v7/features/dashboard/presentation/widgets/weather_dress_card.dart';
import 'package:afos_v7/shared/widgets/profile_identity_header.dart';
import 'package:afos_v7/shared/widgets/shimmer_card.dart';
import 'package:afos_v7/features/dashboard/presentation/widgets/admin_insights_panel.dart';
import 'package:afos_v7/features/web/presentation/consoles/admin_overview.dart';
import 'package:afos_v7/features/web/presentation/widgets/web_layout.dart';
import 'package:afos_v7/features/schedule/data/repositories/schedule_repository.dart';
import 'package:afos_v7/features/schedule/presentation/widgets/semester_break_card.dart';
import 'package:afos_v7/features/web/presentation/widgets/chart_primitives.dart';
import 'package:afos_v7/features/web/presentation/widgets/console_grid.dart';

import 'support/layout_probe.dart';

/// Shared widgets the existing sweeps never covered, driven through the same
/// size x text-scale probe as everything else.
///
/// The reason this file exists: `shared_widgets_layout_test` probes ten
/// widgets, and the ones it does NOT probe are where this session's changes
/// landed. In particular GlassTabBar, whose own doc says icons stack over
/// labels "to stay readable at 3-4 tabs" — and Manage Users now shows FIVE,
/// because the Photos and Code Failed queues were changed to render even when
/// empty so an admin could find them. Adding a tab without re-checking the bar
/// at 320dp and a 2.0x text scale is exactly how a control ends up unreadable
/// for the people who need it most.
///
/// Real widgets only. A copy in a test cannot regress.
void main() {
  runLayoutSweep('ui sweep', expectTruncated: {
    // The exam cards are a horizontal strip of DELIBERATELY fixed-width
    // (250px) cards, and the course title is coded maxLines: 2 + ellipsis on
    // purpose. On a 768px+ viewport the probe's starve threshold is a
    // fraction of the VIEWPORT, so a 250px card trips it no matter how well
    // it behaves — the calibration caveat its own doc describes.
    //
    // Allowed only because the truncation is the design, not a starve being
    // hidden: the real faults these cases found (a 42px bottom overflow and
    // a starved term name) were fixed in the widget rather than allowed here.
    'ExamPulseBand (live term, today + next exam)': {
      'Computer Architecture and Organisation',
      'Seat plan not published yet',
    },
  }, {
    // The exact five tabs Manage Users renders for a super_admin now, counts
    // and all. This is the configuration this session created.
    'GlassTabBar (5 tabs, the real Manage Users set)': () => GlassTabBar(
          currentIndex: 0,
          onChanged: (_) {},
          tabs: const [
            GlassTab('Pending (12)', icon: Icons.how_to_reg_rounded),
            GlassTab('Code Failed (3)', icon: Icons.mark_email_unread_rounded),
            GlassTab('Photos (7)', icon: Icons.photo_camera_outlined),
            GlassTab('CR Requests (4)', icon: Icons.badge_rounded),
            GlassTab('Users', icon: Icons.groups_2_outlined),
          ],
        ),

    // The two- and four-tab cases it was designed for, as the control.
    'GlassTabBar (4 tabs)': () => GlassTabBar(
          currentIndex: 1,
          onChanged: (_) {},
          tabs: const [
            GlassTab('Pending (12)', icon: Icons.how_to_reg_rounded),
            GlassTab('Photos (7)', icon: Icons.photo_camera_outlined),
            GlassTab('CR Requests (4)', icon: Icons.badge_rounded),
            GlassTab('Users', icon: Icons.groups_2_outlined),
          ],
        ),

    // SurfaceCard carries this session's Profile Inspection banner: icon,
    // two stacked lines of text, a count chip and a chevron on one row.
    'SurfaceCard (icon + two lines + chip + chevron)': () => SurfaceCard(
          accent: AppColors.amber,
          onTap: () {},
          child: Row(children: [
            const Icon(Icons.fact_check_rounded, color: AppColors.amber, size: 22),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Profile Inspection'),
                Text('13 verified accounts still owe required details'),
              ]),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsetsDirectional.fromSTEB(8, 2, 8, 2),
              color: AppColors.amber.withValues(alpha: 0.14),
              child: const Text('13'),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, size: 20),
          ]),
        ),

    'AfosTextField (long hint)': () => AfosTextField(
          hint: 'Where was it lost or found? Be as specific as you can',
          controller: TextEditingController(),
        ),

    'AfosTextField (long value + error)': () => AfosTextField(
          hint: 'Emergency contact',
          controller: TextEditingController(
              text: 'Someone With A Rather Long Name 01700000001'),
          validator: (_) => 'This must differ from your own number',
        ),

    // OfflineBanner is deliberately NOT probed here. It reads the offline
    // cache on build and throws "HiveError: Box not found" without an opened
    // box, which is a harness limitation rather than a layout fault — probing
    // it would report a failure that says nothing about how it lays out.
    // Left out rather than papered over with a fake pass.

    // The web console figure this session added a ninth of. Its label is a
    // Semantics label, so the NOTE is what a sighted person reads and the
    // note is the part that has to fit.
    'GridFigure (web console figure)': () => const SizedBox(
          height: 78,
          child: GridFigure(
            label: 'Incomplete profiles',
            value: '13',
            note: 'missing required details',
            icon: Icons.fact_check_rounded,
            accent: AppColors.amber,
          ),
        ),

    'GlassCard (stat row, the Manage Users header)': () => const GlassCard(
          borderRadius: 16,
          glowColor: AppColors.holoviolet,
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Row(children: [
            Expanded(child: Column(children: [Text('12'), Text('Pending')])),
            Expanded(child: Column(children: [Text('4'), Text('CR Requests')])),
            Expanded(child: Column(children: [Text('1854'), Text('Total Users')])),
          ]),
        ),

    // --- the web console's chart layer, none of it probed before ---------
    // These carry real, uncontrolled text: department names, batch numbers
    // and day labels come from the database, and the console is a web-first
    // surface that also renders in a phone-width browser window.
    // Centre labels are one word in every real call site ('', 'classes',
    // 'timetabled', 'total beds') — checked before writing this, because an
    // earlier draft used "timetabled this semester", watched it starve, and
    // very nearly reshaped the widget around a string it is never given.
    // Probe what production actually passes.
    'RingChart (real centre label)': () => const SizedBox(
          height: 180,
          child: RingChart(
            slices: [
              RingSlice(label: 'Lab', value: 844, color: AppColors.blue),
              RingSlice(label: 'Theory', value: 1010, color: AppColors.green),
            ],
            centerLabel: 'timetabled',
            centerValue: '1854',
          ),
        ),

    // The legend's labels are role names on the "Who is in AFOS" panel, so
    // the longest realistic pair is what gets probed.
    'ChartLegend (longest real role labels)': () => const ChartLegend(
          slices: [
            RingSlice(
                label: 'Exam Controller', value: 844, color: AppColors.blue),
            RingSlice(
                label: 'Department Admin', value: 1010, color: AppColors.green),
          ],
        ),

    'BarList (long row labels)': () => const BarList(
          data: [
            BarDatum('Computer Science and Engineering', 320),
            BarDatum('Business Administration', 210),
            BarDatum('68', 12),
          ],
          total: 542,
        ),

    // The redesigned drawer identity, in the widest and narrowest role
    // shapes it has to hold: a long student name with department + semester,
    // and an administrator with a title but no department and no id.
    'ProfileIdentityHeader (student, long name)': () =>
        const ProfileIdentityHeader(
          name: 'Mohammad Shariar Ahamed Ripon Chowdhury',
          identifier: '241-15-1491',
          affiliation: 'CSE',
          roleLabel: 'Sem 8',
          initials: 'MS',
        ),

    'ProfileIdentityHeader (super admin, no dept or id)': () =>
        const ProfileIdentityHeader(
          name: 'Rakib Hassan',
          roleLabel: 'Super Admin',
          initials: 'RH',
          isSuperAdmin: true,
        ),

    'ProfileIdentityHeader (teacher, long designation)': () =>
        const ProfileIdentityHeader(
          name: 'Md. Aktaruzzaman',
          identifier: '201-15-3132',
          affiliation: 'CSE',
          roleLabel: 'Assistant Professor',
          initials: 'MA',
        ),

    // --- the last unprobed public widgets -------------------------------
    // AdminInsightsPanel is the dashboard's largest admin surface and takes a
    // whole AdminOverviewData, which is why it kept being skipped.
    'AdminInsightsPanel (populated)': () => const AdminInsightsPanel(
          data: AdminOverviewData(
            facets: {
              'total': 1854,
              'pending': 12,
              'roles': [
                {'value': 'student', 'count': 1600},
                {'value': 'teacher', 'count': 180},
                {'value': 'exam_controller', 'count': 4},
              ],
            },
            recent: [],
            stuck: 3,
            incomplete: 13,
            exams: [],
            beds: 2800,
            occupied: 2797,
            campus: {
              'liveSlots': 1854,
              'labSlots': 844,
              'rooms': 68,
            },
          ),
        ),

    'WebStatStrip (long labels, real figures)': () => const WebStatStrip(
          stats: [
            WebStat(
                label: 'Incomplete profiles',
                value: '13',
                icon: Icons.fact_check_rounded,
                accent: AppColors.amber),
            WebStat(
                label: 'Awaiting approval',
                value: '12',
                icon: Icons.how_to_reg_rounded,
                accent: AppColors.green),
            WebStat(
                label: 'People in AFOS',
                value: '1854',
                icon: Icons.groups_rounded,
                accent: AppColors.blue),
          ],
        ),

    'WebPanel (title + actions + content)': () => WebPanel(
          title: 'Recently joined, and how they proved who they are',
          actions: [TextButton(onPressed: () {}, child: const Text('See all'))],
          child: const Text('Panel body'),
        ),

    'GridPanel (console panel with a long title)': () => const SizedBox(
          height: 180,
          child: GridPanel(
            title: 'Teaching load by batch',
            child: Text('Panel body'),
          ),
        ),

    // Skeletons. The constitution requires them to match the final layout's
    // geometry so nothing shifts when real data lands; the least they must do
    // is survive every size and scale the real content does.
    'ShimmerList (loading skeleton)': () => const ShimmerList(),

    // The semester-break card, new this phase. It replaces the routine
    // entirely for a whole department, so it has to survive every size and
    // scale the routine itself does.
    'SemesterBreakCard (routine screen)': () => SemesterBreakCard(
          brk: SemesterBreak(
              season: 'summer', year: 2026, endedOn: DateTime(2026, 8, 27)),
        ),

    'SemesterBreakCard (dashboard, compact)': () => SemesterBreakCard(
          compact: true,
          brk: SemesterBreak(
              season: 'summer', year: 2026, endedOn: DateTime(2026, 8, 27)),
        ),

    // --- widgets that take a whole data object --------------------------
    // Flagged as unprobed at the end of Phase W. They were skipped because
    // they need a model built rather than a string passed, which is a poor
    // reason to leave the dashboard's largest surfaces unrendered.
    'ExamPulseBand (live term, today + next exam)': () => ExamPulseBand(
          data: ExamPulseData(
            role: 'student',
            term: {
              'id': 't1',
              'type': 'final',
              'season': 'summer',
              'year': 2026,
              'isLive': true,
              'isOver': false,
              'endsOn':
                  DateTime.now().add(const Duration(days: 9)).toIso8601String(),
            },
            exams: [
              {
                'code': 'CSE314',
                'title': 'Computer Architecture and Organisation',
                'date': DateTime.now().toIso8601String(),
                'slot': 'Morning (09:00 AM - 12:00 PM)',
                'room': 'KT-701',
                'start': '09:00',
              },
              {
                'code': 'ACT327',
                'title': 'Financial and Managerial Accounting',
                'date': DateTime.now()
                    .add(const Duration(days: 2))
                    .toIso8601String(),
                'slot': 'Afternoon (02:00 PM - 05:00 PM)',
                'room': 'AB4-1203',
                'start': '14:00',
              },
            ],
          ),
        ),

    'ExamPulseBand (teacher with invigilation duties)': () => ExamPulseBand(
          data: ExamPulseData(
            role: 'teacher',
            term: {
              'id': 't1',
              'type': 'final',
              'season': 'summer',
              'year': 2026,
              'isLive': true,
              'isOver': false,
              'endsOn':
                  DateTime.now().add(const Duration(days: 3)).toIso8601String(),
            },
            duties: [
              {
                'date': DateTime.now().toIso8601String(),
                'slot': 'Morning (09:00 AM - 12:00 PM)',
                'rooms': ['KT-701', 'KT-702', 'AB4-1203'],
              },
            ],
          ),
        ),

    'AuthBrandPanel (login/register side panel)': () => const AuthBrandPanel(),

    // UserGroupTree is NOT probed: it builds a ListView.builder, and walking a
    // viewport's children throws "Null check operator used on a null value"
    // inside Flutter's own _ViewportElement.debugVisitOnstageChildren during
    // the probe's tree traversal. A harness limitation, not a widget fault —
    // its header row is covered by the GroupSectionHeader case below, which is
    // the part of it that can starve.

    // --- feature widgets carrying real database text --------------------
    // Names, emails and weather sentences are the least controlled strings in
    // the app: nobody reviews them, they arrive from Postgres or an API, and
    // they are exactly where a row starves a title.
    'UserCard (long name + email, pending)': () => UserCard(
          pending: true,
          user: const {
            'id': 'u1',
            'full_name': 'Mohammad Shariar Ahamed Ripon Chowdhury',
            'email': 'shariar.ahamed.ripon15-3132@diu.edu.bd',
            'role': 'student',
            'university_id': '241-15-1491',
            'department': 'CSE',
            'batch': '68',
            'section': 'D',
            'is_verified': false,
          },
          onApprove: () {},
          onReject: () {},
        ),

    'UserCard (super admin, manager, with areas)': () => UserCard(
          pending: false,
          isManager: true,
          areaCount: 4,
          user: const {
            'id': 'u2',
            'full_name': 'Rakib Hassan',
            'email': 'rakibhassan.rh66@gmail.com',
            'role': 'super_admin',
            'is_verified': true,
          },
          onChangeRole: () {},
          onManagePermissions: () {},
          onDelete: () {},
        ),

    // The completeness ring this session's work feeds. Its reason list is
    // built from incompleteReasons(), whose longest entry is a sentence.
    'MyCompletenessRing (longest real reason)': () => MyCompletenessRing(
          missing: 3,
          total: 16,
          reasons: const [
            'Emergency contact is the same as their own number',
            'No photo uploaded past the 48h deadline',
            'Permanent district',
          ],
          onTap: () {},
        ),

    'WeatherDressCard (dress advice sentence)': () => const WeatherDressCard(
          weather: WeatherSnapshot(
            temperatureC: 27.4,
            condition: WeatherCondition.cloudy,
            isDay: false,
          ),
          gender: 'male',
        ),

    // The header the per-role directory's group tree uses: an Expanded label
    // beside a count, which is the shape that starves.
    'GroupSectionHeader (long group label + count)': () =>
        const GroupSectionHeader(label: 'Intake not set', total: 1854),

    // rowLabels come from a fixed const list in admin_overview
    // (['Sat','Sun','Mon',...]) and colLabels are hour numbers, so the real
    // worst case is a FULL week of columns rather than long strings.
    'HeatGrid (full week, real labels)': () => const SizedBox(
          height: 220,
          child: HeatGrid(
            values: [
              [0, 3, 5, 2, 1, 4, 2, 0],
              [1, 4, 2, 0, 3, 1, 5, 2],
              [2, 2, 6, 1, 0, 2, 3, 4],
              [0, 1, 2, 3, 4, 5, 1, 0],
              [3, 0, 1, 2, 2, 1, 0, 3],
              [1, 1, 1, 1, 1, 1, 1, 1],
              [0, 0, 2, 2, 0, 0, 2, 2],
            ],
            rowLabels: ['Sat', 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri'],
            colLabels: ['8', '9', '10', '11', '12', '13', '14', '15'],
          ),
        ),
  });
}
