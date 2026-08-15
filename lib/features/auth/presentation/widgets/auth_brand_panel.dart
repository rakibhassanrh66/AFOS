import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../config/theme/app_text_styles.dart';
import '../../../../config/theme/depth.dart';
import '../../../../config/theme/liquid_glass_tokens.dart';
import '../../../../config/theme/motion.dart';

/// The left-hand branding panel shown next to the auth forms on medium/
/// expanded (tablet/desktop) widths -- on a phone-width screen the auth
/// screens stay exactly as they were (a single centered card), since that
/// already reads fine; this panel only exists to give the *other* half of a
/// wide browser window something intentional instead of empty space, and to
/// actually explain what AFOS is to someone who's never seen it before
/// signing in.
class AuthBrandPanel extends StatelessWidget {
  const AuthBrandPanel({super.key});

  // These four lines are the first thing anyone reads about AFOS, so each one
  // has to describe something the app actually does TODAY. The transport line
  // used to promise "Real-time bus routes and stop-to-stop timing" and neither
  // half was backed by data: `transport_live_status` has 0 rows (so the live
  // badge never renders at all) and `transport_stop_offsets` has 0 rows (so
  // the per-stop time is correctly reported as unknown on every stop).
  //
  // The machinery for both is built and honest -- StopTimeCalculator returns
  // null rather than pass a route-level time off as a stop time, and the admin
  // screen to record offsets exists. What is missing is data only the
  // transport office can give us. Until it arrives, the promise is the thing
  // that has to change, not the code: advertising a feature on the LOGIN
  // screen that reports "not known" the moment you reach it is worse than not
  // advertising it. Restore the original wording when the offsets are loaded.
  static const _features = [
    (Icons.schedule_rounded, 'Class routines & rooms', 'Live schedule, retakes, labs, and free-room finder'),
    (Icons.directions_bus_filled_rounded, 'Campus transport', 'Every route, stop and departure time, mapped'),
    (Icons.apartment_rounded, 'Hall & campus life', 'Hall applications, clubs, mentorship, and more'),
    (Icons.sos_rounded, 'One-tap SOS', 'Emergency alerts to nearby students and staff instantly'),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);
    final reduced = AppMotion.isReduced(context);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: isDark
            ? AppColors.authBrandDark
            : AppColors.authBrandLight,
        ),
      ),
      child: Stack(children: [
        // AMBIENT DRIFT, NOT A TRANSITION. 5.2s and 6.4s are far above the
        // 620ms ceiling and that is correct: the ceiling governs things moving
        // between states, where length reads as lag. These are two out-of-focus
        // glow blobs breathing behind the copy, and at 620ms they would read as
        // a warning light. The durations stay.
        //
        // What WAS broken is that they repeated forever regardless of reduced
        // motion — a perpetual animation is the worst offender for someone who
        // asked the system to stop moving things. Same call as _PulseDot in
        // batch 2: under reduced motion the blobs are simply painted at rest.
        Positioned(top: -80, right: -80, child: reduced
            ? _glowBlob(AppColors.holoBlue)
            : _glowBlob(AppColors.holoBlue)
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .moveY(begin: 0, end: 26, duration: 5200.ms, curve: AppMotion.inOut)
                .moveX(begin: 0, end: -18, duration: 5200.ms, curve: AppMotion.inOut)),
        Positioned(bottom: -100, left: -60, child: reduced
            ? _glowBlob(AppColors.teal)
            : _glowBlob(AppColors.teal)
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .moveY(begin: 0, end: -22, duration: 6400.ms, curve: AppMotion.inOut)
                .moveX(begin: 0, end: 20, duration: 6400.ms, curve: AppMotion.inOut)),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                // The panel's one orchestrated entrance. Delays are steps on
                // the 40ms grid via AppMotion.sequenceDelay; easeOutExpo (not
                // a token) is now AppMotion.standard.
                _SmartFrame()
                  .animate()
                  .fadeIn(duration: AppMotion.durationOf(context, AppMotion.slow), curve: AppMotion.standard)
                  .slideY(begin: -0.5, end: 0,
                      duration: AppMotion.durationOf(context, AppMotion.slow), curve: AppMotion.standard),
                const SizedBox(height: 32),
                Text('All Facilities,\nOne System',
                    style: AppTextStyles.displayLarge.copyWith(color: Colors.white, fontSize: 36, height: 1.08))
                  .animate(delay: AppMotion.sequenceDelay(context, 2))
                  .fadeIn(duration: AppMotion.durationOf(context, AppMotion.slow), curve: AppMotion.standard)
                  .slideX(begin: -0.6, end: 0,
                      duration: AppMotion.durationOf(context, AppMotion.slow), curve: AppMotion.standard),
                const SizedBox(height: 14),
                Text(
                  "Built for Daffodil International University — one login for "
                  "class routines, transport, hall life, mentorship, and help "
                  "the moment you need it.",
                  style: AppTextStyles.bodyLarge.copyWith(color: Colors.white.withValues(alpha: 0.72), height: 1.5),
                )
                  .animate(delay: AppMotion.sequenceDelay(context, 4))
                  .fadeIn(duration: AppMotion.durationOf(context, AppMotion.slow), curve: AppMotion.standard)
                  .slideX(begin: 0.6, end: 0,
                      duration: AppMotion.durationOf(context, AppMotion.slow), curve: AppMotion.standard),
                const SizedBox(height: 36),
                for (var i = 0; i < _features.length; i++)
                  Padding(
                    padding: EdgeInsets.only(bottom: i == _features.length - 1 ? 0 : 18),
                    child: _FeatureRow(icon: _features[i].$1, title: _features[i].$2, subtitle: _features[i].$3)
                      // Steps 6, 8, 10 … — the feature rows keep their
                      // alternating slide, two grid units apart.
                      .animate(delay: AppMotion.sequenceDelay(context, 6 + i * 2))
                      .fadeIn(duration: AppMotion.durationOf(context, AppMotion.base), curve: AppMotion.standard)
                      .slideX(begin: i.isEven ? -0.4 : 0.4, end: 0,
                          duration: AppMotion.durationOf(context, AppMotion.slow), curve: AppMotion.standard),
                  ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _glowBlob(Color color) => Container(
    width: 260, height: 260,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.18)),
  );
}

class _SmartFrame extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final frame = Container(
    width: 92, height: 92,
    padding: const EdgeInsets.all(1.4),
    decoration: BoxDecoration(
      borderRadius: AppDepth.radius(2),
      gradient: const LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [AppColors.holoBlue, AppColors.teal, AppColors.holoTeal],
      ),
      boxShadow: [BoxShadow(color: AppColors.holoBlue.withValues(alpha: 0.35), blurRadius: 22, spreadRadius: -4)],
    ),
    child: Container(
      decoration: BoxDecoration(
        color: AppColors.authDeep,
        // 21 = the 22px card rung minus the 1px gradient hairline this sits
        // inside, same construction as the payment fee tile.
        borderRadius: LiquidGlass.signatureRadius(LiquidGlass.radiusCard - 1),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(14),
      // The brand panel's logo sits in a fixed-size badge, so a 360px decode
      // covers it at any density this ships to — against a 1086px source that
      // otherwise costs ~5 MB of ARGB on the one screen every signed-out user
      // sees first.
      child: Image.asset('assets/images/diu_logo.png', fit: BoxFit.contain, cacheWidth: 360,
          errorBuilder: (_, __, ___) => const Icon(Icons.school_rounded, color: Colors.white, size: 40)),
    ),
    );
    // A third ambient loop, and it had the same defect as the two blobs: it
    // breathed forever with no regard for reduced motion. Under reduced motion
    // the frame is simply drawn at rest.
    if (AppMotion.isReduced(context)) return frame;
    return frame
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .scaleXY(begin: 1.0, end: 1.035, duration: 1900.ms, curve: AppMotion.inOut);
  }
}

class _FeatureRow extends StatefulWidget {
  final IconData icon;
  final String title, subtitle;
  const _FeatureRow({required this.icon, required this.title, required this.subtitle});
  @override State<_FeatureRow> createState() => _FeatureRowState();
}

class _FeatureRowState extends State<_FeatureRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() => _hover = false),
    child: AnimatedContainer(
      duration: AppMotion.durationOf(context, AppMotion.tight),
      curve: AppMotion.standard,
      padding: EdgeInsets.symmetric(horizontal: _hover ? 10 : 0, vertical: 6),
      transform: Matrix4.translationValues(_hover ? 6 : 0, 0, 0),
      decoration: BoxDecoration(
        borderRadius: AppDepth.radius(1),
        color: _hover ? Colors.white.withValues(alpha: 0.06) : Colors.transparent,
        border: Border.all(color: _hover ? Colors.white.withValues(alpha: 0.12) : Colors.transparent),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AnimatedContainer(
          duration: AppMotion.durationOf(context, AppMotion.tight),
          curve: AppMotion.standard,
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: _hover ? 0.18 : 0.1),
            borderRadius: AppDepth.radius(1),
            border: Border.all(color: Colors.white.withValues(alpha: _hover ? 0.3 : 0.14)),
          ),
          alignment: Alignment.center,
          child: Icon(widget.icon, color: Colors.white, size: 18),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.title, style: AppTextStyles.titleMedium.copyWith(color: Colors.white)),
          const SizedBox(height: 2),
          Text(widget.subtitle, style: AppTextStyles.bodyMedium.copyWith(color: Colors.white.withValues(alpha: 0.62))),
        ])),
      ]),
    ),
  );
}
