import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../config/theme/app_colors.dart';

class ShimmerCard extends StatelessWidget {
  final double width, height;
  final double radius;
  const ShimmerCard({super.key, this.width=double.infinity, this.height=80, this.radius=16});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.card,
      highlightColor: AppColors.border,
      child: Container(
        width: width, height: height,
        decoration: BoxDecoration(color:AppColors.card, borderRadius:BorderRadius.circular(radius)),
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
    return Column(children: List.generate(count, (i) =>
      Padding(padding:const EdgeInsets.only(bottom:12),
        child:ShimmerCard(height:itemHeight))));
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
