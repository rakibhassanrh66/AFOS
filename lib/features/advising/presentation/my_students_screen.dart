import 'package:flutter/material.dart';

import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/depth.dart';
import '../../../config/theme/spacing.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/layout/nav_insets.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/afos_text_field.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/glass_tab_bar.dart';
import '../../../shared/widgets/label_value_row.dart';
import '../../../shared/widgets/pill_badge.dart';
import '../../../shared/widgets/surface_card.dart';
import '../../web/presentation/widgets/adaptive_list.dart';
import '../data/models/teacher_link.dart';
import '../data/repositories/advising_repository.dart';
import 'link_thread_screen.dart';
import 'widgets/availability_editor.dart';

/// The teacher's side: everyone who has asked for them, and everyone they
/// took on.
///
/// Advisees and final-year students share ONE list, separated by a chip
/// rather than by a tab, because a teacher thinks in terms of "my students"
/// and not in terms of two databases. What differs between them is only how
/// much of each student this screen is allowed to show, and that is decided
/// by the server, not here.
/// Rendered as a tab inside Mentorship rather than as its own screen.
///
/// Advising belongs beside mentorship rather than in its own corner of the
/// menu: both are a teacher and a student paired up, and a teacher looking for
/// "the students I am responsible for" should not have to know which of two
/// features owns that word.
class MyStudentsBody extends StatefulWidget {
  const MyStudentsBody({super.key});

  @override
  State<MyStudentsBody> createState() => _MyStudentsBodyState();
}

class _MyStudentsBodyState extends State<MyStudentsBody> {
  final _repo = AdvisingRepository();

  int _tab = 0;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _pending = const [];
  List<Map<String, dynamic>> _active = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final pending = await _repo.myStudents(status: LinkStatus.pending);
      final active = await _repo.myStudents(status: LinkStatus.active);
      if (!mounted) return;
      setState(() {
        _pending = pending;
        _active = active;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyError(e);
      });
    }
  }

  Future<void> _decide(String linkId, bool accept) async {
    String? reason;
    if (!accept) {
      reason = await _askReason();
      if (reason == null) return; // cancelled
    }
    try {
      await _repo.decide(linkId, accept: accept, reason: reason);
      AppHaptics.success();
      await _load();
    } catch (e) {
      if (!mounted) return;
      _toast(friendlyError(e));
    }
  }

  /// A decline without a reason reads to the student as being ignored, so the
  /// reason is asked for here rather than made optional in the model.
  Future<String?> _askReason() async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Why are you declining?'),
        content: AfosTextField(
          hint: 'They will see this',
          controller: ctrl,
          maxLines: 3,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Decline')),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final rows = _tab == 0 ? _pending : _active;

    return Column(children: [
      AppSpace.vGapMd,
      // Availability opens in a sheet rather than sitting above the list: a
      // teacher with eight office-hour rows would otherwise push the students
      // off the screen, and this Column has no scroll of its own.
      Padding(
        padding: AppSpace.screenH,
        child: AfosButton(
          label: 'When you are free',
          icon: Icons.schedule_rounded,
          outlined: true,
          onTap: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.4,
              maxChildSize: 0.95,
              expand: false,
              builder: (ctx, scroll) => Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceOf(context),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: ListView(
                  controller: scroll,
                  padding: AppSpace.allLg,
                  children: const [AvailabilityEditor()],
                ),
              ),
            ),
          ),
        ),
      ),
      AppSpace.vGapMd,
      GlassTabBar(
        tabs: [
          GlassTab('Requests (${_pending.length})',
              icon: Icons.mark_email_unread_rounded),
          GlassTab('Active (${_active.length})', icon: Icons.people_alt_rounded),
        ],
        currentIndex: _tab,
        onChanged: (i) => setState(() => _tab = i),
      ),
      AppSpace.vGapMd,
      Expanded(child: _list(rows)),
    ]);
  }

  Widget _list(List<Map<String, dynamic>> rows) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ErrorView(message: _error!, onRetry: _load);
    }
    if (rows.isEmpty) {
      return EmptyState(
        icon: _tab == 0
            ? Icons.mark_email_read_rounded
            : Icons.people_outline_rounded,
        title: _tab == 0 ? 'Nothing waiting' : 'No students yet',
        subtitle: _tab == 0
            ? 'When a student names your initial, their request appears here.'
            : 'Accept a request and the student will appear here.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: AdaptiveList(
        padding: EdgeInsetsDirectional.fromSTEB(
            AppSpace.lg, 0, AppSpace.lg, AppSpace.lg + NavInsets.of(context)),
        itemCount: rows.length,
        itemBuilder: (ctx, i) => _StudentRow(
          key: ValueKey(rows[i]['id']),
          row: rows[i],
          pending: _tab == 0,
          onAccept: () => _decide(rows[i]['id'] as String, true),
          onDecline: () => _decide(rows[i]['id'] as String, false),
          onOpen: () => _openProfile(rows[i]),
          onMessage: () => _openThread(rows[i]),
        ),
      ),
    );
  }

  void _openThread(Map<String, dynamic> row) {
    final raw = row['profiles'];
    final p = (raw is List)
        ? (raw.isEmpty ? const <String, dynamic>{} : raw.first as Map<String, dynamic>)
        : (raw as Map<String, dynamic>? ?? const {});
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => LinkThreadScreen(
        linkId: row['id'] as String,
        title: (p['full_name'] as String?) ?? 'Student',
      ),
    ));
  }

  Future<void> _openProfile(Map<String, dynamic> row) async {
    final linkId = row['id'] as String;
    final kind = LinkKind.parse(row['kind'] as String?);
    try {
      final student = await _repo.studentFor(linkId);
      if (!mounted || student == null) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _StudentSheet(student: student, kind: kind),
      );
    } catch (e) {
      // The server refuses while a link is pending. That is the rule working,
      // and it is worth saying rather than showing an empty sheet.
      if (mounted) _toast(friendlyError(e));
    }
  }
}

/// One student in the list: ID first, then name, as asked.
class _StudentRow extends StatelessWidget {
  final Map<String, dynamic> row;
  final bool pending;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onOpen;
  final VoidCallback onMessage;

  const _StudentRow({
    super.key,
    required this.row,
    required this.pending,
    required this.onAccept,
    required this.onDecline,
    required this.onOpen,
    required this.onMessage,
  });

  @override
  Widget build(BuildContext context) {
    // The embed may arrive as an object or as a single-element list — the
    // same PostgREST behaviour UserModel already handles.
    final raw = row['profiles'];
    final p = (raw is List)
        ? (raw.isEmpty ? const <String, dynamic>{} : raw.first as Map<String, dynamic>)
        : (raw as Map<String, dynamic>? ?? const {});
    final kind = LinkKind.parse(row['kind'] as String?);
    final name = (p['full_name'] as String?) ?? 'Unnamed';
    final id = (p['university_id'] as String?) ?? '';

    return SurfaceCard(
      margin: const EdgeInsetsDirectional.only(bottom: AppSpace.md),
      onTap: pending ? null : onOpen,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (id.isNotEmpty)
                Text(id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.monoSmall
                        .copyWith(color: AppColors.textSecondaryOf(context))),
              Text(name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.titleMedium
                      .copyWith(color: AppColors.textPrimaryOf(context))),
            ]),
          ),
          AppSpace.gapSm,
          // Flexible so a long badge cannot starve the name beside it — the
          // starve guard's whole subject.
          Flexible(
            child: PillBadge(
              label: kind == LinkKind.fydp ? 'FYDP' : 'ADVISEE',
              color: kind == LinkKind.fydp ? AppColors.teal : AppColors.holoBlue,
            ),
          ),
        ]),
        if (!pending) ...[
          AppSpace.vGapMd,
          AfosButton(
            label: 'Message',
            icon: Icons.forum_rounded,
            outlined: true,
            onTap: onMessage,
          ),
        ],
        if (pending) ...[
          AppSpace.vGapMd,
          Row(children: [
            Expanded(
              child: AfosButton(
                  label: 'Review', outlined: true, onTap: onOpen),
            ),
            AppSpace.gapSm,
            Expanded(child: AfosButton(label: 'Accept', onTap: onAccept)),
          ]),
          AppSpace.vGapSm,
          AfosButton(
              label: 'Decline', outlined: true, color: AppColors.red, onTap: onDecline),
        ],
      ]),
    );
  }
}

/// The scoped profile. Every field here arrived already filtered by
/// `student_profile_for_link` — an FYDP supervisor's row has no emergency
/// contact and no address in it, so there is nothing here to leak.
class _StudentSheet extends StatelessWidget {
  final LinkedStudent student;
  final LinkKind kind;

  const _StudentSheet({required this.student, required this.kind});

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String?)>[
      ('University ID', student.universityId),
      ('Batch', student.batch),
      ('Section', student.section),
      ('Semester', student.semester?.toString()),
      ('CGPA', student.cgpa?.toStringAsFixed(2)),
      ('Phone', student.phone),
      ('Email', student.email),
      if (kind == LinkKind.advisor) ...[
        ('Emergency contact', student.emergencyContact),
        ('Home address', student.address.isEmpty ? null : student.address),
      ],
      if (kind == LinkKind.fydp)
        ('Academic advisor', student.advisorName == null
            ? null
            : '${student.advisorName}'
                '${student.advisorInitial != null ? ' (${student.advisorInitial})' : ''}'),
    ];

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scroll) => Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceOf(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          controller: scroll,
          padding: AppSpace.allLg,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textSecondaryOf(context).withValues(alpha: 0.3),
                  borderRadius: AppDepth.radius(0),
                ),
              ),
            ),
            AppSpace.vGapLg,
            Text(student.fullName,
                style: AppTextStyles.headlineMed
                    .copyWith(color: AppColors.textPrimaryOf(context))),
            AppSpace.vGapLg,
            // LabelValueRow rather than a hand-rolled Row: it already
            // reflows its own label width against the text scale, and a
            // fixed-width label column is exactly what starves the value
            // beside it on a 320px screen. Reuse over a second one.
            for (final (label, value) in rows)
              LabelValueRow(
                label: label,
                // 7 of 12 students have no phone number and 8 no emergency
                // contact, so "not provided" is the common case here, not the
                // edge one. It has to read as a fact rather than as a blank
                // the screen failed to fill.
                value: (value ?? '').isEmpty ? 'Not provided' : value!,
                valueColor: (value ?? '').isEmpty
                    ? AppColors.textSecondaryOf(context)
                    : null,
                valueMaxLines: 2,
              ),
            if (kind == LinkKind.fydp) ...[
              AppSpace.vGapSm,
              Text(
                'Family and address details are not shared with a project '
                'supervisor.',
                style: AppTextStyles.labelSmall
                    .copyWith(color: AppColors.textSecondaryOf(context)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
