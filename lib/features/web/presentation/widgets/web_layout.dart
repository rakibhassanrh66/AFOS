import 'package:flutter/material.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../config/theme/app_text_styles.dart';
import '../../../../config/theme/depth.dart';
import '../../../../config/theme/spacing.dart';

/// The four primitives the whole desktop sweep is built from.
///
/// WHY FOUR PRIMITIVES AND NOT SIXTY-TWO DESIGNS. The web build is the phone
/// app centred in a 1100px column -- `AdaptiveContentWidth`, adopted by three
/// files. Giving each of 62 screens its own bespoke desktop layout would take
/// a month and produce 62 slightly different ideas about what a page is.
/// Applying four primitives produces one idea about what a page is, applied 62
/// times, and a reviewer can hold all four in their head.
///
/// THE VISUAL BRIEF, and what it rules out. The owner asked for something that
/// reads as far more advanced than the phone app, and separately decided the
/// design constitution stands: no gradient surfaces, no multi-surface glass,
/// no neon. So "advanced" here is not decoration. It is:
///
///   * DENSITY -- a 1440px screen shows a queue as thirty rows, not six cards.
///   * DEPTH -- real occlusion from the one top-left light, so panes sit
///     above the page rather than being drawn on it.
///   * TABULAR NUMERICS -- figures line up in columns and can be compared.
///   * MOTION THAT MEANS SOMETHING -- entrance on first mount only, never on
///     rebuild, and nothing that moves for its own sake.
///
/// An instrument panel, not a game menu. It also ages: nothing here is going
/// to look like 2026 in three years.

/// Desktop breakpoints, above the three Material window classes already in
/// `Responsive`. Those answer "phone / tablet / desktop"; these answer "how
/// many columns of content fit", which is the only question this file has.
class WebBreak {
  WebBreak._();

  /// Below this a page is a single column, whatever it would prefer.
  static const double twoPane = 1180;

  /// Above this a page may afford a permanent side rail as well.
  static const double threePane = 1560;

  static bool twoUp(BuildContext c) =>
      MediaQuery.sizeOf(c).width >= twoPane;
  static bool threeUp(BuildContext c) =>
      MediaQuery.sizeOf(c).width >= threePane;
}

/// A page inside the web shell: a title, optional actions, optional side rail.
///
/// Replaces `Scaffold + AfosAppBar + AdaptiveContentWidth` on web. The title
/// lives here rather than in a second app bar because the shell already has a
/// header -- two stacked bars was one of the things that made the web build
/// read as a phone app someone had resized.
class WebPage extends StatelessWidget {
  final String title;
  final String? subtitle;

  /// Buttons that act on the whole page. Rendered top-right, where a desktop
  /// user looks for them, rather than in a floating action button.
  final List<Widget> actions;

  final Widget child;

  /// Secondary content -- filters, a summary, a help panel. Becomes a column
  /// beside the content above [WebBreak.threePane] and is appended below it
  /// otherwise, so nothing is ever unreachable at a narrow width.
  final Widget? sideRail;

  /// Constrains reading-width content (forms, prose). Queues and tables pass
  /// null and use the full width, which is the entire point of the redesign.
  final double? maxContentWidth;

  const WebPage({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const [],
    this.sideRail,
    this.maxContentWidth,
  });

  @override
  Widget build(BuildContext context) {
    final header = Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpace.lg, AppSpace.lg, AppSpace.lg, AppSpace.md),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: AppTextStyles.displayMedium.copyWith(
                    color: AppColors.textPrimaryOf(context),
                    fontWeight: FontWeight.w700)),
            if (subtitle != null) ...[
              const SizedBox(height: AppSpace.xs),
              Text(subtitle!,
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textSecondaryOf(context))),
            ],
          ]),
        ),
        if (actions.isNotEmpty)
          Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: actions),
      ]),
    );

    Widget body = child;
    if (maxContentWidth != null) {
      body = Align(
        alignment: AlignmentDirectional.topStart,
        child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxContentWidth!), child: body),
      );
    }

    if (sideRail != null) {
      body = WebBreak.threeUp(context)
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: body),
              const SizedBox(width: AppSpace.lg),
              SizedBox(width: 320, child: sideRail),
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              body,
              const SizedBox(height: AppSpace.lg),
              sideRail!,
            ]);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      header,
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpace.lg, 0, AppSpace.lg, AppSpace.xl),
          child: body,
        ),
      ),
    ]);
  }
}

/// A surface that sits ABOVE the page rather than being drawn on it.
///
/// Uses `AppDepth.litOffset`, so its shadow falls down and to the right from
/// the one top-left light every other surface in the app obeys. That single
/// detail is most of why a desktop layout reads as built rather than
/// assembled: a dozen panels all lit from the same place look like objects on
/// a desk, and a dozen panels with straight-down shadows look like a diagram.
class WebPanel extends StatelessWidget {
  final String? title;
  final Widget child;
  final List<Widget> actions;
  final EdgeInsetsGeometry padding;

  const WebPanel({
    super.key,
    required this.child,
    this.title,
    this.actions = const [],
    this.padding = const EdgeInsets.all(AppSpace.md),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: AppDepth.radius(2),
        border: Border.all(color: AppColors.borderOf(context), width: 0.5),
        boxShadow: AppDepth.shadow(1,
            isDark: Theme.of(context).brightness == Brightness.dark),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (title != null)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpace.md, AppSpace.md, AppSpace.sm, 0),
            child: Row(children: [
              Expanded(
                child: Text(title!,
                    style: AppTextStyles.titleMedium.copyWith(
                        color: AppColors.textPrimaryOf(context),
                        fontWeight: FontWeight.w700)),
              ),
              ...actions,
            ]),
          ),
        Padding(padding: padding, child: child),
      ]),
    );
  }
}

/// A row of figures across the top of a console.
///
/// TABULAR NUMERICS, deliberately. Numbers in a proportional face cannot be
/// compared down a column -- a 1 is narrower than an 8, so the eye has nothing
/// to line up on. `AppTextStyles` already declares a tabular role; this is the
/// first thing on the web to use it for its actual purpose.
class WebStatStrip extends StatelessWidget {
  final List<WebStat> stats;
  const WebStatStrip({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, box) {
      // Never more than 5: one long row of tiny figures is as unreadable as a
      // single column of huge ones.
      //
      // The FLOOR used to be 2 as well, for the same stated reason — but on a
      // narrow window that floor produced exactly the unreadability it was
      // meant to prevent. At 320dp it forced two cells of ~154px, leaving
      // "Incomplete profiles" 64px of text space and rendering 16px of it:
      // "In…", at the DEFAULT text size. The probe caught all three labels
      // truncated that way.
      //
      // The floor is now 1, because 240 ALREADY encodes the minimum readable
      // cell width — flooring at 2 contradicted it, forcing two 194px cells
      // into a 400dp window and truncating every label. Honour the 240 and
      // the count falls out correctly: one column under 480dp, two up to
      // 720dp, and so on to the cap of five.
      //
      // And 240 itself scales with the reader's text, because it is a budget
      // for TEXT: a cell that comfortably holds "Incomplete profiles" at the
      // default size holds a quarter of it at 2.0x. Without this the strip
      // kept three columns at any scale and clipped the caption that gives
      // each figure its meaning.
      final minCell = MediaQuery.textScalerOf(ctx).scale(240);
      final perRow = (box.maxWidth ~/ minCell).clamp(1, 5);
      final width = (box.maxWidth - (perRow - 1) * AppSpace.md) / perRow;
      return Wrap(
        spacing: AppSpace.md,
        runSpacing: AppSpace.md,
        children: [
          for (final s in stats) SizedBox(width: width, child: _StatCell(stat: s)),
        ],
      );
    });
  }
}

class WebStat {
  final String label;
  final String value;
  final IconData icon;
  final Color accent;

  /// Optional one-line reading of the number. A figure with no interpretation
  /// makes the reader do the work: "3" means nothing, "3 overdue" is an
  /// instruction.
  final String? note;

  /// Tapping a figure should go to the thing it counts. A statistic you cannot
  /// act on is decoration.
  final VoidCallback? onTap;

  const WebStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    this.note,
    this.onTap,
  });
}

class _StatCell extends StatelessWidget {
  final WebStat stat;
  const _StatCell({required this.stat});

  @override
  Widget build(BuildContext context) {
    final body = WebPanel(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: stat.accent.withValues(alpha: 0.12),
            borderRadius: AppDepth.radius(1),
          ),
          child: Icon(stat.icon, size: 20, color: stat.accent),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(stat.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.displayMedium.copyWith(
                      color: AppColors.textPrimaryOf(context),
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    )),
                // Two lines, not one. This line is what the figure MEANS —
                // "13" says nothing without "Incomplete profiles" — and at
                // one line it was being ellipsised inside a perfectly roomy
                // 164px cell on a 768dp tablet, at the default text size.
                // Clipping the caption to protect a fixed row height is the
                // wrong trade: the cells sit in a Wrap that grows happily.
                Text(stat.note ?? stat.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.labelSmall
                        .copyWith(color: AppColors.textSecondaryOf(context))),
              ]),
        ),
      ]),
    );
    if (stat.onTap == null) return body;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: stat.onTap, child: body),
    );
  }
}

/// A dense readout: the desktop answer to a column of stacked cards.
///
/// A queue of thirty items on a 1440px screen is thirty rows, not six cards
/// that each waste 200px of horizontal space on a phone-shaped layout. Below
/// [WebBreak.twoPane] it hands back to whatever the mobile screen already
/// renders, because a table in a 700px window is worse than the cards were.
class WebDataTable extends StatelessWidget {
  final List<WebColumn> columns;
  final int rowCount;

  /// Cells for one row, in column order. Returning fewer cells than there are
  /// columns is a programming error and will throw in debug.
  final List<Widget> Function(int index) rowBuilder;

  final void Function(int index)? onRowTap;
  final Widget? empty;

  const WebDataTable({
    super.key,
    required this.columns,
    required this.rowCount,
    required this.rowBuilder,
    this.onRowTap,
    this.empty,
  });

  @override
  Widget build(BuildContext context) {
    if (rowCount == 0 && empty != null) return empty!;
    final border = AppColors.borderOf(context);

    return WebPanel(
      padding: EdgeInsets.zero,
      child: Column(children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.md, vertical: AppSpace.sm),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: border, width: 0.5)),
          ),
          child: Row(children: [
            for (final c in columns)
              Expanded(
                flex: c.flex,
                child: Text(c.label,
                    textAlign: c.numeric ? TextAlign.end : TextAlign.start,
                    style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.textSecondaryOf(context),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4)),
              ),
          ]),
        ),
        // Rows. ListView.builder, never a mapped list: a queue is unbounded by
        // nature and the constitution bans unbounded ListViews for exactly the
        // case where somebody has 4,000 rows.
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: rowCount,
          itemBuilder: (ctx, i) {
            final cells = rowBuilder(i);
            assert(cells.length == columns.length,
                'row $i produced ${cells.length} cells for ${columns.length} columns');
            final row = Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.md, vertical: AppSpace.sm),
              decoration: BoxDecoration(
                border: i == rowCount - 1
                    ? null
                    : Border(bottom: BorderSide(color: border, width: 0.5)),
              ),
              child: Row(children: [
                for (var c = 0; c < columns.length; c++)
                  Expanded(
                    flex: columns[c].flex,
                    child: Align(
                      alignment: columns[c].numeric
                          ? AlignmentDirectional.centerEnd
                          : AlignmentDirectional.centerStart,
                      child: cells[c],
                    ),
                  ),
              ]),
            );
            if (onRowTap == null) return row;
            return MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(onTap: () => onRowTap!(i), child: row),
            );
          },
        ),
      ]),
    );
  }
}

class WebColumn {
  final String label;
  final int flex;

  /// Right-aligns the column and is the caller's cue to render the cell with
  /// tabular figures, so a column of numbers can be read down.
  final bool numeric;

  const WebColumn(this.label, {this.flex = 1, this.numeric = false});
}

/// Master/detail. The single most useful desktop pattern and the one the phone
/// app cannot express: a list and the thing it selects, side by side, with no
/// navigation between them.
///
/// Below [WebBreak.twoPane] it renders the master only and hands selection
/// back to the caller to push a route, so narrow windows behave exactly as the
/// phone does.
class WebSplit extends StatelessWidget {
  final Widget master;
  final Widget? detail;

  /// Shown in the detail pane when nothing is selected. Not an error state --
  /// an empty detail pane with no explanation is the desktop equivalent of a
  /// blank screen.
  final Widget? placeholder;

  final double masterWidth;

  const WebSplit({
    super.key,
    required this.master,
    this.detail,
    this.placeholder,
    this.masterWidth = 380,
  });

  @override
  Widget build(BuildContext context) {
    if (!WebBreak.twoUp(context)) return master;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: masterWidth, child: master),
      const SizedBox(width: AppSpace.lg),
      Expanded(child: detail ?? placeholder ?? const SizedBox.shrink()),
    ]);
  }
}

/// Responsive column grid. Content decides how narrow it may get; the grid
/// decides how many fit. Avoids the banned "three equal cards in a row" by
/// being driven by available width rather than by a hardcoded count.
class WebGrid extends StatelessWidget {
  final List<Widget> children;
  final double minItemWidth;
  final double spacing;

  const WebGrid({
    super.key,
    required this.children,
    this.minItemWidth = 320,
    this.spacing = AppSpace.md,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, box) {
      final perRow = (box.maxWidth ~/ minItemWidth).clamp(1, 6);
      final width = (box.maxWidth - (perRow - 1) * spacing) / perRow;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final c in children) SizedBox(width: width, child: c),
        ],
      );
    });
  }
}
