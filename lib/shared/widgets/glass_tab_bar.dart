import '../../config/theme/depth.dart';
import 'package:flutter/material.dart';
import '../../config/theme/app_colors.dart';
import '../../config/theme/liquid_glass_tokens.dart';
import 'pressable.dart';

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
            // WHY THIS MEASURES INSTEAD OF JUST DIVIDING.
            //
            // It used to be `c.maxWidth / n` and nothing else, which silently
            // assumed every label fits whatever slice it gets. On a 320dp
            // phone with the five tabs Manage Users now shows, a slice is
            // ~46px of usable text width and "Pending (12)" needs 60px at the
            // DEFAULT text size — the layout probe measured it rendering
            // 12px of 60px, i.e. "P…". At a 2.0x accessibility scale it was
            // 24px of 264px. Every label on the bar, unreadable, and the
            // ellipsis made it look deliberate rather than broken.
            //
            // Four tabs failed too, so this predates the fifth; adding one
            // just made a bar that was already too tight impossible.
            //
            // So: measure what the widest label actually needs at the current
            // text scale, and if the tabs cannot all be read at once, let the
            // bar scroll horizontally instead of shredding every label.
            // Segments stay equal width either way, which is what keeps the
            // rolling indicator's arithmetic honest.
            final idx = currentIndex.clamp(0, n - 1);
            final scaler = MediaQuery.textScalerOf(context);
            var needed = 0.0;
            for (final t in tabs) {
              final tp = TextPainter(
                text: TextSpan(
                    text: t.label,
                    style: const TextStyle(fontSize: 12, height: 1.0)),
                maxLines: 1,
                textScaler: scaler,
                textDirection: Directionality.of(context),
              )..layout();
              if (tp.width > needed) needed = tp.width;
            }
            // +12 for the segment's own horizontal padding, and never below a
            // 48dp touch target.
            final minSegW = (needed + 12).clamp(48.0, double.infinity);
            final evenSegW = n == 0 ? 0.0 : c.maxWidth / n;
            final scrolls = evenSegW < minSegW;
            final segW = scrolls ? minSegW : evenSegW;

            final bar = SizedBox(
              width: scrolls ? segW * n : c.maxWidth,
              child: _track(context, segW, idx, n),
            );
            return scrolls
                ? SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    // The selected tab is usually the one you want in view.
                    physics: const ClampingScrollPhysics(),
                    child: bar,
                  )
                : bar;
          },
        ),
      ),
    );
  }

  Widget _track(BuildContext context, double segW, int idx, int n) {
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
                  child: Builder(builder: (context) {
                    // The user's chosen accent, not the fixed holoGradient
                    // signature -- this is literally "a selected tab", the
                    // doctrine's own named example of where the accent
                    // should show up and previously did not. Same in-family
                    // depth technique AfosButton uses, for one consistent
                    // look across every accent-driven surface.
                    final accent = AppColors.accentOf(context);
                    final deep = Color.lerp(accent, AppColors.background, 0.35)!;
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft, end: Alignment.bottomRight,
                          colors: [accent, deep],
                        ),
                        borderRadius: BorderRadius.circular(LiquidGlass.radiusPill),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: AppDepth.litOffset(3),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
                Row(
                  children: [
                    for (var i = 0; i < n; i++)
                      // A fixed width, not Expanded: when the bar scrolls, the
                      // Row sits inside an unbounded viewport where Expanded
                      // has nothing to divide up.
                      SizedBox(
                        width: segW,
                        child: _Segment(
                          tab: tabs[i],
                          selected: i == idx,
                          onTap: () => onChanged(i),
                        ),
                      ),
                  ],
                ),
              ],
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
    // segment lights up as the pill arrives. Luminance-checked against the
    // indicator's own fill, same as AfosButton -- a light accent (amber,
    // gold) under a flat white label would fail contrast the instant the
    // indicator stopped being a fixed dark-ish blue/teal gradient.
    final fg = selected
        ? AppColors.foregroundOn(AppColors.accentOf(context))
        : AppColors.textSecondaryOf(context);
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
    // A tab switch is the definition of "a discrete choice landed", so this one
    // keeps its haptic.
    return Pressable(
      onTap: onTap,
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
