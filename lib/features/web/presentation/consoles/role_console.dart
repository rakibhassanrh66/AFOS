import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../config/supabase_config.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../config/theme/app_text_styles.dart';
import '../../../../config/theme/spacing.dart';
import '../../../../core/auth/capabilities.dart';
import '../../../../core/auth/permission_session.dart';
import '../../../../shared/models/user_model.dart';
import '../../../../shared/widgets/shimmer_card.dart';
import '../widgets/web_layout.dart';
import 'work_queue.dart';

/// The web home screen: what needs doing, for whoever is looking.
///
/// WHY THIS IS NOT THE MOBILE DASHBOARD. `dashboard_screen.dart` renders a
/// fixed twelve-tile grid and its only role logic is subtracting four
/// student-only tiles. It never reads `PermissionSession` — zero references in
/// 1035 lines. So a staff member, a delegated officer, a teacher and an exam
/// controller all landed on the SAME eight student-facing tiles: Schedule,
/// Transport, Lost & Found, Clubs, Mentorship, Dept Chat, VR-ID, Notices.
/// Routine upload, hall management, CR approval, marks entry, the activity
/// log — none of it appeared anywhere on the home screen.
///
/// That is the "staff and officers still get nothing" report, and it was never
/// a permissions bug: the permission layer works. It was a home screen that
/// had never been told roles exist.
///
/// A launcher tells you what exists. A console tells you what is waiting. On a
/// phone the first is defensible — you opened the app for a reason. On a
/// desktop, where somebody sits down to work, a grid of icons is a wasted
/// screen.
class RoleConsole extends StatefulWidget {
  const RoleConsole({super.key});

  @override
  State<RoleConsole> createState() => _RoleConsoleState();
}

class _RoleConsoleState extends State<RoleConsole> {
  UserModel? _user;
  bool _isCr = false;
  Set<String> _grants = const {};
  List<WorkQueue> _queues = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final p = await SupabaseConfig.client
          .from('profiles')
          .select('*, teachers(designation), staff(designation, office), students(is_cr)')
          .eq('id', uid).single();
      final grants = await PermissionSession.reload();
      // Counted only after the grants are known — asking for queues before
      // knowing the areas would either fetch everything or fetch nothing.
      final queues = await loadWorkQueues(grants);
      if (!mounted) return;
      setState(() {
        _user = UserModel.fromJson(p);
        _isCr = (p['students'] as Map?)?['is_cr'] as bool? ?? false;
        _grants = grants;
        _queues = queues;
        _loading = false;
      });
    } catch (_) {
      // Falls through to the student baseline, which is the least privileged
      // answer rather than the most — a failed load must never hand someone a
      // console they have no right to.
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
          padding: EdgeInsets.all(AppSpace.lg), child: ShimmerList());
    }

    final role = _user?.role;
    final first = (_user?.fullName ?? '').split(' ').first;
    final caps = capabilitiesFor(role: role, grants: _grants, isCr: _isCr);

    return WebPage(
      title: first.isEmpty ? _greeting : '$_greeting, $first',
      subtitle: _subtitleFor(role),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // The granted areas come FIRST, above everything else, for everyone
        // who has any. Whatever your role is, the thing somebody specifically
        // asked you to look after outranks the general-purpose app.
        if (_queues.isNotEmpty) ...[
          const _SectionLabel(
            'Your work areas',
            note: 'Assigned to you individually',
          ),
          const SizedBox(height: AppSpace.md),
          WebGrid(
            minItemWidth: 260,
            children: [for (final q in _queues) WorkQueueCard(queue: q)],
          ),
          const SizedBox(height: AppSpace.xl),
        ] else if (role == 'staff') ...[
          // The one role whose menu is built entirely from grants. With none,
          // it is correctly empty — and an empty screen with no explanation
          // reads as a broken app rather than an unfinished setup step.
          const NoAreasPanel(),
          const SizedBox(height: AppSpace.xl),
        ],

        _RoleBody(role: role, isCr: _isCr, caps: caps),

        const SizedBox(height: AppSpace.xl),
        _SectionLabel('Everything you can reach',
            note: '${caps.length} in total'),
        const SizedBox(height: AppSpace.md),
        WebGrid(
          minItemWidth: 210,
          children: [for (final c in caps) _CapabilityTile(cap: c)],
        ),
      ]),
    );
  }

  String _subtitleFor(String? role) => switch (role) {
        'super_admin' => 'Everything across the university, and who did what.',
        'admin' || 'dept_admin' => 'Your department: queues, registry and approvals.',
        'teacher' => 'Your courses, your register, your students.',
        'staff' => 'The areas you have been given, and what is waiting in them.',
        'exam_controller' => 'Seating, notices and the exam cycle.',
        _ => 'Your classes, records and campus services.',
      };
}

/// The part of the console that differs by who is looking.
///
/// Kept as one widget with a switch rather than five files because every
/// branch is a composition of the same primitives over data the app already
/// loads. Five files would be five places to forget a fix.
class _RoleBody extends StatelessWidget {
  final String? role;
  final bool isCr;
  final List<AppCapability> caps;

  const _RoleBody({required this.role, required this.isCr, required this.caps});

  @override
  Widget build(BuildContext context) {
    // Shortcut rows: the two or three things this audience does most, as
    // buttons rather than as tiles to hunt for.
    final shortcuts = switch (role) {
      'teacher' => [
          Caps.attendance, Caps.myOfferings, Caps.joinRequests, Caps.teachingLoad,
        ],
      'super_admin' => [
          Caps.manageUsers, Caps.activityLog, Caps.feedbackTriage, Caps.notices,
        ],
      'admin' || 'dept_admin' => [
          Caps.courseOfferingsAdmin, Caps.notices, Caps.hallAdmin, Caps.uploadRoutine,
        ],
      'exam_controller' => [Caps.examSeatsAdmin, Caps.notices],
      'staff' => const <AppCapability>[],
      _ => [
          Caps.schedule, Caps.results, Caps.assignments,
          if (isCr) Caps.roomAvailability,
        ],
    };

    // Only offer a shortcut the person can actually reach. The capability list
    // is the authority — a shortcut the router would refuse is exactly the
    // "offering a door the database slams" pattern this codebase keeps
    // finding, and there is no reason to reintroduce it on the home screen.
    final reachable = caps.map((c) => c.route).toSet();
    final usable = shortcuts.where((c) => reachable.contains(c.route)).toList();
    if (usable.isEmpty) return const SizedBox.shrink();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _SectionLabel(switch (role) {
        'teacher' => 'Teaching',
        'super_admin' || 'admin' || 'dept_admin' => 'Running the place',
        'exam_controller' => 'Exam cycle',
        _ => 'Your studies',
      }),
      const SizedBox(height: AppSpace.md),
      WebGrid(
        minItemWidth: 260,
        children: [for (final c in usable) _ShortcutPanel(cap: c)],
      ),
    ]);
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final String? note;
  const _SectionLabel(this.text, {this.note});

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic, children: [
      Text(text,
          style: AppTextStyles.titleMedium.copyWith(
              color: AppColors.textPrimaryOf(context),
              fontWeight: FontWeight.w700)),
      if (note != null) ...[
        const SizedBox(width: AppSpace.sm),
        Text(note!,
            style: AppTextStyles.labelSmall
                .copyWith(color: AppColors.textMutedOf(context))),
      ],
    ]);
  }
}

class _ShortcutPanel extends StatelessWidget {
  final AppCapability cap;
  const _ShortcutPanel({required this.cap});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => context.go(cap.route),
        child: WebPanel(
          child: Row(children: [
            Icon(cap.icon, size: 22, color: cap.accent),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(cap.label,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.titleMedium.copyWith(
                        color: AppColors.textPrimaryOf(context),
                        fontWeight: FontWeight.w700)),
                if (cap.hint != null)
                  Text(cap.hint!,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.labelSmall
                          .copyWith(color: AppColors.textSecondaryOf(context))),
              ]),
            ),
            Icon(Icons.arrow_forward_rounded,
                size: 16, color: AppColors.textMutedOf(context)),
          ]),
        ),
      ),
    );
  }
}

class _CapabilityTile extends StatelessWidget {
  final AppCapability cap;
  const _CapabilityTile({required this.cap});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => context.go(cap.route),
        child: WebPanel(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Row(children: [
            Icon(cap.icon, size: 18, color: cap.accent),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Text(cap.label,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textPrimaryOf(context),
                      fontWeight: FontWeight.w600)),
            ),
            if (cap.delegated)
              Container(
                width: 5, height: 5,
                decoration: const BoxDecoration(
                    color: AppColors.holoTeal, shape: BoxShape.circle),
              ),
          ]),
        ),
      ),
    );
  }
}
