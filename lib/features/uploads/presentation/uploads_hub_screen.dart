import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_icons.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/button_styles.dart';
import '../../../config/theme/depth.dart';
import '../../../config/theme/motion.dart';
import '../../../core/auth/permission_session.dart';
import '../../../core/auth/role_session.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/layout/nav_insets.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/feature_header.dart';
import '../../../shared/widgets/glass_chip.dart';
import '../../../shared/widgets/glass_sheet.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../../shared/widgets/surface_card.dart';
import '../../shell/presentation/top_app_bar.dart';
import '../data/upload_backup_pdf.dart';
import '../data/upload_batch.dart';

/// One place for everything the university loads into AFOS.
///
/// Before this the five importers lived in three unrelated places under three
/// unrelated names — "Upload Routine/Transport", "Manage Exam Seats", "Notices
/// & Rules" — and none of them recorded who had done what. Asked which upload
/// put a row somewhere, or how to take one back out, the app had no answer.
///
/// So this is a hub and a ledger, not a rename. Every kind is reachable from
/// here, every import leaves a row underneath, and removing one is a two-step
/// gesture: take the backup, then remove.
class UploadsHubScreen extends StatefulWidget {
  const UploadsHubScreen({super.key});
  @override
  State<UploadsHubScreen> createState() => _UploadsHubState();
}

class _UploadsHubState extends State<UploadsHubScreen> {
  List<UploadBatch> _history = const [];
  Set<String> _grants = const {};
  String? _role;
  bool _loading = true;
  String? _error;

  // -- bulk cleanup ("release storage pressure") -----------------------------
  //
  // The per-batch sheet below already does backup-then-remove safely, but one
  // batch at a time doesn't scale to "clean out last term's old uploads" —
  // that can be dozens of rows to open individually. This adds a filtered,
  // multi-select layer on TOP of the same two proven server calls
  // (UploadBackupPdf.generateAndStore, UploadBatchService.revert), never a
  // new deletion path of its own.
  bool _selectMode = false;
  final Set<String> _selectedIds = {};
  String? _filterKind;
  String? _filterDept;
  bool _bulkBusy = false;
  String? _bulkError;
  String? _bulkNote;

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<UploadBatch> get _filteredHistory =>
      filterUploadBatches(_history, kind: _filterKind, department: _filterDept);

  /// Kinds actually present in the ledger, in the same order the hub already
  /// lists them — not every kind the person is allowed to upload, since a
  /// filter chip for a kind with zero history rows filters to an empty list.
  List<String> get _kindsInHistory {
    final present = _history.map((b) => b.kind).toSet();
    return _kinds.map((k) => k.kind).where(present.contains).toList();
  }

  List<String> get _departmentsInHistory => departmentsInBatches(_history);

  void _toggleSelectMode() => setState(() {
        _selectMode = !_selectMode;
        _selectedIds.clear();
        _bulkError = null;
        _bulkNote = null;
      });

  void _toggleSelected(String id) => setState(() {
        _selectedIds.contains(id) ? _selectedIds.remove(id) : _selectedIds.add(id);
      });

  Future<void> _bulkRemove() async {
    final targets = _history.where((b) => _selectedIds.contains(b.id) && b.canRevert).toList();
    if (targets.isEmpty) return;
    final totalRows = targets.fold<int>(0, (a, b) => a + b.rowCount);

    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Remove ${targets.length} uploads?'),
        content: Text(
            'This deletes $totalRows rows across ${targets.length} uploads. '
            'A backup PDF is generated and stored for each one first — the '
            'server refuses any that fails its own backup, and those are '
            'reported below rather than left half-done.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Remove all')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      _bulkBusy = true;
      _bulkError = null;
      _bulkNote = null;
    });

    // Sequential, not Future.wait — each iteration is a backup upload plus a
    // delete RPC against the same account; running dozens at once is exactly
    // the kind of self-inflicted burst load a "free up storage" tool should
    // not itself cause. One failure must not stop the rest: an admin working
    // through a term's worth of old batches should not lose progress on item
    // 30 because item 12 hit a network blip.
    var removed = 0, rowsRemoved = 0;
    final failures = <String>[];
    for (final b in targets) {
      try {
        await UploadBackupPdf.generateAndStore(b);
        final res = await UploadBatchService.revert(b.id);
        removed++;
        rowsRemoved += (res.summary['rowsRemoved'] as num?)?.toInt() ?? b.rowCount;
      } catch (e) {
        failures.add('${b.kindLabel} (${b.sourceFile ?? b.id}): ${friendlyError(e)}');
      }
    }

    setState(() {
      _bulkBusy = false;
      _selectedIds.clear();
      _selectMode = false;
      _bulkNote = removed > 0 ? 'Removed $rowsRemoved rows across $removed upload(s).' : null;
      _bulkError = failures.isEmpty
          ? null
          : '${failures.length} could not be removed:\n${failures.join('\n')}';
    });
    await _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      _role = RoleSession.role;
      _grants = await PermissionSession.ensureLoaded();
      final rows = await UploadBatchService.list();
      if (mounted) setState(() => _history = rows);
    } catch (e) {
      // The kinds above still render: a person who came here to upload
      // something should not be blocked because the ledger failed to load.
      if (mounted) setState(() => _error = friendlyError(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Which kinds this person may use. Delegated to `uploadKindsFor` so the
  /// rule sits beside the RLS it mirrors and can be tested without a screen.
  Set<String> get _allowed =>
      uploadKindsFor(role: _role, grants: _grants).toSet();

  /// The five kinds, in the order the owner listed them.
  List<_UploadKind> get _kinds => [
        _UploadKind(
          kind: 'class_routine',
          hint: 'Weekly class timetable',
          icon: AppIcons.schedule,
          accent: AppColors.blue,
          route: '/admin/upload/files',
          enabled: _allowed.contains('class_routine'),
        ),
        _UploadKind(
          kind: 'exam_routine',
          hint: 'Which exam sits when',
          icon: AppIcons.examSeat,
          accent: AppColors.holoTeal,
          route: '/admin/upload/exam-routine',
          enabled: _allowed.contains('exam_routine'),
        ),
        _UploadKind(
          kind: 'transport',
          hint: 'Bus routes and stop times',
          icon: AppIcons.transport,
          accent: AppColors.green,
          route: '/admin/upload/files',
          enabled: _allowed.contains('transport'),
        ),
        _UploadKind(
          kind: 'exam_seat_plan',
          hint: 'Which room each section sits in',
          icon: AppIcons.examSeat,
          accent: AppColors.orange,
          route: '/manage-exam-seats',
          enabled: _allowed.contains('exam_seat_plan'),
        ),
        _UploadKind(
          kind: 'notice',
          hint: 'Announcements and rules',
          icon: AppIcons.notices,
          accent: AppColors.red,
          route: '/manage-notices',
          enabled: _allowed.contains('notice'),
        ),
      ];

  Future<void> _openDetail(UploadBatch b) async {
    await showGlassModal(context,
        builder: (ctx) => _BatchSheet(batch: b, onChanged: _load));
  }

  @override
  Widget build(BuildContext context) {
    final textSecondary = AppColors.textSecondaryOf(context);
    final kinds = _kinds.where((k) => k.enabled).toList();
    final filtered = _filteredHistory;
    final anySelectable = filtered.any((b) => b.canRevert);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const AfosAppBar(title: 'Uploads'),
      bottomNavigationBar: _selectedIds.isEmpty
          ? null
          : _BulkBar(
              count: _selectedIds.length,
              busy: _bulkBusy,
              onClear: () => setState(_selectedIds.clear),
              onRemove: _bulkRemove,
            ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.blue,
        // A plain ListView, NOT AdaptiveList.
        //
        // AdaptiveList lays its ITEMS out in columns on a wide screen. This
        // page is one composed column passed as a single item, so at 1440px it
        // computed three columns, put the whole page in the first one and left
        // the other two blank -- the page rendered at a third of the width with
        // two thirds of the screen empty beside it. It looked like the phone
        // layout had been dropped into a desktop window, which is exactly what
        // it was. AdaptiveList is for MANY items; one item is not a list.
        child: ListView(
          padding: EdgeInsetsDirectional.fromSTEB(
              16, 16, 16, 16 + NavInsets.of(context)),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              const FeatureHeader(
                title: 'Uploads',
                subtitle: 'Everything the university loads into AFOS',
                icon: Icons.cloud_upload_outlined,
                gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.blue, AppColors.holoviolet]),
                margin: EdgeInsets.only(bottom: 16),
              ),
              if (kinds.isEmpty)
                const EmptyState(
                    icon: Icons.cloud_upload_outlined,
                    title: 'Nothing to upload',
                    subtitle:
                        'You have not been given any upload area. Ask a super '
                        'admin to assign one in Manage Users.')
              else
                for (var i = 0; i < kinds.length; i++)
                  _KindCard(kind: kinds[i], index: i),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(
                  child: Text('Upload history',
                      style: AppTextStyles.titleMedium
                          .copyWith(color: AppColors.textPrimaryOf(context))),
                ),
                if (!_loading && _history.isNotEmpty && anySelectable)
                  TextButton(
                    style: rowAction(),
                    onPressed: _toggleSelectMode,
                    child: Text(_selectMode ? 'Cancel' : 'Select',
                        style: AppTextStyles.bodyMedium
                            .copyWith(color: AppColors.blue, fontWeight: FontWeight.w700)),
                  ),
              ]),
              Text(
                  _selectMode
                      ? 'Pick uploads to back up and remove together — useful for '
                          'clearing out old terms\' data at once.'
                      : 'Who loaded what, and when. Removing an upload takes its '
                          'backup first.',
                  style:
                      AppTextStyles.labelSmall.copyWith(color: textSecondary)),
              const SizedBox(height: 12),
              if (!_loading && _history.length > 1 && (_kindsInHistory.length > 1 || _departmentsInHistory.length > 1)) ...[
                if (_kindsInHistory.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Wrap(spacing: 8, runSpacing: 8, children: [
                      GlassChip(
                          label: 'All kinds',
                          selected: _filterKind == null,
                          onTap: () => setState(() => _filterKind = null)),
                      for (final k in _kindsInHistory)
                        GlassChip(
                            label: UploadBatch.labelFor(k),
                            selected: _filterKind == k,
                            onTap: () => setState(() => _filterKind = k)),
                    ]),
                  ),
                if (_departmentsInHistory.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Wrap(spacing: 8, runSpacing: 8, children: [
                      GlassChip(
                          label: 'All departments',
                          selected: _filterDept == null,
                          onTap: () => setState(() => _filterDept = null)),
                      for (final d in _departmentsInHistory)
                        GlassChip(
                            label: d,
                            selected: _filterDept == d,
                            onTap: () => setState(() => _filterDept = d)),
                    ]),
                  ),
                const SizedBox(height: 8),
              ],
              if (_bulkNote != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_bulkNote!, style: const TextStyle(color: AppColors.green)),
                ),
              if (_bulkError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_bulkError!, style: const TextStyle(color: AppColors.red)),
                ),
              if (_loading)
                const ShimmerList()
              else if (_error != null)
                ErrorView(message: _error!, onRetry: _load)
              else if (_history.isEmpty)
                const EmptyState(
                    icon: Icons.history_rounded,
                    title: 'No uploads recorded yet',
                    subtitle:
                        'Imports made from here appear in this list, with the '
                        'file, the person and the row count.')
              else if (filtered.isEmpty)
                const EmptyState(
                    icon: Icons.filter_alt_off_outlined,
                    title: 'Nothing matches this filter',
                    subtitle: 'Try a different kind or department, or clear the filter above.')
              else
                for (final b in filtered)
                  _HistoryRow(
                    batch: b,
                    onTap: () => _openDetail(b),
                    selectMode: _selectMode,
                    selected: _selectedIds.contains(b.id),
                    onToggleSelected: b.canRevert ? () => _toggleSelected(b.id) : null,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _UploadKind {
  final String kind, hint, route;
  final IconData icon;
  final Color accent;
  final bool enabled;
  const _UploadKind({
    required this.kind,
    required this.hint,
    required this.route,
    required this.icon,
    required this.accent,
    required this.enabled,
  });
  String get label => UploadBatch.labelFor(kind);
}

class _KindCard extends StatelessWidget {
  final _UploadKind kind;
  final int index;
  const _KindCard({required this.kind, required this.index});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SurfaceCard(
        onTap: () {
          AppHaptics.selection();
          context.push(kind.route);
        },
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: kind.accent.withValues(alpha: 0.14),
              borderRadius: AppDepth.radius(1),
            ),
            child: Icon(kind.icon, color: kind.accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(kind.label,
                      style: AppTextStyles.titleMedium
                          .copyWith(color: AppColors.textPrimaryOf(context))),
                  Text(kind.hint,
                      style: AppTextStyles.labelSmall
                          .copyWith(color: AppColors.textSecondaryOf(context))),
                ]),
          ),
          Icon(Icons.chevron_right_rounded,
              color: AppColors.textSecondaryOf(context)),
        ]),
      ),
    ).animate(delay: AppMotion.staggerFor(context, index)).fadeIn().slideY(begin: 0.05);
  }
}

class _HistoryRow extends StatelessWidget {
  final UploadBatch batch;
  final VoidCallback onTap;
  final bool selectMode, selected;
  final VoidCallback? onToggleSelected;
  const _HistoryRow({
    required this.batch,
    required this.onTap,
    this.selectMode = false,
    this.selected = false,
    this.onToggleSelected,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    final (label, colour) = switch (batch.status) {
      'reverted' => ('Removed', AppColors.red),
      'pending' => ('Did not finish', AppColors.amber),
      _ => ('${batch.rowCount} rows', AppColors.green),
    };
    // In select mode a non-revertible batch (already removed, or nothing to
    // remove) has nothing this tool can do to it — dimmed and inert rather
    // than offering a checkbox that would fail server-side anyway.
    final dimmed = selectMode && onToggleSelected == null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Opacity(
        opacity: dimmed ? 0.5 : 1,
        child: SurfaceCard(
          onTap: selectMode ? onToggleSelected : onTap,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (selectMode) ...[
              Icon(
                  selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  size: 20,
                  color: selected
                      ? AppColors.blue
                      : AppColors.textSecondaryOf(context).withValues(alpha: 0.5)),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(batch.kindLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyMedium.copyWith(
                      color: textPrimary, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: colour.withValues(alpha: 0.14),
                  borderRadius: AppDepth.radius(0)),
              child: Text(label,
                  style: AppTextStyles.labelSmall.copyWith(
                      color: colour, fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
              [
                if ((batch.sourceFile ?? '').isNotEmpty) batch.sourceFile!,
                batch.uploader ?? 'Unknown',
                AppFormatters.fullDate(batch.uploadedAt),
              ].join('  ·  '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.labelSmall.copyWith(color: textSecondary)),
          ]),
        ),
      ),
    );
  }
}

/// One upload, and the two things that can be done with it.
class _BatchSheet extends StatefulWidget {
  final UploadBatch batch;
  final Future<void> Function() onChanged;
  const _BatchSheet({required this.batch, required this.onChanged});
  @override
  State<_BatchSheet> createState() => _BatchSheetState();
}

class _BatchSheetState extends State<_BatchSheet> {
  late UploadBatch _b = widget.batch;
  bool _busy = false;
  String? _error, _note;

  Future<void> _backup() async {
    setState(() {
      _busy = true;
      _error = null;
      _note = null;
    });
    try {
      await UploadBackupPdf.generateStoreAndOpen(_b);
      // Re-read rather than assume: the interlock the remove button reads is
      // the server's, and this is the moment it changed.
      final fresh = await UploadBatchService.list(limit: 200);
      final match = fresh.where((x) => x.id == _b.id).toList();
      if (mounted) {
        setState(() {
          if (match.isNotEmpty) _b = match.first;
          _note = 'Backup opened and stored. You can remove the upload now.';
        });
      }
      await widget.onChanged();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Remove ${_b.kindLabel}?'),
        content: Text(
            'This deletes the ${_b.rowCount} rows this upload added. '
            'The backup you downloaded is the only copy that remains.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await UploadBatchService.revert(_b.id);
      await widget.onChanged();
      if (mounted) {
        setState(() {
          _b = res;
          _note = 'Removed ${res.summary['rowsRemoved'] ?? _b.rowCount} rows.';
        });
        AppHaptics.success();
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);

    return SingleChildScrollView(
      padding: EdgeInsetsDirectional.fromSTEB(
          24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_b.kindLabel,
                style: AppTextStyles.headlineLarge.copyWith(color: textPrimary)),
            const SizedBox(height: 12),
            _row('File', _b.sourceFile ?? '—', textPrimary, textSecondary),
            _row('Uploaded by', _b.uploader ?? 'Unknown', textPrimary,
                textSecondary),
            _row('When', AppFormatters.fullDate(_b.uploadedAt), textPrimary,
                textSecondary),
            if ((_b.department ?? '').isNotEmpty)
              _row('Department', _b.department!, textPrimary, textSecondary),
            _row('Rows', '${_b.rowCount}', textPrimary, textSecondary),
            _row('Status', _b.isReverted ? 'Removed' : (_b.isPending ? 'Did not finish' : 'Applied'),
                textPrimary, textSecondary),
            if (_b.isReverted && _b.revertedAt != null)
              _row('Removed', AppFormatters.fullDate(_b.revertedAt!),
                  textPrimary, textSecondary),
            for (final e in _b.summary.entries)
              if (e.key != 'rowsRemoved')
                _row(e.key, '${e.value}', textPrimary, textSecondary),
            const SizedBox(height: 16),
            if (!_b.isReverted) ...[
              Text(
                  _b.hasBackup
                      ? 'A backup has been generated for this upload.'
                      : 'Take the backup before removing this. It contains '
                          'every row the upload added — once removed, that '
                          'document is what is left of it.',
                  style:
                      AppTextStyles.labelSmall.copyWith(color: textSecondary)),
              const SizedBox(height: 12),
              AfosButton(
                  label: _b.hasBackup ? 'Download backup again' : 'Download backup',
                  icon: Icons.download_rounded,
                  loading: _busy,
                  onTap: _backup),
              if (_b.canRevert) ...[
                const SizedBox(height: 10),
                // Deliberately not disabled-looking-but-tappable: without a
                // backup the server refuses, so the button says why instead of
                // failing after the fact.
                AfosButton(
                    label: _b.hasBackup
                        ? 'Remove this upload'
                        : 'Remove (backup required first)',
                    icon: Icons.delete_outline_rounded,
                    loading: _busy,
                    onTap: _b.hasBackup ? _remove : null),
              ],
            ],
            if (_note != null) ...[
              const SizedBox(height: 12),
              Text(_note!, style: const TextStyle(color: AppColors.green)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppColors.red)),
            ],
          ]),
    );
  }

  Widget _row(String k, String v, Color primary, Color secondary) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 110,
              child: Text(k,
                  style: AppTextStyles.labelSmall.copyWith(color: secondary))),
          Expanded(
              child: Text(v,
                  style:
                      AppTextStyles.bodyMedium.copyWith(color: primary))),
        ]),
      );
}

/// The bulk-select bottom bar. Pinned like [SelectionBar] in Join Requests —
/// a selection made scrolled far down the history list must stay actionable
/// without scrolling back up to find a floating button.
class _BulkBar extends StatelessWidget {
  final int count;
  final bool busy;
  final VoidCallback onClear;
  final Future<void> Function() onRemove;
  const _BulkBar({
    required this.count,
    required this.busy,
    required this.onClear,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsetsDirectional.fromSTEB(16, 10, 16, 10 + NavInsets.of(context)),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        border: Border(top: BorderSide(color: AppColors.borderOf(context), width: 0.5)),
      ),
      child: Row(children: [
        Expanded(
          child: Text('$count selected',
              style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textPrimaryOf(context), fontWeight: FontWeight.w700)),
        ),
        TextButton(
          style: rowAction(),
          onPressed: busy ? null : onClear,
          child: const Text('Clear'),
        ),
        const SizedBox(width: 8),
        AfosButton(
          label: 'Back up & remove',
          icon: Icons.delete_sweep_outlined,
          loading: busy,
          onTap: onRemove,
        ),
      ]),
    );
  }
}
