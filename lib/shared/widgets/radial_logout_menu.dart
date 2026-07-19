import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/theme/app_colors.dart';
import '../../config/theme/app_icons.dart';
import '../../config/theme/liquid_glass_tokens.dart';
import 'glass_sheet.dart';

/// What the user picked in the leave menu. `null` (a dismiss) means "stay
/// signed in" — the safe default, so tapping the scrim can never sign anyone
/// out by accident.
enum LogoutChoice { switchAccount, lock, signOut }

/// The three leave options, in fan order (outermost-left → outermost-right).
const List<_LeaveOption> _kOptions = [
  _LeaveOption(LogoutChoice.switchAccount, 'Switch account', Icons.swap_horiz_rounded, AppColors.holoBlue),
  _LeaveOption(LogoutChoice.lock, 'Lock app', AppIcons.lockOutline, AppColors.holoTeal),
  _LeaveOption(LogoutChoice.signOut, 'Sign out', AppIcons.logout, AppColors.red),
];

class _LeaveOption {
  final LogoutChoice choice;
  final String label;
  final IconData icon;
  final Color color;
  const _LeaveOption(this.choice, this.label, this.icon, this.color);
}

// Fan geometry. The arc sweeps across the top half so options rise away from
// the tapped row rather than covering it.
const double _kRadius = 104;
const double _kArcStart = -166 * math.pi / 180; // up-and-left
const double _kArcEnd = -14 * math.pi / 180; // up-and-right
const double _kPillW = 148;
const double _kPillH = 46;
const double _kEdgePad = 10;

/// Shows the AFOS leave menu: the options **burst outward on an arc** from the
/// row that was tapped, each springing out along its own radius on a staggered
/// interval, then settling. Tapping the scrim (or Back) returns `null` =
/// stay signed in.
///
/// [context] must be the context of the tapped widget itself — its render box
/// supplies the arc's origin, so the fan visibly emanates from the row.
/// If there isn't enough room above the anchor for the arc (a short screen, or
/// a row near the top), this degrades to the standard glass bottom sheet with
/// the same options rather than clipping the fan.
Future<LogoutChoice?> showRadialLogoutMenu(BuildContext context) async {
  final box = context.findRenderObject();
  final media = MediaQuery.maybeOf(context);
  if (box is! RenderBox || !box.hasSize || media == null) {
    return _showFallbackSheet(context);
  }
  final origin = box.localToGlobal(box.size.center(Offset.zero));
  final screen = media.size;

  // Room needed above the origin for the arc plus a pill and the caption.
  final needAbove = _kRadius + _kPillH + 44 + media.padding.top;
  final fits = origin.dy >= needAbove &&
      screen.width >= _kPillW + 2 * _kEdgePad &&
      !media.accessibleNavigation; // a11y users get the linear, focusable list
  if (!fits) return _showFallbackSheet(context);

  HapticFeedback.mediumImpact();
  return showGeneralDialog<LogoutChoice>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Leave menu',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 460),
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, __, ___) =>
        _RadialFan(anim: anim, origin: origin, screen: screen, safeTop: media.padding.top),
  );
}

/// Carries out the chosen leave action. Shared by the slide menu and Settings
/// so both entry points behave identically — the two stock dialogs this
/// replaced had already drifted apart in wording and context handling.
///
/// A `null` choice (scrim tap / Back) is a deliberate no-op: dismissing must
/// never sign anyone out.
Future<void> applyLogoutChoice(BuildContext context, LogoutChoice? choice) async {
  if (choice == null) return;
  if (choice == LogoutChoice.lock) {
    // The session stays valid on purpose. `/auth/unlock` is explicitly exempt
    // from the router's "logged in ⇒ bounce away from /auth/*" redirect
    // (app_router.dart) precisely so it can gate an already-valid session.
    context.go('/auth/unlock');
    return;
  }
  // Switch-account and sign-out both end the session: AFOS keeps no
  // multi-account store, so switching *is* signing out and returning to login
  // — the separate label only tells the user why they're going there.
  // The stored biometric session is cleared by bootstrap.dart's
  // AuthChangeEvent.signedOut listener, so it must NOT be cleared again here.
  await Supabase.instance.client.auth.signOut();
  if (context.mounted) context.go('/auth/login');
}

/// Linear fallback for short screens / screen-reader users — same options,
/// same return value, no arc.
Future<LogoutChoice?> _showFallbackSheet(BuildContext context) => showGlassSheet<LogoutChoice>(
      context,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text('Leaving already?',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.textPrimaryOf(context), fontSize: 17, fontWeight: FontWeight.w700)),
        ),
        for (final o in _kOptions)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _OptionPill(option: o, onTap: () => Navigator.of(context).pop(o.choice)),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Stay signed in', style: TextStyle(color: AppColors.textSecondaryOf(context))),
        ),
      ]),
    );

/// The animated fan itself: a caption above the anchor, a soft glow at the
/// origin, and the option pills travelling out along their radii.
class _RadialFan extends StatelessWidget {
  final Animation<double> anim;
  final Offset origin;
  final Size screen;
  final double safeTop;
  const _RadialFan({required this.anim, required this.origin, required this.screen, required this.safeTop});

  /// Resting centre of option [i] — on the arc, then nudged inside the screen
  /// so an anchor near an edge still lands every pill fully on-screen.
  Offset _restingCenter(int i) {
    final t = _kOptions.length == 1 ? 0.5 : i / (_kOptions.length - 1);
    final angle = _kArcStart + (_kArcEnd - _kArcStart) * t;
    final raw = origin + Offset(math.cos(angle) * _kRadius, math.sin(angle) * _kRadius);
    return Offset(
      raw.dx.clamp(_kEdgePad + _kPillW / 2, screen.width - _kEdgePad - _kPillW / 2),
      raw.dy.clamp(safeTop + _kEdgePad + _kPillH / 2, screen.height - _kEdgePad - _kPillH / 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return AnimatedBuilder(
      animation: anim,
      builder: (context, _) {
        final children = <Widget>[];

        // Caption, fading in above the fan.
        final captionY = (origin.dy - _kRadius - 46).clamp(safeTop + 8, screen.height);
        children.add(Positioned(
          left: 0, right: 0, top: captionY,
          child: Opacity(
            opacity: const Interval(0.15, 0.6, curve: Curves.easeOut).transform(anim.value),
            child: const Text('Leaving already?',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
          ),
        ));

        for (var i = 0; i < _kOptions.length; i++) {
          final o = _kOptions[i];
          // Staggered ~60ms apart: each pill has its own slice of the timeline,
          // so they visibly burst one after another instead of together.
          final start = i * 0.13;
          final p = reduceMotion
              ? 1.0
              : Interval(start, (start + 0.68).clamp(0.0, 1.0), curve: Curves.easeOutBack).transform(anim.value);
          final fade = reduceMotion
              ? 1.0
              : Interval(start, (start + 0.3).clamp(0.0, 1.0), curve: Curves.easeOut).transform(anim.value);
          // Travel out from the origin along the radius as it appears.
          final c = Offset.lerp(origin, _restingCenter(i), p)!;
          children.add(Positioned(
            left: c.dx - _kPillW / 2,
            top: c.dy - _kPillH / 2,
            width: _kPillW,
            height: _kPillH,
            child: Opacity(
              opacity: fade.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: 0.5 + 0.5 * p.clamp(0.0, 1.5),
                child: _OptionPill(option: o, onTap: () => Navigator.of(context).pop(o.choice)),
              ),
            ),
          ));
        }

        return Stack(children: [
          // Full-bleed dismiss target — anywhere off a pill means "stay".
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          ...children,
        ]);
      },
    );
  }
}

/// One frosted option pill.
class _OptionPill extends StatelessWidget {
  final _LeaveOption option;
  final VoidCallback onTap;
  const _OptionPill({required this.option, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(LiquidGlass.radiusControl);
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: LiquidGlass.blurFloating, sigmaY: LiquidGlass.blurFloating),
        child: Material(
          color: Color.alphaBlend(
            option.color.withValues(alpha: 0.16),
            AppColors.surfaceOf(context).withValues(alpha: 0.86),
          ),
          child: InkWell(
            onTap: onTap,
            child: Container(
              height: _kPillH,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: option.color.withValues(alpha: 0.45)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(option.icon, size: 18, color: option.color),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    option.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: option.color, fontWeight: FontWeight.w700, fontSize: 13.5),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
