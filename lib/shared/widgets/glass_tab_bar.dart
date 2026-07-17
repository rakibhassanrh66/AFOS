import 'package:flutter/material.dart';
import '../../config/theme/app_colors.dart';
import '../../config/theme/liquid_glass_tokens.dart';

/// A single glass tab item.
class GlassTab {
  final String label;
  final IconData? icon;
  const GlassTab(this.label, {this.icon});
}

/// The app's standard floating pill tab-bar — a frosted glass track with a
/// SINGLE sliding "rolling" indicator that glides between segments (motion
/// tokens) instead of segments cross-fading their own fills. Detached from the
/// screen edges (via [margin]) with a fully-rounded track. Drive it from any
/// index source (e.g. a `TabController.index` + `animateTo`). Labels are
/// overflow-safe; icons stack over labels to stay readable at 3–4 tabs.
class GlassTabBar extends StatelessWidget {
  final List<GlassTab> tabs;
  final int currentIndex;
  final ValueChanged<int> onChanged;
  final EdgeInsetsGeometry margin;

  const GlassTabBar({
    super.key,
    required this.tabs,
    required this.currentIndex,
    required this.onChanged,
    this.margin = const EdgeInsets.symmetric(horizontal: 12),
  });

  @override
  Widget build(BuildContext context) {
    final n = tabs.length;
    return Padding(
      padding: margin,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.glassFill(context),
          borderRadius: BorderRadius.circular(LiquidGlass.radiusPill),
          border: Border.all(color: AppColors.glassBorder(context), width: 0.5),
        ),
        child: LayoutBuilder(
          builder: (context, c) {
            final segW = n == 0 ? 0.0 : c.maxWidth / n;
            final idx = currentIndex.clamp(0, n - 1);
            return Stack(
              children: [
                // The one rolling indicator — slides between segments.
                AnimatedPositioned(
                  duration: LiquidGlass.motionStandard,
                  curve: LiquidGlass.motionCurve,
                  left: idx * segW,
                  top: 0,
                  bottom: 0,
                  width: segW,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: AppColors.holoGradient,
                      borderRadius: BorderRadius.circular(LiquidGlass.radiusPill),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.holoTeal.withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (var i = 0; i < n; i++)
                      Expanded(child: _Segment(
                        tab: tabs[i],
                        selected: i == idx,
                        onTap: () => onChanged(i),
                      )),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final GlassTab tab;
  final bool selected;
  final VoidCallback onTap;
  const _Segment({required this.tab, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Text/icon colour cross-fades with the indicator slide so the passing
    // segment lights up as the pill arrives.
    final fg = selected ? Colors.white : AppColors.textSecondaryOf(context);
    final label = AnimatedDefaultTextStyle(
      duration: LiquidGlass.motionStandard,
      curve: LiquidGlass.motionCurve,
      style: TextStyle(
        color: fg,
        fontSize: 12,
        height: 1.0,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
      child: Text(
        tab.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        textHeightBehavior: const TextHeightBehavior(
            applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
      ),
    );
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
        child: tab.icon == null
            ? Center(child: label)
            : Column(mainAxisSize: MainAxisSize.min, children: [
                AnimatedScale(
                  duration: LiquidGlass.motionStandard,
                  curve: LiquidGlass.motionCurve,
                  scale: selected ? 1.05 : 1.0,
                  child: Icon(tab.icon, size: 16, color: fg),
                ),
                const SizedBox(height: 4),
                label,
              ]),
      ),
    );
  }
}
