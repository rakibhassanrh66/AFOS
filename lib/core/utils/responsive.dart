import 'package:flutter/material.dart';

/// Three-tier breakpoint system (compact/medium/expanded) matching Material
/// 3's window size classes -- every screen in this app was designed
/// mobile-first with no width limit anywhere, so a GlassCard/form/list that
/// looks right on a 390px phone stretches to fill a 1920px desktop window
/// edge-to-edge, leaving everything oversized and hollow-looking. This is
/// the shared vocabulary the rest of the responsive work builds on.
enum DeviceSize { compact, medium, expanded }

class Responsive {
  Responsive._();

  static const double mediumBreakpoint = 600;
  static const double expandedBreakpoint = 1024;

  static DeviceSize sizeOf(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= expandedBreakpoint) return DeviceSize.expanded;
    if (width >= mediumBreakpoint) return DeviceSize.medium;
    return DeviceSize.compact;
  }

  static bool isCompact(BuildContext context) => sizeOf(context) == DeviceSize.compact;
  static bool isMedium(BuildContext context) => sizeOf(context) == DeviceSize.medium;
  static bool isExpanded(BuildContext context) => sizeOf(context) == DeviceSize.expanded;
  static bool isDesktop(BuildContext context) => sizeOf(context) != DeviceSize.compact;
}

/// Letterboxes mobile-designed content to a sane max width on medium/
/// expanded screens instead of letting it stretch edge-to-edge, filling the
/// remaining space with the surrounding background so the app still reads
/// as intentional rather than "a phone app someone forgot to resize." Safe
/// to wrap around anything meant to be read top-to-bottom (forms, lists,
/// dashboards); screens that deliberately want a custom full-width desktop
/// layout (like the login split-panel) opt out by branching on
/// [Responsive.isExpanded] themselves instead of using this widget.
class AdaptiveContentWidth extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  const AdaptiveContentWidth({super.key, required this.child, this.maxWidth = 1100});

  @override
  Widget build(BuildContext context) {
    if (Responsive.isCompact(context)) return child;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
