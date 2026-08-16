import 'package:flutter/material.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/depth.dart';
import '../../../core/layout/nav_insets.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/glass_chip.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../../shared/widgets/surface_card.dart';
import '../../shell/presentation/top_app_bar.dart';

/// What happened under you.
///
/// WHY THIS EXISTS. Delegation without oversight is just a wider blast radius.
/// Once a manager can hand out work, decide CR requests and set roles, "who
/// gave this person routine upload, and who took it away" has to have an
/// answer that is not "ask them". `permission_audit` has recorded every grant
/// and revoke by trigger since it was added — append-only, with no UPDATE or
/// DELETE policy for anyone — and until now had **zero references in the app**.
/// An audit log nobody can read is a log nobody is keeping.
///
/// Three trails, one list, because the question is chronological and not
/// per-table:
///   * permission — granted / revoked
///   * cr         — Class Representative requests decided, and by whom
///   * handover   — Lost & Found items returned, verified by scan or not
///
/// Read-only by construction. The screen has no write path at all, and the
/// `authority_activity_log` RPC it calls is SELECT-only and refuses anyone who
/// is neither super_admin nor a holder of `audit:read`.
class ActivityLogScreen extends StatefulWidget {
  const ActivityLogScreen({super.key});
  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;
  String _kind = 'all';

  static const _kinds = ['all', 'permission', 'cr', 'handover'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await SupabaseConfig.client
          .rpc('authority_activity_log', params: {'p_limit': 300}) as List;
      if (mounted) {
        setState(() { _rows = res.cast<Map<String, dynamic>>(); _loading = false; });
      }
    } catch (e) {
      // Surfaced rather than rendered as an empty log: "nothing happened" and
      // "we could not find out what happened" are not the same answer, and
      // this is the one screen where confusing them matters most.
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  List<Map<String, dynamic>> get _filtered =>
      _kind == 'all' ? _rows : _rows.where((r) => r['kind'] == _kind).toList();

  static const _kindLabels = {
    'all': 'Everything',
    'permission': 'Permissions',
    'cr': 'CR decisions',
    'handover': 'Handovers',
  };

  static const _kindColors = {
    'permission': AppColors.holoviolet,
    'cr': AppColors.holoTeal,
    'handover': AppColors.amber,
  };

  static const _kindIcons = {
    'permission': Icons.key_rounded,
    'cr': Icons.badge_rounded,
    'handover': Icons.handshake_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const AfosAppBar(title: 'Activity Log'),
      body: Column(children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 4),
          child: Text(
            'Every permission change, Class Representative decision and item '
            'handover, newest first. This record is written by the database '
            'and cannot be edited by anyone, including you.',
            style: AppTextStyles.labelSmall
                .copyWith(color: AppColors.textSecondaryOf(context)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: _kinds.map((k) {
              final n = k == 'all'
                  ? _rows.length
                  : _rows.where((r) => r['kind'] == k).length;
              return GlassChip(
                label: '${_kindLabels[k]} ($n)',
                selected: k == _kind,
                color: AppColors.holoviolet,
                onTap: () => setState(() => _kind = k),
              );
            }).toList(),
          ),
        ),
        Expanded(
          child: _loading
              ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList())
              : _error != null
                  ? ErrorView(message: _error!, onRetry: _load)
                  : _filtered.isEmpty
                      ? const EmptyState(
                          icon: Icons.history_toggle_off_rounded,
                          title: 'Nothing recorded yet',
                          subtitle: 'Permission changes, CR decisions and '
                              'handovers will appear here as they happen')
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: EdgeInsetsDirectional.fromSTEB(
                                16, 8, 16, 16 + NavInsets.of(context)),
                            itemCount: _filtered.length,
                            itemBuilder: (ctx, i) => _LogRow(entry: _filtered[i]),
                          ),
                        ),
        ),
      ]),
    );
  }
}

class _LogRow extends StatelessWidget {
  final Map<String, dynamic> entry;
  const _LogRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final kind = entry['kind'] as String? ?? 'permission';
    final color = _ActivityLogScreenState._kindColors[kind] ?? AppColors.textSecondary;
    final icon = _ActivityLogScreenState._kindIcons[kind] ?? Icons.circle;
    final when = entry['occurred_at'] != null
        ? DateTime.tryParse(entry['occurred_at'] as String)
        : null;
    final actor = (entry['actor_name'] as String?)?.trim();
    final subject = (entry['subject_name'] as String?)?.trim();
    // A handover closed without a scan is the one row here that is a
    // *finding* rather than a record, so it says so instead of blending in.
    final unverified = kind == 'handover' && entry['verified'] == false;

    return SurfaceCard(
      margin: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: AppDepth.radius(0),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              entry['detail'] as String? ?? '',
              style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textPrimaryOf(context),
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              // "by X" and "to Y" are the two facts an oversight reader is
              // actually after; a row that only says what changed makes them
              // open something else to find out who did it.
              [
                if (actor != null && actor.isNotEmpty) 'by $actor',
                if (subject != null && subject.isNotEmpty) 'to $subject',
              ].join('  ·  '),
              style: AppTextStyles.labelSmall
                  .copyWith(color: AppColors.textSecondaryOf(context)),
            ),
            if (unverified) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.amber.withValues(alpha: 0.14),
                  borderRadius: AppDepth.radius(0),
                ),
                child: const Text('not verified by scan',
                    style: TextStyle(
                        color: AppColors.amber,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ]),
        ),
        const SizedBox(width: 8),
        if (when != null)
          Text(
            AppFormatters.relativeTime(when),
            style: TextStyle(color: AppColors.textMutedOf(context), fontSize: 10),
          ),
      ]),
    );
  }
}
