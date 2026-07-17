import 'package:flutter/material.dart';
import '../../config/theme/app_colors.dart';
import '../../config/theme/liquid_glass_tokens.dart';

/// A single glass tab item.
class GlassTab {
  final String label;
  final IconData? icon;
  const GlassTab(this.label, {this.icon});
}

/// The app's standard pill tab-bar — one component replacing the ~12
/// hand-rolled `TabController` + `AnimatedBuilder` + custom pill `Row`s
/// (`_ScheduleTabPill`, and the transport/hall/library/payment/vr_id/…
/// header pill rows). Drive it from any index source (including a
/// `TabController.index` + `animateTo`). Selected pill is glossy-filled;
/// labels are overflow-safe.
///
/// Wrapped in a glass "track" so the whole control reads as one frosted
/// segmented control.
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
    this.margin = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.glassFill(context),
          borderRadius: BorderRadius.circular(LiquidGlass.radiusPill),
          border: Border.all(color: AppColors.glassBorder(context), width: 0.5),
        ),
        child: Row(
          children: [
            for (var i = 0; i < tabs.length; i++)
              Expanded(child: _Segment(
                tab: tabs[i],
                selected: i == currentIndex,
                onTap: () => onChanged(i),
              )),
          ],
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
    final fg = selected ? Colors.white : AppColors.textSecondaryOf(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          gradient: selected ? AppColors.holoGradient : null,
          borderRadius: BorderRadius.circular(LiquidGlass.radiusPill),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.holoTeal.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (tab.icon != null) ...[
              Icon(tab.icon, size: 16, color: fg),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                tab.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                textHeightBehavior: const TextHeightBehavior(
                    applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
                style: TextStyle(
                  color: fg,
                  fontSize: 12.5,
                  height: 1.0,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
