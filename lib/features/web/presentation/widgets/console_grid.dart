import 'package:flutter/material.dart';

import '../../../../config/theme/app_colors.dart';
import '../../../../config/theme/app_text_styles.dart';
import '../../../../config/theme/depth.dart';
import '../../../../config/theme/motion.dart';
import '../../../../config/theme/spacing.dart';

/// The size classes a console panel is allowed to be.
///
/// THIS IS THE FIX FOR "IT LOOKS SCATTERED". Before this, every panel on the
/// console sized itself: two `LayoutBuilder`s each hand-rolled an
/// `Expanded(flex: 2)` / `Expanded(flex: 3)` pair, and every panel's HEIGHT was
/// whatever its content happened to come to. Six rows of exams made one column
/// tall, a ring made the next one short, and the gap underneath the shorter one
/// was dead space. Nothing was aligned to anything, because nothing had been
/// asked to be.
///
/// A panel now picks a class and the grid gives it exactly that box. Content
/// fits the box; the box is never resized to fit the content. That single
/// inversion is the whole difference between a dashboard and a pile of cards.
enum PanelSpan {
  /// A single figure. Four across a full-width row.
  stat(cols: 3, rows: 1),

  /// A compact chart — a ring, a short bar list.
  small(cols: 4, rows: 2),

  /// The default panel: a chart with a legend, or a five-row list.
  medium(cols: 6, rows: 2),

  /// A chart that needs vertical room — a distribution, a tall bar list.
  tall(cols: 4, rows: 3),

  /// A table, or a chart with an axis.
  large(cols: 6, rows: 3),

  /// Full bleed: a week-long heatmap, a timeline.
  wide(cols: 12, rows: 2);

  const PanelSpan({required this.cols, required this.rows});

  final int cols;
  final int rows;
}

/// One cell of the console, already sized.
class ConsolePanel {
  final PanelSpan span;
  final Widget child;

  /// Panels are laid out in list order; this only breaks ties when a narrower
  /// window forces a reflow and something must drop below the fold. Lower
  /// sorts earlier. Left null, it follows list order.
  final int? priority;

  const ConsolePanel({
    required this.span,
    required this.child,
    this.priority,
  });
}

/// A 12-column grid with a fixed row unit.
///
/// WHY A ROW UNIT AND NOT `IntrinsicHeight`. Intrinsic sizing asks every child
/// how tall it wants to be and then makes the row that tall — which is exactly
/// the content-decides-the-box behaviour that produced the scatter, plus a
/// second layout pass over the whole subtree. A fixed unit means the geometry
/// is known before any child is measured: the page cannot shift as data
/// arrives, and a skeleton is trivially the same size as the real thing.
///
/// The unit is 78dp plus one gutter per extra row, so the classes come out at
/// 78 / 168 / 258 — close enough to a 1:2:3 rhythm to read as deliberate, and
/// tall enough that a `stat` row clears the 48dp touch target with padding to
/// spare.
class ConsoleGrid extends StatelessWidget {
  final List<ConsolePanel> panels;

  /// Stagger the panels in on first mount.
  ///
  /// ONE sequence per screen, per the motion law — the console is the screen
  /// that owns it, so nothing inside a panel should animate its own arrival on
  /// top of this. Reduced motion collapses the whole thing to zero through
  /// [AppMotion.staggerFor], which is also why the delay is read from the
  /// token rather than hand-picked.
  final bool animate;

  /// Below this the grid stops pretending to be twelve columns wide. Matches
  /// `Responsive.expandedBreakpoint` — a 12-column grid in a 700px window is
  /// twelve 58px columns, which is not a grid, it is a stripe pattern.
  static const double twelveColMin = 1024;
  static const double sixColMin = 640;

  static const double rowUnit = 78;
  static const double gutter = AppSpace.md;

  const ConsoleGrid({super.key, required this.panels, this.animate = true});

  /// How many columns this width gets. Kept static so tests and skeletons can
  /// ask the same question without building the widget.
  static int columnsFor(double width) {
    if (width >= twelveColMin) return 12;
    if (width >= sixColMin) return 6;
    return 3;
  }

  static double heightFor(PanelSpan span) =>
      span.rows * rowUnit + (span.rows - 1) * gutter;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final columns = columnsFor(box.maxWidth);
      final colWidth =
          (box.maxWidth - (columns - 1) * gutter) / columns;

      final ordered = [...panels];
      if (ordered.any((p) => p.priority != null)) {
        ordered.sort((a, b) =>
            (a.priority ?? 1 << 20).compareTo(b.priority ?? 1 << 20));
      }

      return Wrap(
        spacing: gutter,
        runSpacing: gutter,
        children: [
          for (var i = 0; i < ordered.length; i++)
            SizedBox(
              // A panel never exceeds the grid: a 12-wide panel in a 6-column
              // window becomes 6 wide rather than overflowing by a screen.
              width: _widthFor(ordered[i].span.cols, columns, colWidth),
              height: heightFor(ordered[i].span),
              // The box is sized OUTSIDE the reveal on purpose. If the
              // animation wrapped the SizedBox instead, a panel would occupy
              // no space until its turn came and the grid would reflow on
              // every frame of the entrance — the exact layout shift the
              // fixed row unit exists to prevent.
              child: animate
                  ? _PanelReveal(index: i, child: ordered[i].child)
                  : ordered[i].child,
            ),
        ],
      );
    });
  }

  static double _widthFor(int wanted, int columns, double colWidth) {
    final span = wanted.clamp(1, columns);
    return span * colWidth + (span - 1) * gutter;
  }
}

/// Fades and lifts one panel into place, once.
///
/// ONCE is the whole contract. The constitution allows motion on first mount
/// or explicit user action and forbids it on rebuild, and a console rebuilds
/// constantly — every resize, every theme change, every setState upstream. So
/// the controller lives in State and is fired exactly once from initState;
/// nothing in build can restart it.
class _PanelReveal extends StatefulWidget {
  final int index;
  final Widget child;
  const _PanelReveal({required this.index, required this.child});

  @override
  State<_PanelReveal> createState() => _PanelRevealState();
}

class _PanelRevealState extends State<_PanelReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: AppMotion.base);

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Deferred to here rather than initState because the stagger delay and the
    // reduced-motion answer both need a MediaQuery, which initState has no
    // safe access to.
    if (_started) return;
    _started = true;

    if (AppMotion.isReduced(context)) {
      _c.value = 1; // straight to the end state, no tween
      return;
    }
    final delay = AppMotion.staggerFor(context, widget.index);
    if (delay == Duration.zero) {
      _c.forward();
    } else {
      Future.delayed(delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _c, curve: AppMotion.standard);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        // A short rise, not a slide across the screen. 12dp reads as the panel
        // settling; anything further reads as a transition between pages.
        position: Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(curved),
        child: widget.child,
      ),
    );
  }
}

/// A panel built for a fixed box.
///
/// WHY NOT `WebPanel`. That one is a Column of [title, Padding(child)] inside a
/// shrink-wrapping Container — it sizes to its content, which is right for the
/// 52 screens already using it and exactly wrong here. Dropped into a grid cell
/// it hands its child unbounded height and overflows the moment the content is
/// a row taller than the box.
///
/// This one gives the child `Expanded`, so the content gets precisely the space
/// left after the header and a list inside it can scroll rather than overflow.
class GridPanel extends StatelessWidget {
  final String? title;
  final Widget child;
  final List<Widget> actions;
  final EdgeInsetsGeometry padding;

  const GridPanel({
    super.key,
    required this.child,
    this.title,
    this.actions = const [],
    this.padding = const EdgeInsets.fromLTRB(
        AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.md),
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.titleMedium.copyWith(
                        color: AppColors.textPrimaryOf(context),
                        fontWeight: FontWeight.w700)),
              ),
              ...actions,
            ]),
          ),
        Expanded(child: Padding(padding: padding, child: child)),
      ]),
    );
  }
}

/// A single figure, sized for a [PanelSpan.stat] box.
///
/// Every figure carries a NOTE, because a number with no reading makes the
/// reader do the work: "3" means nothing, "3 need a decision" is an
/// instruction. The note also carries the meaning that colour alone would
/// otherwise have to — an amber tile says nothing to someone who cannot see it
/// as amber.
class GridFigure extends StatelessWidget {
  final String label;
  final String value;
  final String note;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;

  const GridFigure({
    super.key,
    required this.label,
    required this.value,
    required this.note,
    required this.icon,
    required this.accent,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final body = GridPanel(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.md, vertical: AppSpace.sm),
      child: Row(children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.14),
            borderRadius: AppDepth.radius(1),
          ),
          child: Icon(icon, size: 18, color: accent),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          // scaleDown, because this panel's HEIGHT is fixed by the grid
          // (`heightFor(PanelSpan.stat)` = one 78px row) while the figure and
          // its note grow with the reader's text scale. The layout probe
          // caught the pair overflowing that row by 4px at a 1.3x scale on a
          // 320dp-wide window — a browser at phone width with the text turned
          // up, which is a real way to read the web console. Ellipsis does not
          // help a VERTICAL overflow; shrinking to fit does, and at the normal
          // scale it changes nothing.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.numericLarge.copyWith(
                        color: AppColors.textPrimaryOf(context),
                        fontWeight: FontWeight.w800)),
                Text(note,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.labelSmall
                        .copyWith(color: AppColors.textSecondaryOf(context))),
              ],
            ),
          ),
        ),
      ]),
    );

    return Semantics(
      label: '$label: $value, $note',
      button: onTap != null,
      child: onTap == null
          ? body
          : MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(onTap: onTap, child: body),
            ),
    );
  }
}
