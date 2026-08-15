import '../../config/theme/motion.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../config/theme/app_colors.dart';
import '../../config/theme/liquid_glass_tokens.dart';

class ShimmerCard extends StatelessWidget {
  /// Height of one standard [InfoCard] list row — icon badge, title, one line
  /// of subtitle, trailing chevron.
  ///
  /// WHY THIS IS A NAMED NUMBER. The constitution requires a skeleton to match
  /// the final layout geometry EXACTLY, and until it was measured nobody knew
  /// whether it did. It did not: the default 80 sat between a 69px row (no or
  /// one-line subtitle) and a 108px one (two-line subtitle) and matched
  /// neither, so every row below the first moved when the data landed.
  ///
  /// 97 is measured, not chosen — `test/skeleton_layout_shift_test.dart`
  /// renders the real `InfoCard` and fails if this drifts from it. Use it
  /// wherever the loaded list renders `InfoCard`s.
  ///
  /// It is calibrated on a title that fits ONE line, which is the modal case.
  /// A wrapping title makes the real row ~136px, so those rows still move; a
  /// fixed-height skeleton cannot follow a variable-height row, and choosing
  /// the tall end instead would just make short rows jump upward.
  static const double infoCardRow = 97;

  final double width, height;
  final double radius;
  const ShimmerCard({super.key, this.width=double.infinity, this.height=80, this.radius=LiquidGlass.radiusCard});

  @override
  Widget build(BuildContext context) {
    // Glass-tinted skeleton: the shimmer sweep runs across a translucent
    // glass fill with the signature tinted hairline border, so a loading
    // placeholder reads as the same material as the card it stands in for.
    final base = Color.alphaBlend(AppColors.glassFill(context), AppColors.surfaceOf(context));
    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: AppColors.glassBorder(context),
      // A process indicator, not a transition, so 1400ms is correct and the
      // 620ms ceiling does not apply. But it swept forever regardless of
      // reduced motion — and a skeleton communicates "loading" by its GEOMETRY,
      // so freezing the sweep loses nothing. Effectively still under reduced
      // motion (Shimmer has no disable flag; a near-zero-delta period is the
      // supported way to still it).
      period: AppMotion.isReduced(context)
          ? const Duration(days: 1)
          : const Duration(milliseconds: 1400),
      child: Container(
        width: width, height: height,
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: AppColors.glassBorder(context), width: 0.5),
        ),
      ),
    );
  }
}

class ShimmerList extends StatelessWidget {
  final int count;
  final double itemHeight;
  const ShimmerList({super.key, this.count=4, this.itemHeight=80});

  @override
  Widget build(BuildContext context) {
    // A ListView (a clipping viewport) rather than a raw Column so this
    // placeholder can't throw a RenderFlex overflow when a parent bounds it
    // to less than count*(itemHeight+12) -- e.g. a TabBarView tab or an
    // Expanded slot on a short screen. shrinkWrap keeps it sizing to its
    // content in unbounded/scrollable parents; NeverScrollable keeps it from
    // stealing scroll gestures. Under-tight constraints it simply clips the
    // extra shimmer rows instead of painting the yellow/black overflow stripe.
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      children: List.generate(count, (i) =>
        Padding(padding:const EdgeInsets.only(bottom:12),
          child:ShimmerCard(height:itemHeight))),
    );
  }
}

class ShimmerGrid extends StatelessWidget {
  final int count;
  final double itemHeight;
  const ShimmerGrid({super.key, this.count=6, this.itemHeight=160});

  @override
  Widget build(BuildContext context) {
    return GridView.count(crossAxisCount:2, shrinkWrap:true, physics:const NeverScrollableScrollPhysics(),
      crossAxisSpacing:12, mainAxisSpacing:12, childAspectRatio:1,
      children: List.generate(count, (_) => ShimmerCard(height:itemHeight)));
  }
}
