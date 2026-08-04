import 'package:flutter/material.dart';

import '../../../config/theme/app_colors.dart';
import '../../../config/theme/button_styles.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/liquid_glass_tokens.dart';
import '../../../core/auth/role_session.dart';
import '../../../core/layout/nav_insets.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/afos_text_field.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/glass_sheet.dart';
import '../../../shared/widgets/glass_tab_bar.dart';
import '../../../shared/widgets/pill_badge.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../shell/presentation/top_app_bar.dart';
import '../data/repositories/teaching_assignment_repository.dart';

const _adminRoles = ['admin', 'dept_admin', 'super_admin'];

/// Where a department's teaching load is allocated for the semester.
///
/// Two audiences in one screen, because they are two halves of the same job:
/// an admin appoints the module leaders, and a module leader allocates
/// courses to teachers. An admin sees both tabs; a module leader sees only
/// their own department's allocations.
class ModuleLeaderScreen extends StatefulWidget {
  const ModuleLeaderScreen({super.key});

  @override
  State<ModuleLeaderScreen> createState() => _ModuleLeaderScreenState();
}

class _ModuleLeaderScreenState extends State<ModuleLeaderScreen> {
  final _repo = TeachingAssignmentRepository();

  List<String> _myDepartments = [];
  String? _department;
  int _tab = 0;
  bool _loading = true;
  String? _error;

  bool get _isAdmin => _adminRoles.contains(RoleSession.role);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final led = await _repo.fetchMyLedDepartments();
      // An admin who leads nothing still needs a department to work in, so
      // fall back to their own. Without this the allocation tab would be
      // permanently empty for the person who set the whole thing up.
      final ownDept = led.isEmpty ? await _repo.fetchMyDepartment() : null;
      if (!mounted) return;
      setState(() {
        _myDepartments = led;
        _department ??= led.isNotEmpty ? led.first : ownDept;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final canAllocate = _isAdmin || _myDepartments.isNotEmpty;

    if (_loading) {
      return const Scaffold(
        appBar: AfosAppBar(title: 'Teaching Load'),
        body: Padding(padding: EdgeInsets.all(16), child: ShimmerList()),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: const AfosAppBar(title: 'Teaching Load'),
        body: ErrorView(message: _error!, onRetry: _load),
      );
    }
    // An ordinary teacher is not locked out of this screen — they see what
    // their module leader allocated TO them. Showing a bare "not a module
    // leader" would make a menu item that is useless to almost every teacher
    // who taps it, when the allocations are exactly what they want to check.
    if (!canAllocate) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: const AfosAppBar(title: 'Teaching Load'),
        body: _MyAssignmentsTab(repo: _repo),
      );
    }

    // "Mine" is here for everyone who can allocate, not just ordinary teachers.
    // A module leader IS a teacher and gets allocated classes like anyone else,
    // and an admin can be allocated one too — but the only path to
    // [_MyAssignmentsTab] used to be the `!canAllocate` early return above, so
    // the moment somebody was appointed module leader their own allocations
    // became unreachable: they could not see them, accept them or decline them
    // from anywhere in the app, and the module leader who allocated the class
    // never got an answer.
    final tabs = <GlassTab>[
      const GlassTab('Allocations', icon: Icons.assignment_outlined),
      const GlassTab('Mine', icon: Icons.assignment_ind_outlined),
      if (_isAdmin) const GlassTab('Module Leaders', icon: Icons.manage_accounts_outlined),
    ];

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const AfosAppBar(title: 'Teaching Load'),
      body: Column(children: [
        const SizedBox(height: 10),
        GlassTabBar(
          tabs: tabs,
          currentIndex: _tab.clamp(0, tabs.length - 1),
          onChanged: (i) => setState(() => _tab = i),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: switch (_tab) {
            1 => _MyAssignmentsTab(repo: _repo),
            2 when _isAdmin => _LeadersTab(repo: _repo, onChanged: _load),
            _ => _AllocationsTab(
                  repo: _repo,
                  department: _department ?? '',
                  departments: _myDepartments,
                  onDepartmentChanged: (d) => setState(() => _department = d),
                ),
          },
        ),
      ]),
    );
  }
}

// ------------------------------------------------- a teacher's own load

/// What this teacher has been allocated, claimed and unclaimed alike.
class _MyAssignmentsTab extends StatefulWidget {
  final TeachingAssignmentRepository repo;
  const _MyAssignmentsTab({required this.repo});

  @override
  State<_MyAssignmentsTab> createState() => _MyAssignmentsTabState();
}

class _MyAssignmentsTabState extends State<_MyAssignmentsTab> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final rows = await widget.repo.fetchMyAssignments();
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  final Set<String> _busy = {};

  /// A decline must carry a reason: the module leader is the one who has to
  /// find somebody else, and "no" on its own tells them nothing. Enforced in
  /// the database as well, so this dialog is convenience, not the guarantee.
  Future<String?> _askReason() async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Decline this allocation'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
              hintText: 'Why? e.g. already teaching four sections, clashes with CSE221'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          TextButton(
              onPressed: () {
                final t = ctrl.text.trim();
                if (t.isNotEmpty) Navigator.pop(d, t);
              },
              child: const Text('Decline')),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }

  Future<void> _respond(Map<String, dynamic> r, bool accept) async {
    String? reason;
    if (!accept) {
      reason = await _askReason();
      if (reason == null) return;
    }
    final id = r['id'] as String;
    setState(() => _busy.add(id));
    try {
      await widget.repo.respondToAssignment(
          assignmentId: id, accept: accept, reason: reason);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(accept
                ? 'Accepted — create the offering when ready'
                : 'Declined — your module leader has been told'),
            backgroundColor: accept ? AppColors.green : AppColors.amber));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
    if (mounted) setState(() => _busy.remove(id));
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);
    if (_loading) {
      return const Padding(padding: EdgeInsets.all(16), child: ShimmerList());
    }
    if (_rows.isEmpty) {
      return const EmptyState(
          icon: Icons.assignment_ind_outlined,
          title: 'Nothing allocated to you yet',
          subtitle: 'Your department\'s module leader allocates the semester\'s '
              'courses — they appear here and in the New Course Offering form');
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: NavInsets.content(context),
        itemCount: _rows.length,
        itemBuilder: (ctx, i) => TeachingAssignmentCard(
          row: _rows[i],
          busy: _busy.contains(_rows[i]['id']),
          onAccept: () => _respond(_rows[i], true),
          onDecline: () => _respond(_rows[i], false),
        ),
      ),
    );
  }
}

/// One allocation as the TEACHER sees it: what they were given, and the answer
/// they owe the module leader.
///
/// Public so `course_offering_layout_test` drives the real widget rather than a
/// copy — this card is one of the two places where a long [PillBadge] label
/// starved its sibling `Expanded(Text)` down to 0px.
class TeachingAssignmentCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final bool busy;
  final VoidCallback onAccept, onDecline;
  const TeachingAssignmentCard({
    super.key,
    required this.row,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final claimed = row['offering_id'] != null;
    final isLab = row['course_type'] == 'lab';
    final status = row['status'] as String? ?? 'pending';

    // Four states, not two. "Waiting for you to answer" and "you said yes but
    // haven't made the offering" are different jobs, and a declined one is
    // finished business kept only as the record of why.
    //
    // The badge is a WORD. It used to carry the whole instruction
    // ('ACCEPTED — CREATE OFFERING', 26 characters) which, as a non-flex child
    // of this Row, was laid out first at its full width and left the course
    // code beside it with nothing — so the code rendered one letter per line.
    // The instruction now lives in [hint] below, where it has the full card
    // width and can wrap like the prose it is.
    final (label, color, hint) = switch ((status, claimed)) {
      // Already turned into a running course but never answered — a real state
      // in this project, from before accept/decline existed. Telling this
      // teacher to "accept to take the class" would be nonsense; they have been
      // teaching it. Accepting is still the right button, because it is what
      // clears the module leader's queue.
      ('pending', true) => (
          'UNANSWERED',
          AppColors.amber,
          'You already created the offering for this, but never answered the '
              'allocation itself — so your module leader still has it open. '
              'Accept to close it off.'
        ),
      ('pending', false) => (
          'PENDING',
          AppColors.amber,
          'Your module leader is waiting on you. Accept to take the class, or decline with a reason.'
        ),
      ('declined', _) => ('DECLINED', AppColors.red, null),
      ('accepted', true) => ('RUNNING', AppColors.green, null),
      _ => (
          'ACCEPTED',
          AppColors.blue,
          'Next: open New Course Offering — this allocation fills the form in for you.'
        ),
    };

    final dim = AppTextStyles.labelSmall
        .copyWith(color: AppColors.textSecondaryOf(context));

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(LiquidGlass.radiusCard),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Badge UNDER the title, not beside it.
        //
        // Beside it, the badge is a non-flex child: the Row lays it out first
        // at up to its full cap and hands the Expanded whatever is left. On a
        // 320dp phone at a 1.6x text scale that left the title 90px for a
        // string needing 424px — 79% of "CSE321 · Theory" invisible, measured
        // by layout_probe's starved-text check. Capping the badge and adding
        // `maxLines: 1` to the title (the previous round of fixes) stopped it
        // rendering one letter per line, but the title was still gone; the
        // ellipsis just made its absence tidy.
        //
        // On its own line the badge competes with nothing. Costs one row of
        // height on a card that is already several lines tall.
        Text('${row['course_code']} · ${isLab ? 'Lab' : 'Theory'}',
            maxLines: 2, overflow: TextOverflow.ellipsis,
            style: AppTextStyles.titleMedium
                .copyWith(color: AppColors.textPrimaryOf(context))),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          // Uncapped: on its own line the badge has nothing to starve, and the
          // default 160 cap would clip its own label at a large text scale.
          child: PillBadge(
              label: label, color: color, maxWidth: double.infinity),
        ),
        const SizedBox(height: 3),
        Text('Batch ${row['batch']} · Section ${row['section']} · Semester ${row['semester']}',
            maxLines: 2, overflow: TextOverflow.ellipsis, style: dim),
        if ((row['note'] as String?)?.isNotEmpty == true) ...[
          const SizedBox(height: 5),
          Text(row['note'] as String,
              maxLines: 4, overflow: TextOverflow.ellipsis, style: dim),
        ],
        if (status == 'declined' &&
            (row['decline_reason'] as String?)?.isNotEmpty == true) ...[
          const SizedBox(height: 5),
          Text('Your reason: ${row['decline_reason']}',
              maxLines: 4, overflow: TextOverflow.ellipsis,
              style: AppTextStyles.labelSmall.copyWith(color: AppColors.red)),
        ],
        if (hint != null) ...[
          const SizedBox(height: 8),
          Text(hint, style: dim.copyWith(color: color)),
        ],
        if (status == 'pending') ...[
          const SizedBox(height: 12),
          // Wrap, not Row: at a large text scale these two buttons together are
          // wider than the card, and a Row answers that by clipping the Accept
          // button off the right edge — leaving the teacher looking at an
          // allocation they cannot answer.
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              // No Decline once the offering exists: the class is already
              // running with students in it, and declining would tell the
              // module leader to reassign it out from under them. Refused by
              // assert_teaching_assignment_edit() too — this only saves the
              // teacher a pointless tap and an error. Archiving the offering is
              // the supported way to call a class off.
              if (!claimed)
                OutlinedButton(
                  onPressed: busy ? null : onDecline,
                  style: rowAction(OutlinedButton.styleFrom(foregroundColor: AppColors.red)),
                  child: const Text('Decline', maxLines: 1),
                ),
              FilledButton(
                onPressed: busy ? null : onAccept,
                style: rowAction(FilledButton.styleFrom(backgroundColor: AppColors.green)),
                child: busy
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Accept', maxLines: 1),
              ),
            ],
          ),
        ],
      ]),
    );
  }
}

// ------------------------------------------------------------- allocations

class _AllocationsTab extends StatefulWidget {
  final TeachingAssignmentRepository repo;
  final String department;
  final List<String> departments;
  final ValueChanged<String> onDepartmentChanged;
  const _AllocationsTab({
    required this.repo,
    required this.department,
    required this.departments,
    required this.onDepartmentChanged,
  });

  @override
  State<_AllocationsTab> createState() => _AllocationsTabState();
}

class _AllocationsTabState extends State<_AllocationsTab> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _AllocationsTab old) {
    super.didUpdateWidget(old);
    if (old.department != widget.department) _load();
  }

  Future<void> _load() async {
    if (widget.department.isEmpty) {
      setState(() { _loading = false; _rows = []; });
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final rows = await widget.repo.fetchDepartmentAssignments(widget.department);
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _remove(Map<String, dynamic> row) async {
    // An allocation the teacher has already built an offering from is no
    // longer just a plan — pulling it would leave a live offering with no
    // record of who authorised it.
    if (row['offering_id'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Already turned into an offering — archive the offering instead'),
          backgroundColor: AppColors.amber));
      return;
    }
    // Withdrawing DELETES the allocation and the teacher's notification about
    // it, and it fired on a single tap with nothing to cancel it. It is
    // materially different depending on whether they have answered yet, so the
    // confirmation says which case this is rather than asking "are you sure".
    final answered = (row['status'] as String? ?? 'pending') == 'accepted';
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Withdraw this allocation?'),
        content: Text(
          '${row['course_code']} (Batch ${row['batch']}, Section ${row['section']}) '
          'will be taken back from ${row['teacher_name'] ?? 'this teacher'} and '
          'the class becomes free to allocate to somebody else.'
          '${answered ? '\n\nThey have already ACCEPTED it, so tell them — they are expecting to teach this.' : ''}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Keep it')),
          TextButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Withdraw', style: TextStyle(color: AppColors.red))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.repo.unassign(row['id'] as String);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
  }

  /// [prefill] is a declined allocation being handed to somebody else: the
  /// course, batch, section and semester are already decided, so only the
  /// teacher actually changes.
  Future<void> _openAssign({Map<String, dynamic>? prefill}) async {
    final created = await showGlassModal<bool>(context,
        builder: (_) => _AssignSheet(
            repo: widget.repo, department: widget.department, prefill: prefill));
    if (created == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Row(children: [
          Expanded(
            child: Text(
                widget.department.isEmpty
                    ? 'No department set'
                    : '${widget.department} · ${_rows.length} allocated',
                style: AppTextStyles.titleMedium
                    .copyWith(color: AppColors.textPrimaryOf(context))),
          ),
          // Only shown when there is more than one to choose between — a
          // single-department leader has nothing to switch.
          if (widget.departments.length > 1)
            DropdownButton<String>(
              value: widget.department,
              underline: const SizedBox.shrink(),
              items: [
                for (final d in widget.departments)
                  DropdownMenuItem(value: d, child: Text(d)),
              ],
              onChanged: (v) { if (v != null) widget.onDepartmentChanged(v); },
            ),
          const SizedBox(width: 6),
          FilledButton.icon(
            onPressed: widget.department.isEmpty ? null : _openAssign,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Allocate'),
          ),
        ]),
      ),
      Expanded(
        child: _error != null
            ? ErrorView(message: _error!, onRetry: _load)
            : _loading
                ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList())
                : _rows.isEmpty
                    ? const EmptyState(
                        icon: Icons.assignment_outlined,
                        title: 'Nothing allocated yet',
                        subtitle: 'Allocate a course, batch and section to a teacher')
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: NavInsets.content(context, top: 0),
                          itemCount: _rows.length,
                          itemBuilder: (ctx, i) => AllocationCard(
                              row: _rows[i],
                              onRemove: () => _remove(_rows[i]),
                              onReassign: () => _openAssign(prefill: _rows[i])),
                        ),
                      ),
      ),
    ]);
  }
}

/// One allocation as the MODULE LEADER sees it: who has it, whether they have
/// answered, and what became of it.
///
/// Public so `course_offering_layout_test` drives the real widget. See
/// [TeachingAssignmentCard] for why a copy in a test would be worthless here.
class AllocationCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final VoidCallback onRemove;

  /// Only offered on a declined allocation — the one state that needs the
  /// leader to act. Null in contexts that cannot open the Allocate sheet.
  final VoidCallback? onReassign;
  const AllocationCard({
    super.key,
    required this.row,
    required this.onRemove,
    this.onReassign,
  });

  @override
  Widget build(BuildContext context) {
    final claimed = row['offering_id'] != null;
    final offeringStatus = row['offering_status'] as String?;
    final response = row['status'] as String? ?? 'pending';
    // Six states now the teacher can answer. A refusal is the one that needs
    // action from the leader, so it reads loudest and carries the reason.
    //
    // Until 20260727094328 `row['status']` was ALWAYS null here — the accept/
    // decline migration added the column to teaching_assignments and never to
    // teaching_assignment_overview, which is what this reads. The `?? 'pending'`
    // default then swallowed it silently, so every allocation showed AWAITING
    // TEACHER forever and the decline panel below was unreachable code. If this
    // ever reads 'pending' for a row you know was answered, suspect the view
    // first.
    //
    // Labels are one word: as a non-flex sibling of the Expanded title, a long
    // badge is laid out first at full width and starves the title to 0px, which
    // renders it one letter per line. 'DECLINED — REASSIGN' did exactly that.
    //
    // ('pending', claimed) is its own state and must NOT read as AWAITING.
    // There is a real row in this project like that: a teacher turned an
    // allocation into a running course without ever answering it, back before
    // accept/decline existed. Lumping it in with "awaiting teacher" sends the
    // module leader chasing somebody about a class that has been live for days.
    // New ones cannot happen — assert_teaching_assignment_edit() refuses to
    // stamp an offering onto an unaccepted allocation — but the existing row
    // is history and a BEFORE UPDATE trigger cannot rewrite the past.
    final (label, color) = switch ((response, claimed, offeringStatus)) {
      ('declined', _, _) => ('DECLINED', AppColors.red),
      ('pending', true, _) => ('UNANSWERED', AppColors.amber),
      ('pending', false, _) => ('AWAITING', AppColors.amber),
      (_, true, 'approved') => ('LIVE', AppColors.green),
      (_, true, 'rejected') => ('REJECTED', AppColors.red),
      (_, true, _) => ('SUBMITTED', AppColors.blue),
      _ => ('ACCEPTED', AppColors.blue),
    };
    final isLab = row['course_type'] == 'lab';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(LiquidGlass.radiusCard),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Same starve as TeachingAssignmentCard above, same fix. This line
        // carries a person's name, which is the worst thing to truncate: at
        // 2.0x on a 320dp phone "CSE321 — Md. Masukur Rahman Chowdhury" was
        // given 90px of the 424px it needs, so the teacher this allocation is
        // about was simply not on screen.
        Text('${row['course_code']} — ${row['teacher_name'] ?? 'Unknown'}',
            maxLines: 2, overflow: TextOverflow.ellipsis,
            style: AppTextStyles.titleMedium
                .copyWith(color: AppColors.textPrimaryOf(context))),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: PillBadge(
              label: label, color: color, maxWidth: double.infinity),
        ),
        const SizedBox(height: 3),
        Text(
            '${isLab ? 'Lab' : 'Theory'} · Batch ${row['batch']} '
            'Section ${row['section']} · Semester ${row['semester']}',
            maxLines: 2, overflow: TextOverflow.ellipsis,
            style: AppTextStyles.labelSmall
                .copyWith(color: AppColors.textSecondaryOf(context))),
        if ((row['note'] as String?)?.isNotEmpty == true) ...[
          const SizedBox(height: 5),
          Text(row['note'] as String,
              maxLines: 4, overflow: TextOverflow.ellipsis,
              style: AppTextStyles.labelSmall
                  .copyWith(color: AppColors.textSecondaryOf(context))),
        ],
        // Explains the state above, so "UNANSWERED" does not just read as a
        // stranger word for "awaiting".
        if (response == 'pending' && claimed) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(LiquidGlass.radiusControl),
              border: Border.all(color: AppColors.amber.withValues(alpha: 0.3), width: 0.5),
            ),
            child: Text(
                'The offering for this already exists, but the allocation was '
                'never answered — it predates accept/decline. Nothing is wrong '
                'with the class; no need to chase anyone.',
                style: AppTextStyles.labelSmall.copyWith(color: AppColors.amber)),
          ),
        ],
        // The whole point of a decline: say who refused and why, so the leader
        // can act without chasing anyone. The class is already free -- the
        // uniqueness index ignores declined rows -- so allocating it again
        // needs no withdrawal step.
        if (response == 'declined') ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(LiquidGlass.radiusControl),
              border: Border.all(color: AppColors.red.withValues(alpha: 0.3), width: 0.5),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Reason: ${row['decline_reason'] ?? 'none given'}',
                  maxLines: 5, overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelSmall.copyWith(color: AppColors.red)),
              const SizedBox(height: 3),
              Text('This class is free — allocate it to someone else.',
                  style: AppTextStyles.labelSmall
                      .copyWith(color: AppColors.textSecondaryOf(context))),
            ]),
          ),
          // The refusal is the one state that needs the leader to DO something,
          // and it was the one state with no button at all — the card said "
          // allocate it to someone else" and left them to find their own way
          // back to the Allocate form.
          if (onReassign != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onReassign,
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                label: const Text('Reassign'),
              ),
            ),
        ],
        if (!claimed && response != 'declined')
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onRemove,
              style: TextButton.styleFrom(foregroundColor: AppColors.red),
              icon: const Icon(Icons.close_rounded, size: 16),
              label: const Text('Withdraw'),
            ),
          ),
      ]),
    );
  }
}

class _AssignSheet extends StatefulWidget {
  final TeachingAssignmentRepository repo;
  final String department;

  /// A declined allocation being passed to somebody else. Everything except
  /// the teacher is already settled, so those fields arrive filled in — the
  /// leader was otherwise retyping a course code, batch and section they had
  /// just been looking at, which is how a reassignment lands on the wrong
  /// section.
  final Map<String, dynamic>? prefill;
  const _AssignSheet({
    required this.repo,
    required this.department,
    this.prefill,
  });

  @override
  State<_AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends State<_AssignSheet> {
  final _codeCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _batchCtrl = TextEditingController();
  final _sectionCtrl = TextEditingController();
  final _semesterCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  List<Map<String, dynamic>> _teachers = [];
  String? _teacherId;
  String _courseType = 'theory';
  bool _loading = true, _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.prefill;
    if (p != null) {
      _codeCtrl.text = p['course_code'] as String? ?? '';
      _titleCtrl.text = p['course_title'] as String? ?? '';
      _batchCtrl.text = p['batch'] as String? ?? '';
      _sectionCtrl.text = p['section'] as String? ?? '';
      _semesterCtrl.text = (p['semester'] as num?)?.toString() ?? '';
      _courseType = p['course_type'] as String? ?? 'theory';
    }
    _load();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _titleCtrl.dispose();
    _batchCtrl.dispose();
    _sectionCtrl.dispose();
    _semesterCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final t = await widget.repo.fetchDepartmentTeachers(widget.department);
      if (mounted) setState(() => _teachers = t);
    } catch (_) {
      // Non-fatal: the sheet is still usable if the list fails, it just has
      // nobody to pick, and the error surfaces on save instead.
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final semester = int.tryParse(_semesterCtrl.text.trim());
    if (_teacherId == null ||
        _codeCtrl.text.trim().isEmpty ||
        _batchCtrl.text.trim().isEmpty ||
        _sectionCtrl.text.trim().isEmpty ||
        semester == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Teacher, course code, batch, section and semester are required'),
          backgroundColor: AppColors.amber));
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.repo.assign(
        department: widget.department,
        teacherId: _teacherId!,
        courseCode: _codeCtrl.text,
        courseTitle: _titleCtrl.text,
        courseType: _courseType,
        batch: _batchCtrl.text,
        section: _sectionCtrl.text,
        semester: semester,
        note: _noteCtrl.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        // The unique constraint firing here is the feature working: somebody
        // else already has this exact class. Say so in those terms.
        final msg = e.toString().contains('duplicate key')
            ? 'That course, batch and section is already allocated for this semester'
            : friendlyError(e);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg), backgroundColor: AppColors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Allocate teaching',
            style: AppTextStyles.headlineLarge.copyWith(color: AppColors.textPrimaryOf(context))),
        const SizedBox(height: 4),
        Text('${widget.department} · the teacher is notified straight away',
            style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(context))),
        const SizedBox(height: 16),
        if (_loading)
          const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
        else ...[
          DropdownButtonFormField<String>(
            initialValue: _teacherId,
            isExpanded: true,
            decoration: const InputDecoration(hintText: 'Teacher'),
            items: [
              for (final t in _teachers)
                DropdownMenuItem(
                  value: t['id'] as String,
                  child: Text(
                      '${t['full_name']}${(t['teacher_initial'] as String?)?.isNotEmpty == true ? ' (${t['teacher_initial']})' : ''}',
                      overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => setState(() => _teacherId = v),
          ),
          const SizedBox(height: 12),
          AfosTextField(hint: 'Course code (e.g. CSE221)', controller: _codeCtrl),
          const SizedBox(height: 12),
          AfosTextField(hint: 'Course title (optional)', controller: _titleCtrl),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'theory', label: Text('Theory')),
              ButtonSegment(value: 'lab', label: Text('Lab')),
            ],
            selected: {_courseType},
            onSelectionChanged: (s) => setState(() => _courseType = s.first),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: AfosTextField(hint: 'Batch', controller: _batchCtrl)),
            const SizedBox(width: 10),
            Expanded(child: AfosTextField(hint: 'Section', controller: _sectionCtrl)),
          ]),
          const SizedBox(height: 12),
          AfosTextField(
              hint: 'Semester (1–12)',
              controller: _semesterCtrl,
              keyboardType: TextInputType.number),
          const SizedBox(height: 12),
          AfosTextField(hint: 'Note to the teacher (optional)', controller: _noteCtrl, maxLines: 2),
          const SizedBox(height: 20),
          AfosButton(label: 'Allocate', loading: _saving, onTap: _save),
        ],
      ]),
    );
  }
}

// ---------------------------------------------------------- module leaders

class _LeadersTab extends StatefulWidget {
  final TeachingAssignmentRepository repo;
  final VoidCallback onChanged;
  const _LeadersTab({required this.repo, required this.onChanged});

  @override
  State<_LeadersTab> createState() => _LeadersTabState();
}

class _LeadersTabState extends State<_LeadersTab> {
  List<Map<String, dynamic>> _leaders = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final rows = await widget.repo.fetchAllLeaders();
      if (mounted) setState(() => _leaders = rows);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _revoke(String id) async {
    try {
      await widget.repo.revokeLeader(id);
      await _load();
      widget.onChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
  }

  Future<void> _openAppoint() async {
    final done = await showGlassModal<bool>(context,
        builder: (_) => _AppointSheet(repo: widget.repo));
    if (done == true) {
      await _load();
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Row(children: [
          Expanded(
            child: Text('${_leaders.length} appointed',
                style: AppTextStyles.titleMedium
                    .copyWith(color: AppColors.textPrimaryOf(context))),
          ),
          FilledButton.icon(
            onPressed: _openAppoint,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Appoint'),
          ),
        ]),
      ),
      Expanded(
        child: _error != null
            ? ErrorView(message: _error!, onRetry: _load)
            : _loading
                ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList())
                : _leaders.isEmpty
                    ? const EmptyState(
                        icon: Icons.manage_accounts_outlined,
                        title: 'No module leaders yet',
                        subtitle: 'Appoint a teacher to allocate a department\'s teaching')
                    : ListView.builder(
                        padding: NavInsets.content(context, top: 0),
                        itemCount: _leaders.length,
                        itemBuilder: (ctx, i) {
                          final l = _leaders[i];
                          final t = l['profiles'] as Map<String, dynamic>? ?? const {};
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceOf(ctx),
                              borderRadius: BorderRadius.circular(LiquidGlass.radiusCard),
                              border: Border.all(color: AppColors.borderOf(ctx), width: 0.5),
                            ),
                            child: Row(children: [
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(t['full_name'] as String? ?? 'Unknown',
                                      maxLines: 1, overflow: TextOverflow.ellipsis,
                                      style: AppTextStyles.titleMedium
                                          .copyWith(color: AppColors.textPrimaryOf(ctx))),
                                  Text('${l['department']} · ${t['email'] ?? ''}',
                                      maxLines: 1, overflow: TextOverflow.ellipsis,
                                      style: AppTextStyles.labelSmall
                                          .copyWith(color: AppColors.textSecondaryOf(ctx))),
                                ]),
                              ),
                              IconButton(
                                icon: const Icon(Icons.person_remove_outlined,
                                    size: 18, color: AppColors.red),
                                onPressed: () => _revoke(l['id'] as String),
                              ),
                            ]),
                          );
                        },
                      ),
      ),
    ]);
  }
}

class _AppointSheet extends StatefulWidget {
  final TeachingAssignmentRepository repo;
  const _AppointSheet({required this.repo});

  @override
  State<_AppointSheet> createState() => _AppointSheetState();
}

class _AppointSheetState extends State<_AppointSheet> {
  final _deptCtrl = TextEditingController();
  List<Map<String, dynamic>> _teachers = [];
  String? _teacherId;
  bool _saving = false, _searching = false;

  @override
  void initState() {
    super.initState();
    // Prefilled with the admin's own department, which is the common case;
    // still editable, because a super admin appoints across all of them.
    widget.repo.fetchMyDepartment().then((d) {
      if (mounted && d != null && _deptCtrl.text.isEmpty) {
        _deptCtrl.text = d;
      }
    });
  }

  @override
  void dispose() {
    _deptCtrl.dispose();
    super.dispose();
  }

  Future<void> _findTeachers() async {
    final dept = _deptCtrl.text.trim().toUpperCase();
    if (dept.isEmpty) return;
    setState(() { _searching = true; _teacherId = null; });
    try {
      final t = await widget.repo.fetchDepartmentTeachers(dept);
      if (mounted) setState(() => _teachers = t);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
    if (mounted) setState(() => _searching = false);
  }

  Future<void> _save() async {
    if (_teacherId == null) return;
    setState(() => _saving = true);
    try {
      await widget.repo.appointLeader(
          department: _deptCtrl.text.trim().toUpperCase(), teacherId: _teacherId!);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        final msg = e.toString().contains('duplicate key')
            ? 'Already a module leader for that department'
            : friendlyError(e);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg), backgroundColor: AppColors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Appoint a module leader',
            style: AppTextStyles.headlineLarge.copyWith(color: AppColors.textPrimaryOf(context))),
        const SizedBox(height: 4),
        Text('They keep their teacher role and can allocate this department\'s courses.',
            style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(context))),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: AfosTextField(hint: 'Department code', controller: _deptCtrl)),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: _searching ? null : _findTeachers,
            child: _searching
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Find'),
          ),
        ]),
        const SizedBox(height: 12),
        if (_teachers.isNotEmpty)
          DropdownButtonFormField<String>(
            initialValue: _teacherId,
            isExpanded: true,
            decoration: const InputDecoration(hintText: 'Teacher'),
            items: [
              for (final t in _teachers)
                DropdownMenuItem(
                    value: t['id'] as String,
                    child: Text(t['full_name'] as String? ?? '—',
                        overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _teacherId = v),
          )
        else
          Text('Enter a department code and tap Find.',
              style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(context))),
        const SizedBox(height: 20),
        AfosButton(label: 'Appoint', loading: _saving, onTap: _save),
      ]),
    );
  }
}
