import 'package:flutter/material.dart';

import '../../../config/theme/app_colors.dart';
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

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const AfosAppBar(title: 'Teaching Load'),
      body: Column(children: [
        if (_isAdmin) ...[
          const SizedBox(height: 10),
          GlassTabBar(
            tabs: const [
              GlassTab('Allocations', icon: Icons.assignment_outlined),
              GlassTab('Module Leaders', icon: Icons.manage_accounts_outlined),
            ],
            currentIndex: _tab,
            onChanged: (i) => setState(() => _tab = i),
          ),
        ],
        const SizedBox(height: 8),
        Expanded(
          child: _tab == 1 && _isAdmin
              ? _LeadersTab(repo: _repo, onChanged: _load)
              : _AllocationsTab(
                  repo: _repo,
                  department: _department ?? '',
                  departments: _myDepartments,
                  onDepartmentChanged: (d) => setState(() => _department = d),
                ),
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
        itemBuilder: (ctx, i) {
          final r = _rows[i];
          final claimed = r['offering_id'] != null;
          final isLab = r['course_type'] == 'lab';
          final status = r['status'] as String? ?? 'pending';
          final busy = _busy.contains(r['id']);
          // Four states, not two. "Waiting for you to answer" and "you said yes
          // but haven't made the offering" are different jobs, and a declined
          // one is finished business kept only as the record of why.
          final (label, color) = switch ((status, claimed)) {
            ('pending', _) => ('NEEDS YOUR ANSWER', AppColors.amber),
            ('declined', _) => ('YOU DECLINED', AppColors.red),
            ('accepted', true) => ('OFFERING CREATED', AppColors.green),
            _ => ('ACCEPTED — CREATE OFFERING', AppColors.blue),
          };
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceOf(ctx),
              borderRadius: BorderRadius.circular(LiquidGlass.radiusCard),
              border: Border.all(color: color.withValues(alpha: 0.3), width: 0.8),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text('${r['course_code']} · ${isLab ? 'Lab' : 'Theory'}',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleMedium
                          .copyWith(color: AppColors.textPrimaryOf(ctx))),
                ),
                PillBadge(label: label, color: color),
              ]),
              const SizedBox(height: 3),
              Text(
                  'Batch ${r['batch']} · Section ${r['section']} · Semester ${r['semester']}',
                  style: AppTextStyles.labelSmall
                      .copyWith(color: AppColors.textSecondaryOf(ctx))),
              if ((r['note'] as String?)?.isNotEmpty == true) ...[
                const SizedBox(height: 5),
                Text(r['note'] as String,
                    style: AppTextStyles.labelSmall
                        .copyWith(color: AppColors.textSecondaryOf(ctx))),
              ],
              if (status == 'declined' &&
                  (r['decline_reason'] as String?)?.isNotEmpty == true) ...[
                const SizedBox(height: 5),
                Text('Your reason: ${r['decline_reason']}',
                    style: AppTextStyles.labelSmall.copyWith(color: AppColors.red)),
              ],
              if (status == 'pending') ...[
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  OutlinedButton(
                    onPressed: busy ? null : () => _respond(r, false),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.red),
                    child: const Text('Decline'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: busy ? null : () => _respond(r, true),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.green),
                    child: busy
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Accept'),
                  ),
                ]),
              ],
            ]),
          );
        },
      ),
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

  Future<void> _openAssign() async {
    final created = await showGlassModal<bool>(context,
        builder: (_) => _AssignSheet(repo: widget.repo, department: widget.department));
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
                          itemBuilder: (ctx, i) => _AllocationCard(
                              row: _rows[i], onRemove: () => _remove(_rows[i])),
                        ),
                      ),
      ),
    ]);
  }
}

class _AllocationCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final VoidCallback onRemove;
  const _AllocationCard({required this.row, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final claimed = row['offering_id'] != null;
    final offeringStatus = row['offering_status'] as String?;
    final response = row['status'] as String? ?? 'pending';
    // Five states now the teacher can answer. A refusal is the one that needs
    // action from the leader, so it reads loudest and carries the reason.
    final (label, color) = switch ((response, claimed, offeringStatus)) {
      ('declined', _, _) => ('DECLINED — REASSIGN', AppColors.red),
      ('pending', _, _) => ('AWAITING TEACHER', AppColors.amber),
      (_, true, 'approved') => ('LIVE', AppColors.green),
      (_, true, 'rejected') => ('OFFERING REJECTED', AppColors.red),
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
        Row(children: [
          Expanded(
            child: Text('${row['course_code']} — ${row['teacher_name'] ?? 'Unknown'}',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: AppTextStyles.titleMedium
                    .copyWith(color: AppColors.textPrimaryOf(context))),
          ),
          PillBadge(label: label, color: color),
        ]),
        const SizedBox(height: 3),
        Text(
            '${isLab ? 'Lab' : 'Theory'} · Batch ${row['batch']} '
            'Section ${row['section']} · Semester ${row['semester']}',
            style: AppTextStyles.labelSmall
                .copyWith(color: AppColors.textSecondaryOf(context))),
        if ((row['note'] as String?)?.isNotEmpty == true) ...[
          const SizedBox(height: 5),
          Text(row['note'] as String,
              style: AppTextStyles.labelSmall
                  .copyWith(color: AppColors.textSecondaryOf(context))),
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
                  style: AppTextStyles.labelSmall.copyWith(color: AppColors.red)),
              const SizedBox(height: 3),
              Text('This class is free — allocate it to someone else.',
                  style: AppTextStyles.labelSmall
                      .copyWith(color: AppColors.textSecondaryOf(context))),
            ]),
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
  const _AssignSheet({required this.repo, required this.department});

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
