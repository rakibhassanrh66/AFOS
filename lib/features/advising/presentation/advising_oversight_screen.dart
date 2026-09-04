import 'package:flutter/material.dart';

import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/spacing.dart';
import '../../../core/layout/nav_insets.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/glass_chip.dart';
import '../../../shared/widgets/pill_badge.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../../shared/widgets/surface_card.dart';
import '../../shell/presentation/top_app_bar.dart';
import '../../web/presentation/widgets/adaptive_list.dart';
import '../data/models/teacher_link.dart';
import '../data/repositories/advising_repository.dart';

/// Every advisor and supervisor pairing in the university, for a super-admin.
///
/// This is where the roll-range idea survives in a form the data can support.
/// A numeric range over `university_id` cannot work — six ID shapes are in
/// use and batch 63 alone holds two of them — so instead of a rule that
/// misfires silently, an administrator sees the whole map and can correct it.
///
/// Read-only on purpose for now: revoking somebody else's advisor is a
/// decision with a conversation attached, and the screen that does it should
/// be built once that conversation has a shape.
class AdvisingOversightScreen extends StatefulWidget {
  const AdvisingOversightScreen({super.key});

  @override
  State<AdvisingOversightScreen> createState() =>
      _AdvisingOversightScreenState();
}

class _AdvisingOversightScreenState extends State<AdvisingOversightScreen> {
  final _repo = AdvisingRepository();

  /// null = both kinds.
  LinkKind? _kind;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final rows = await _repo.allLinks(kind: _kind);
      if (!mounted) return;
      setState(() {
        _rows = rows;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const AfosAppBar(title: 'Advising'),
      body: Column(children: [
        // AppSpace.chipStrip, not a bare height: these chips clip at a 2.0x
        // text scale otherwise, which is the fault Phase 0 fixed in two other
        // strips.
        SizedBox(
          height: AppSpace.chipStrip(context, 44),
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: AppSpace.screenH,
            children: [
              for (final (label, kind) in <(String, LinkKind?)>[
                ('All', null),
                ('Advisors', LinkKind.advisor),
                ('Final year', LinkKind.fydp),
              ])
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: AppSpace.sm),
                  child: Center(
                    child: GlassChip(
                      label: label,
                      selected: _kind == kind,
                      onTap: () {
                        setState(() => _kind = kind);
                        _load();
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(child: _body()),
      ]),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Padding(padding: EdgeInsets.all(16), child: ShimmerList());
    }
    if (_error != null) {
      return ErrorView(message: _error!, onRetry: _load);
    }
    if (_rows.isEmpty) {
      return const EmptyState(
        icon: Icons.hub_outlined,
        title: 'Nobody is paired yet',
        subtitle: 'Pairings appear here as students name a teacher and the '
            'teacher accepts.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: AdaptiveList(
        padding: EdgeInsetsDirectional.fromSTEB(
            AppSpace.lg, AppSpace.md, AppSpace.lg,
            AppSpace.lg + NavInsets.of(context)),
        itemCount: _rows.length,
        itemBuilder: (ctx, i) => _PairRow(row: _rows[i]),
      ),
    );
  }
}

class _PairRow extends StatelessWidget {
  final Map<String, dynamic> row;
  const _PairRow({required this.row});

  /// A PostgREST embed arrives as an object or as a single-element list. The
  /// same normalisation UserModel already carries.
  static Map<String, dynamic> _one(Object? raw) => (raw is List)
      ? (raw.isEmpty ? const {} : raw.first as Map<String, dynamic>)
      : (raw as Map<String, dynamic>? ?? const {});

  @override
  Widget build(BuildContext context) {
    final student = _one(row['student']);
    final teacher = _one(row['teacher']);
    final kind = LinkKind.parse(row['kind'] as String?);
    final status = LinkStatus.parse(row['status'] as String?);

    final (statusLabel, statusColor) = switch (status) {
      LinkStatus.active => ('ACTIVE', AppColors.green),
      LinkStatus.pending => ('WAITING', AppColors.amber),
      LinkStatus.declined => ('DECLINED', AppColors.red),
      LinkStatus.ended => ('ENDED', AppColors.textSecondary),
    };

    return SurfaceCard(
      margin: const EdgeInsetsDirectional.only(bottom: AppSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((student['university_id'] as String?) ?? '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.monoSmall
                      .copyWith(color: AppColors.textSecondaryOf(context))),
              Text((student['full_name'] as String?) ?? 'Unnamed',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.titleMedium
                      .copyWith(color: AppColors.textPrimaryOf(context))),
            ]),
          ),
          AppSpace.gapSm,
          // Flexible, so a badge cannot starve the name beside it.
          Flexible(child: PillBadge(label: statusLabel, color: statusColor)),
        ]),
        AppSpace.vGapSm,
        Row(children: [
          Icon(
              kind == LinkKind.fydp
                  ? Icons.science_rounded
                  : Icons.support_agent_rounded,
              size: 14,
              color: AppColors.textSecondaryOf(context)),
          AppSpace.gapXs,
          Expanded(
            child: Text(
              '${kind.teacherNoun}: ${teacher['full_name'] ?? 'Unnamed'}'
              '${teacher['teacher_initial'] != null ? ' (${teacher['teacher_initial']})' : ''}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textSecondaryOf(context)),
            ),
          ),
        ]),
        if ((student['batch'] as String?)?.isNotEmpty == true) ...[
          AppSpace.vGapXs,
          Text('Batch ${student['batch']}',
              style: AppTextStyles.labelSmall
                  .copyWith(color: AppColors.textSecondaryOf(context))),
        ],
      ]),
    );
  }
}
