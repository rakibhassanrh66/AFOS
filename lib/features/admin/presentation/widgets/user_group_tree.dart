import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../config/theme/app_colors.dart';
import '../../../../config/theme/app_text_styles.dart';
import '../../../../config/theme/depth.dart';
import '../../../../config/theme/motion.dart';
import '../../../../config/theme/spacing.dart';

/// One row of `admin_user_groups()` — a leaf group and the two labels above it.
///
/// The count comes from the DATABASE, not from how many rows happen to be
/// loaded. A header reading "40" above 50 visible rows is worse than no header
/// at all, so the count and the rows are fetched with the same group keys and
/// cannot describe different populations.
class UserGroup {
  final String l1Key, l1Label, l2Key, l2Label;
  final int count;

  const UserGroup({
    required this.l1Key,
    required this.l1Label,
    required this.l2Key,
    required this.l2Label,
    required this.count,
  });

  factory UserGroup.fromJson(Map<String, dynamic> j) => UserGroup(
        l1Key: '${j['l1key'] ?? 'unset'}',
        l1Label: '${j['l1label'] ?? 'Not set'}',
        l2Key: '${j['l2key'] ?? 'unset'}',
        l2Label: '${j['l2label'] ?? 'Not set'}',
        count: (j['count'] as num?)?.toInt() ?? 0,
      );

  /// Identity for expansion state. Two batches can share a label across
  /// different intakes ("Batch 68" appears under both Summer 2023 and Intake
  /// not set), so the pair is what identifies a group, never the label.
  String get id => '$l1Key::$l2Key';
}

/// A directory grouped the way the people in it are actually organised, rather
/// than one flat list of everybody.
///
/// Rows are loaded per group, on expand — the whole point of grouping a
/// directory that is expected to hold thousands is that opening one section
/// never downloads the rest.
class UserGroupTree extends StatefulWidget {
  final List<UserGroup> groups;

  /// Fetches the rows for one leaf group. Called once per group and cached
  /// until [groups] changes.
  final Future<List<Map<String, dynamic>>> Function(UserGroup) rowsFor;
  final Widget Function(Map<String, dynamic> user) itemBuilder;
  final EdgeInsetsGeometry padding;

  const UserGroupTree({
    super.key,
    required this.groups,
    required this.rowsFor,
    required this.itemBuilder,
    this.padding = EdgeInsets.zero,
  });

  @override
  State<UserGroupTree> createState() => _UserGroupTreeState();
}

class _UserGroupTreeState extends State<UserGroupTree> {
  final _open = <String>{};
  final _rows = <String, List<Map<String, dynamic>>>{};
  final _loading = <String>{};
  final _failed = <String, String>{};

  @override
  void didUpdateWidget(covariant UserGroupTree old) {
    super.didUpdateWidget(old);
    // The filter or the search changed underneath us: cached rows describe a
    // population that no longer exists.
    if (!identical(old.groups, widget.groups)) {
      _rows.clear();
      _loading.clear();
      _failed.clear();
    }
  }

  Future<void> _toggle(UserGroup g) async {
    final id = g.id;
    if (_open.contains(id)) {
      setState(() => _open.remove(id));
      return;
    }
    setState(() {
      _open.add(id);
      _failed.remove(id);
    });
    if (_rows.containsKey(id) || _loading.contains(id)) return;

    setState(() => _loading.add(id));
    try {
      final rows = await widget.rowsFor(g);
      if (!mounted) return;
      setState(() {
        _rows[id] = rows;
        _loading.remove(id);
      });
    } catch (e) {
      if (!mounted) return;
      // A failed fetch must not render as an empty group. "No one here" and
      // "we could not ask" are different answers and this screen has faked the
      // first one before.
      setState(() {
        _loading.remove(id);
        _failed[id] = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Preserve the server's ordering while collecting the level-2 groups that
    // sit under each level-1 heading.
    final order = <String>[];
    final byL1 = <String, List<UserGroup>>{};
    for (final g in widget.groups) {
      if (!byL1.containsKey(g.l1Key)) {
        order.add(g.l1Key);
        byL1[g.l1Key] = [];
      }
      byL1[g.l1Key]!.add(g);
    }

    return ListView.builder(
      padding: widget.padding,
      itemCount: order.length,
      itemBuilder: (context, i) {
        final l1 = order[i];
        final children = byL1[l1]!;
        final total = children.fold<int>(0, (a, g) => a + g.count);
        return _L1Section(
          label: children.first.l1Label,
          total: total,
          index: i,
          children: [
            for (final g in children)
              _L2Tile(
                group: g,
                open: _open.contains(g.id),
                loading: _loading.contains(g.id),
                error: _failed[g.id],
                rows: _rows[g.id],
                onTap: () => _toggle(g),
                itemBuilder: widget.itemBuilder,
              ),
          ],
        );
      },
    );
  }
}

/// The section heading used by every grouped list on this screen — the
/// directory and the approval queue — so the two read as one system rather
/// than two lists that happen to sit in the same app.
///
/// The count is tabular-figure aligned: a column of counts that jitters as
/// digits change is the small thing that makes a dense screen look homemade.
class GroupSectionHeader extends StatelessWidget {
  final String label;
  final int total;

  const GroupSectionHeader({super.key, required this.label, required this.total});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(4, 0, 4, AppSpace.sm),
      child: Row(children: [
        Expanded(
          child: Text(
            label.toUpperCase(),
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.textSecondaryOf(context),
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text(
          '$total',
          style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.textSecondaryOf(context),
              fontFeatures: const [FontFeature.tabularFigures()]),
        ),
      ]),
    );
  }
}

class _L1Section extends StatelessWidget {
  final String label;
  final int total;
  final int index;
  final List<Widget> children;

  const _L1Section({
    required this.label,
    required this.total,
    required this.index,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, AppSpace.xl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GroupSectionHeader(label: label, total: total),
        ...children,
      ]),
    ).animate(delay: AppMotion.staggerFor(context, index)).fadeIn(
        duration: AppMotion.durationOf(context, AppMotion.base));
  }
}

class _L2Tile extends StatelessWidget {
  final UserGroup group;
  final bool open, loading;
  final String? error;
  final List<Map<String, dynamic>>? rows;
  final VoidCallback onTap;
  final Widget Function(Map<String, dynamic>) itemBuilder;

  const _L2Tile({
    required this.group,
    required this.open,
    required this.loading,
    required this.error,
    required this.rows,
    required this.onTap,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final border = AppColors.borderOf(context);
    return Container(
      margin: const EdgeInsetsDirectional.fromSTEB(0, 0, 0, AppSpace.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: AppDepth.radius(1),
        border: Border.all(color: border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            // 48dp floor: a header that collapses a whole cohort has to be
            // comfortably tappable.
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                  AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.sm),
              child: Row(children: [
                AnimatedRotation(
                  turns: open ? 0.25 : 0,
                  duration: AppMotion.durationOf(context, AppMotion.tight),
                  child: Icon(Icons.chevron_right_rounded,
                      size: 20, color: AppColors.textSecondaryOf(context)),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text(group.l2Label,
                      style: AppTextStyles.titleMedium.copyWith(
                          color: AppColors.textPrimaryOf(context))),
                ),
                Container(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                      AppSpace.sm, 2, AppSpace.sm, 2),
                  decoration: BoxDecoration(
                    color: AppColors.holoBlue.withValues(alpha: 0.12),
                    borderRadius: AppDepth.radius(0),
                  ),
                  child: Text('${group.count}',
                      style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.holoBlue,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                ),
              ]),
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpace.sm, 0, AppSpace.sm, AppSpace.sm),
            child: _body(context),
          ),
      ]),
    );
  }

  Widget _body(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(AppSpace.lg),
        child: Center(
          child: SizedBox(
            width: 20, height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.holoBlue),
          ),
        ),
      );
    }
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Row(children: [
          const Icon(Icons.error_outline, size: 16, color: AppColors.red),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text('Could not load this group. Tap to retry.',
                style: AppTextStyles.labelSmall
                    .copyWith(color: AppColors.textSecondaryOf(context))),
          ),
        ]),
      );
    }
    final list = rows ?? const <Map<String, dynamic>>[];
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Text('No one in this group.',
            style: AppTextStyles.labelSmall
                .copyWith(color: AppColors.textSecondaryOf(context))),
      );
    }
    return Column(children: [for (final u in list) itemBuilder(u)]);
  }
}
