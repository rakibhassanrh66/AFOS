import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../../../config/theme/spacing.dart';
import '../../../../core/utils/responsive.dart';

/// A list that becomes columns on a desktop browser, without giving up lazy
/// building.
///
/// THE PROBLEM IT SOLVES. Every list screen in this app is
/// `ListView.builder` + a card. At 1440px that is one card per row with most
/// of the line empty: a queue of thirty items reads as a ribbon, and the
/// reader scrolls three screens for something that fits on one. That is the
/// last remaining "phone app someone resized" symptom after the shell, the
/// header and the width were fixed.
///
/// WHY NOT A GRIDVIEW. `GridView` wants a fixed `childAspectRatio` or
/// `mainAxisExtent`, and these cards are not a fixed height — a Lost & Found
/// post with a photo and three claims is twice the height of one without. A
/// grid would either clip them or pad every card to the tallest.
///
/// WHY NOT A WRAP. `Wrap` lays out every child eagerly. The constitution bans
/// unbounded lists for a real reason: `list_section_students` can return a
/// whole department, and building 1,854 cards to show twelve is how a screen
/// takes four seconds to open.
///
/// WHAT IT DOES INSTEAD. Keeps `ListView.builder` and makes each **row** the
/// list item: with two columns, row `i` builds items `2i` and `2i+1`. Laziness
/// is preserved exactly — the ListView still only builds the rows near the
/// viewport — and variable heights are fine because a row is just a `Row` with
/// top-aligned children.
///
/// Below the desktop breakpoint, and on Android entirely, it is a plain
/// `ListView.builder` with the same arguments. `kIsWeb` is a compile-time
/// constant, so the column path is tree-shaken out of the APK.
class AdaptiveList extends StatelessWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final EdgeInsetsGeometry? padding;

  /// The narrowest a column may get before dropping to fewer columns. Cards
  /// carrying a title, two metadata lines and a button need roughly 420px
  /// before they start ellipsising things that matter.
  final double minColumnWidth;

  /// Hard ceiling on columns. Four columns of dense cards is a wall; three is
  /// the most that still reads as a list rather than a mosaic.
  final int maxColumns;

  final ScrollPhysics? physics;
  final bool shrinkWrap;
  final ScrollController? controller;

  /// Passed straight through in the single-column paths, where it does what it
  /// always did: lets the sliver measure one representative item instead of
  /// every item, which is why several of these screens scroll smoothly with
  /// thousands of rows.
  ///
  /// DELIBERATELY IGNORED in the multi-column path. There, the list item is a
  /// ROW of cards, so a single card is no longer a valid prototype for its
  /// height — using it would under-measure every row by a factor of the column
  /// count. Dropping it costs an extent estimate; keeping it would corrupt
  /// scroll geometry.
  final Widget? prototypeItem;

  const AdaptiveList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.padding,
    this.minColumnWidth = 420,
    this.maxColumns = 3,
    this.physics,
    this.shrinkWrap = false,
    this.controller,
    this.prototypeItem,
  });

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb || !Responsive.isExpanded(context)) {
      return ListView.builder(
        padding: padding,
        itemCount: itemCount,
        itemBuilder: itemBuilder,
        physics: physics,
        shrinkWrap: shrinkWrap,
        controller: controller,
        prototypeItem: prototypeItem,
      );
    }

    return LayoutBuilder(builder: (ctx, box) {
      final columns =
          (box.maxWidth ~/ minColumnWidth).clamp(1, maxColumns);
      if (columns == 1) {
        return ListView.builder(
          padding: padding,
          itemCount: itemCount,
          itemBuilder: itemBuilder,
          physics: physics,
          shrinkWrap: shrinkWrap,
          controller: controller,
          prototypeItem: prototypeItem,
        );
      }

      final rows = (itemCount + columns - 1) ~/ columns;
      return ListView.builder(
        padding: padding,
        itemCount: rows,
        physics: physics,
        shrinkWrap: shrinkWrap,
        controller: controller,
        itemBuilder: (rowCtx, row) {
          return Row(
            // Top-aligned, not stretched: a short card next to a tall one
            // should stay short rather than growing to match, which is what
            // makes this read as a list in columns rather than as a grid.
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var c = 0; c < columns; c++) ...[
                if (c > 0) const SizedBox(width: AppSpace.md),
                Expanded(
                  child: (row * columns + c) < itemCount
                      // The real item, built by the screen's own builder --
                      // this widget never knows or cares what a row looks like.
                      ? itemBuilder(rowCtx, row * columns + c)
                      // A blank cell keeps the last row's columns aligned with
                      // every row above it. Without it, three items in a
                      // two-column list would centre the orphan.
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          );
        },
      );
    });
  }
}
