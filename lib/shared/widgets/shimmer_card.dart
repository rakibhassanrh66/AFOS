import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../config/theme/app_colors.dart';
import '../../config/theme/liquid_glass_tokens.dart';

class ShimmerCard extends StatelessWidget {
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
      period: const Duration(milliseconds: 1400),
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
