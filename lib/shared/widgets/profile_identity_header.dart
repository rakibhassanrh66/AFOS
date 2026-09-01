import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../config/theme/app_colors.dart';
import '../../config/theme/app_text_styles.dart';
import '../../config/theme/motion.dart';
import '../../config/theme/spacing.dart';

/// Who you are, at the top of the slide menu — every role, one shape.
///
/// THE LAYOUT, and why it is this way round. The old header stacked a small
/// 52px avatar top-left with the name and chips beneath it, which left the
/// entire right half of a 300dp drawer empty and made the photo an
/// afterthought. The identity now reads as one block: the portrait on the
/// RIGHT at 84px, and the name, id and role sitting to its LEFT, centred
/// against it BOTH WAYS — vertically against the portrait, and horizontally
/// within their own half — so the two halves balance across the gap instead
/// of one dangling under the other or trailing off the left edge.
///
/// The portrait's vertical centring is only half this widget's doing: it
/// centres within the Row, but whether that Row is centred in the HEADER
/// depends on the caller's padding. See `_buildHeader` in slide_menu.dart,
/// which balances the drawer's collapse button against the bottom padding for
/// exactly this reason.
///
/// WHAT THE SECOND LINE SAYS IS ROLE-DEPENDENT, and deliberately so — a
/// student's department plus their semester, a teacher's department plus their
/// designation, an administrator's title on its own. Callers pass whichever
/// applies; anything blank is simply not drawn, because a chip with padding
/// and no text is a small blank blob parked beside someone's name (this
/// project has shipped that once already).
class ProfileIdentityHeader extends StatelessWidget {
  final String name;

  /// University/staff id. Optional — administrators frequently have none.
  final String? identifier;

  /// Department or faculty, e.g. 'CSE'. Null or blank draws nothing.
  final String? affiliation;

  /// The role-appropriate second label: 'Sem 8', 'Lecturer', 'Super Admin'.
  final String? roleLabel;

  final String? avatarUrl;
  final String initials;
  final bool isSuperAdmin;
  final VoidCallback? onTapAvatar;

  const ProfileIdentityHeader({
    super.key,
    required this.name,
    required this.initials,
    this.identifier,
    this.affiliation,
    this.roleLabel,
    this.avatarUrl,
    this.isSuperAdmin = false,
    this.onTapAvatar,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    final id = (identifier ?? '').trim();
    final dept = (affiliation ?? '').trim();
    final role = (roleLabel ?? '').trim();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          // CENTRED, not left-aligned. Ragged-left text hard against the
          // drawer's padding read as a caption that had drifted away from the
          // portrait; centring the block on its own half makes the two halves
          // balance across the gap, which is the whole point of putting the
          // portrait opposite it rather than under it.
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.titleLarge.copyWith(color: textPrimary)),
              if (id.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.monoSmall.copyWith(color: textSecondary)),
              ],
              if (dept.isNotEmpty || role.isNotEmpty) ...[
                const SizedBox(height: AppSpace.sm),
                // Wrap, not Row: "Exam Controller" beside a department is more
                // than a 300dp drawer's left column can hold on one line at a
                // large text scale, and a Row answers that by clipping.
                Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.xs,
                  alignment: WrapAlignment.center,
                  children: [
                    if (dept.isNotEmpty) _Chip(dept, AppColors.holoBlue),
                    if (role.isNotEmpty) _Chip(role, AppColors.green),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: AppSpace.md),
        GlowingAvatar(
          url: avatarUrl,
          initials: initials,
          isSuperAdmin: isSuperAdmin,
          onTap: onTapAvatar,
        ),
      ],
    );
  }
}

/// The portrait, with a light that travels around it and a slow parallax tilt.
///
/// HOW THIS OBEYS THE MOTION LAW. The constitution caps INTERACTION motion at
/// [AppMotion.hero] and forbids animating on rebuild — neither of which is
/// what this is. This is an ambient loop, the same category as `ShimmerCard`
/// (1400ms) and the exam band's `_Pulse`, and it follows their precedent: one
/// controller owned by the widget, started once on mount, never restarted by a
/// parent rebuilding.
///
/// It stops completely under reduced motion, where it renders as a plain ring
/// — not a slower version of itself. A person who has asked the OS for less
/// movement should get none, not less.
class GlowingAvatar extends StatefulWidget {
  final String? url;
  final String initials;
  final bool isSuperAdmin;
  final VoidCallback? onTap;
  final double size;

  const GlowingAvatar({
    super.key,
    required this.initials,
    this.url,
    this.isSuperAdmin = false,
    this.onTap,
    this.size = 84,
  });

  @override
  State<GlowingAvatar> createState() => _GlowingAvatarState();
}

class _GlowingAvatarState extends State<GlowingAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    // One unhurried revolution. Fast enough to read as alive, slow enough that
    // it never competes with the menu the drawer exists to show.
    duration: const Duration(milliseconds: 5200),
  );

  @override
  void initState() {
    super.initState();
    // Started in initState, once. Not in build, and not conditionally on data
    // arriving — the profile row loads a moment after the drawer opens, and
    // restarting the sweep at that point would read as a glitch.
    _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.isReduced(context);
    final accent =
        widget.isSuperAdmin ? AppColors.holoviolet : AppColors.holoBlue;
    final size = widget.size;

    final portrait = _Portrait(
      url: widget.url,
      initials: widget.initials,
      accent: accent,
      size: size,
    );

    if (reduced) {
      return _tappable(_StaticRing(accent: accent, size: size, child: portrait));
    }

    return _tappable(
      AnimatedBuilder(
        animation: _c,
        // The portrait is built ONCE and passed through: it holds a network
        // image, and rebuilding it 60 times a second to spin a ring around it
        // would be the expensive way to draw a cheap effect.
        child: portrait,
        builder: (context, child) {
          final t = _c.value;
          final angle = t * 2 * math.pi;
          // A slow figure-of-eight rather than a spin: the tilt reads as the
          // light moving around a solid object instead of the object itself
          // turning, which is what makes it read as depth and not as a
          // loading spinner.
          final tiltX = math.sin(angle) * 0.05;
          final tiltY = math.cos(angle) * 0.07;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              // Perspective, without which rotateX/rotateY are just a squash.
              ..setEntry(3, 2, 0.0016)
              ..rotateX(tiltX)
              ..rotateY(tiltY),
            child: CustomPaint(
              painter: _GlowRingPainter(
                progress: t,
                accent: accent,
                isDark: AppColors.isDark(context),
              ),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: child,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _tappable(Widget child) {
    if (widget.onTap == null) return child;
    return GestureDetector(
      onTap: widget.onTap,
      // The portrait is 84dp, comfortably past the 48dp floor, so the tap
      // target is the thing you can see.
      behavior: HitTestBehavior.opaque,
      child: child,
    );
  }
}

/// The travelling light. One sweep gradient arc, plus a soft outer bloom.
class _GlowRingPainter extends CustomPainter {
  final double progress;
  final Color accent;
  final bool isDark;

  const _GlowRingPainter({
    required this.progress,
    required this.accent,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = size.shortestSide / 2 - 2;
    final sweepStart = progress * 2 * math.pi;

    // The base ring: always visible, so the portrait keeps its edge even at
    // the darkest point of the sweep.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = accent.withValues(alpha: isDark ? 0.30 : 0.22),
    );

    // The travelling highlight. A SweepGradient rotated by `progress`, so the
    // bright head chases the ring rather than the ring rotating as a whole.
    final sweep = SweepGradient(
      startAngle: 0,
      endAngle: 2 * math.pi,
      transform: GradientRotation(sweepStart),
      colors: [
        accent.withValues(alpha: 0.0),
        accent.withValues(alpha: 0.0),
        accent.withValues(alpha: 0.85),
        Colors.white.withValues(alpha: isDark ? 0.9 : 0.6),
        accent.withValues(alpha: 0.85),
        accent.withValues(alpha: 0.0),
        accent.withValues(alpha: 0.0),
      ],
      stops: const [0.0, 0.55, 0.72, 0.78, 0.84, 0.95, 1.0],
    );

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..shader = sweep.createShader(rect)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
    );

    // The bloom the light throws outward. Drawn OUTSIDE the ring so it never
    // washes over the face.
    canvas.drawCircle(
      center,
      radius + 3,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..shader = sweep.createShader(rect)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
  }

  @override
  bool shouldRepaint(_GlowRingPainter old) =>
      old.progress != progress || old.accent != accent || old.isDark != isDark;
}

/// What reduced motion gets: the same ring, standing still.
class _StaticRing extends StatelessWidget {
  final Color accent;
  final double size;
  final Widget child;
  const _StaticRing(
      {required this.accent, required this.size, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: accent.withValues(alpha: 0.6), width: 2),
          boxShadow: [
            BoxShadow(
                color: accent.withValues(alpha: 0.25),
                blurRadius: 12,
                spreadRadius: -2),
          ],
        ),
        child: Padding(padding: const EdgeInsets.all(4), child: child),
      );
}

class _Portrait extends StatelessWidget {
  final String? url;
  final String initials;
  final Color accent;
  final double size;
  const _Portrait(
      {this.url, required this.initials, required this.accent, required this.size});

  @override
  Widget build(BuildContext context) {
    final has = (url ?? '').isNotEmpty;
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: has
            ? CachedNetworkImage(
                imageUrl: url!,
                fit: BoxFit.cover,
                // Decoded for the size it is DRAWN at, not the size it was
                // uploaded at: this is a ~84dp circle, and a full camera frame
                // behind it is megabytes of bitmap for nothing.
                memCacheWidth: 256,
                errorWidget: (_, __, ___) => _Initials(initials, accent),
              )
            : _Initials(initials, accent),
      ),
    );
  }
}

class _Initials extends StatelessWidget {
  final String initials;
  final Color accent;
  const _Initials(this.initials, this.accent);

  @override
  Widget build(BuildContext context) => Container(
        color: AppColors.surfaceOf(context),
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Text(initials,
                style: TextStyle(
                    color: accent, fontSize: 26, fontWeight: FontWeight.bold)),
          ),
        ),
      );
}

/// The department / role pill.
///
/// Solid ink on a tint, not the accent on a tint: a full-strength accent over
/// a near-neutral 0.15 tint of itself is low contrast almost by construction,
/// which this project has already had reported live once.
class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip(this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsetsDirectional.fromSTEB(10, 4, 10, 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.textPrimaryOf(context),
              fontWeight: FontWeight.w700,
              height: 1.0,
            ),
            textHeightBehavior: const TextHeightBehavior(
                applyHeightToFirstAscent: false, applyHeightToLastDescent: false)),
      );
}
