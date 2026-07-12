import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../config/theme/app_text_styles.dart';

/// The left-hand branding panel shown next to the auth forms on medium/
/// expanded (tablet/desktop) widths -- on a phone-width screen the auth
/// screens stay exactly as they were (a single centered card), since that
/// already reads fine; this panel only exists to give the *other* half of a
/// wide browser window something intentional instead of empty space, and to
/// actually explain what AFOS is to someone who's never seen it before
/// signing in.
class AuthBrandPanel extends StatelessWidget {
  const AuthBrandPanel({super.key});

  static const _features = [
    (Icons.schedule_rounded, 'Class routines & rooms', 'Live schedule, retakes, labs, and free-room finder'),
    (Icons.directions_bus_filled_rounded, 'Campus transport', 'Real-time bus routes and stop-to-stop timing'),
    (Icons.apartment_rounded, 'Hall & campus life', 'Hall applications, clubs, mentorship, and more'),
    (Icons.sos_rounded, 'One-tap SOS', 'Emergency alerts to nearby students and staff instantly'),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: isDark
            ? const [Color(0xFF0B1220), Color(0xFF16233D), Color(0xFF0F1B30)]
            : const [Color(0xFF0F1B30), Color(0xFF1B2E52), Color(0xFF16233D)],
        ),
      ),
      child: Stack(children: [
        Positioned(top: -80, right: -80, child: _glowBlob(AppColors.holoBlue)
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .moveY(begin: 0, end: 26, duration: 5200.ms, curve: Curves.easeInOutSine)
            .moveX(begin: 0, end: -18, duration: 5200.ms, curve: Curves.easeInOutSine)),
        Positioned(bottom: -100, left: -60, child: _glowBlob(AppColors.holoviolet)
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .moveY(begin: 0, end: -22, duration: 6400.ms, curve: Curves.easeInOutSine)
            .moveX(begin: 0, end: 20, duration: 6400.ms, curve: Curves.easeInOutSine)),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                _SmartFrame()
                  .animate().fadeIn(duration: 380.ms, curve: Curves.easeOutExpo)
                  .slideY(begin: -0.5, end: 0, duration: 420.ms, curve: Curves.easeOutExpo),
                const SizedBox(height: 32),
                Text('All Facilities,\nOne System',
                    style: AppTextStyles.displayLarge.copyWith(color: Colors.white, fontSize: 36, height: 1.08))
                  .animate(delay: 90.ms).fadeIn(duration: 380.ms, curve: Curves.easeOutExpo)
                  .slideX(begin: -0.6, end: 0, duration: 420.ms, curve: Curves.easeOutExpo),
                const SizedBox(height: 14),
                Text(
                  "Built for Daffodil International University — one login for "
                  "class routines, transport, hall life, mentorship, and help "
                  "the moment you need it.",
                  style: AppTextStyles.bodyLarge.copyWith(color: Colors.white.withValues(alpha: 0.72), height: 1.5),
                )
                  .animate(delay: 170.ms).fadeIn(duration: 380.ms, curve: Curves.easeOutExpo)
                  .slideX(begin: 0.6, end: 0, duration: 420.ms, curve: Curves.easeOutExpo),
                const SizedBox(height: 36),
                for (var i = 0; i < _features.length; i++)
                  Padding(
                    padding: EdgeInsets.only(bottom: i == _features.length - 1 ? 0 : 18),
                    child: _FeatureRow(icon: _features[i].$1, title: _features[i].$2, subtitle: _features[i].$3)
                      .animate(delay: (260 + i * 100).ms).fadeIn(duration: 340.ms, curve: Curves.easeOutExpo)
                      .slideX(begin: i.isEven ? -0.4 : 0.4, end: 0, duration: 380.ms, curve: Curves.easeOutExpo),
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
  Widget build(BuildContext context) => Container(
    width: 92, height: 92,
    padding: const EdgeInsets.all(1.4),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(22),
      gradient: const LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [AppColors.holoBlue, AppColors.holoviolet, AppColors.holoTeal],
      ),
      boxShadow: [BoxShadow(color: AppColors.holoBlue.withValues(alpha: 0.35), blurRadius: 22, spreadRadius: -4)],
    ),
    child: Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0B1220),
        borderRadius: BorderRadius.circular(21),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(14),
      child: Image.asset('assets/images/diu_logo.png', fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Icon(Icons.school_rounded, color: Colors.white, size: 40)),
    ),
  ).animate(onPlay: (c) => c.repeat(reverse: true))
    .scaleXY(begin: 1.0, end: 1.035, duration: 1900.ms, curve: Curves.easeInOutSine);
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
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.symmetric(horizontal: _hover ? 10 : 0, vertical: 6),
      transform: Matrix4.translationValues(_hover ? 6 : 0, 0, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: _hover ? Colors.white.withValues(alpha: 0.06) : Colors.transparent,
        border: Border.all(color: _hover ? Colors.white.withValues(alpha: 0.12) : Colors.transparent),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: _hover ? 0.18 : 0.1),
            borderRadius: BorderRadius.circular(11),
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
