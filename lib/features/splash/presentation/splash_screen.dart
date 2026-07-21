import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../config/app_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/liquid_glass_tokens.dart';
import '../../../core/auth/biometric_lock.dart';
import '../../../core/utils/last_route.dart';

/// Splash motion concept: a clock-style sweep reveals the wordmark
/// right-to-left (a rotating clock hand wiping the dial open), then the whole
/// splash content bursts outward (scales UP + fades — a Netflix-style pop-out)
/// as it hands off to the app.
/// Routing is unchanged: session → last route, else login.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _particleCtrl; // ambient drifting dots
  late AnimationController _glowCtrl;      // holo glow pulse
  late AnimationController _handCtrl;      // continuous clock hand sweep
  late AnimationController _introCtrl;     // dramatic letter-by-letter logo punch-in
  late AnimationController _revealCtrl;    // one-shot right-to-left wipe reveal
  late AnimationController _exitCtrl;      // zoom-out on hand-off
  final List<_Particle> _particles = [];
  bool _showTagline = false, _showSub = false;

  @override
  void initState() {
    super.initState();
    _particleCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat();
    _glowCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat(reverse: true);
    _handCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
    _introCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));
    _revealCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
    _exitCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 820));
    final rng = Random();
    for (int i = 0; i < 60; i++) {
      _particles.add(_Particle(
        x: rng.nextDouble(), y: rng.nextDouble(),
        r: rng.nextDouble() * 2 + 0.5,
        dx: (rng.nextDouble() - 0.5) * 0.001,
        dy: (rng.nextDouble() - 0.5) * 0.001,
        opacity: rng.nextDouble() * 0.5 + 0.1,
      ));
    }
    _run();
  }

  Future<void> _run() async {
    // The AFOS logo punches in first (letter-by-letter spring pop), then the
    // clock sweeps the wordmark open right-to-left.
    _introCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    _revealCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 900));
    if (mounted) setState(() => _showTagline = true);
    await Future.delayed(const Duration(milliseconds: 450));
    if (mounted) setState(() => _showSub = true);
    await Future.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;

    // Resolve the destination first, then zoom the splash out and hand off.
    final session = Supabase.instance.client.auth.currentSession;
    String target;
    if (!kIsWeb && await BiometricTokenStore.isEnabled()) {
      // Biometric quick-login is set up on this device — gate behind the
      // Unlock screen (the session is usually already auto-restored; Unlock
      // recovers it from secure storage otherwise).
      target = '/auth/unlock';
    } else {
      target = session == null ? '/auth/login' : (await loadLastRoute() ?? '/home');
    }
    if (!mounted) return;
    if (!MediaQuery.of(context).disableAnimations) {
      await _exitCtrl.forward();
    }
    if (!mounted) return;
    context.go(target);
  }

  @override
  void dispose() {
    _particleCtrl.dispose();
    _glowCtrl.dispose();
    _handCtrl.dispose();
    _introCtrl.dispose();
    _revealCtrl.dispose();
    _exitCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(children: [
        const _AmbientWash(),
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _particleCtrl,
            builder: (_, __) => CustomPaint(
                painter: _ParticlePainter(_particles, _particleCtrl.value), size: Size.infinite),
          ),
        ),
        // Everything below zooms out together on hand-off.
        Center(
          child: AnimatedBuilder(
            animation: _exitCtrl,
            builder: (_, child) {
              // Camera-punch hand-off: easeInBack dips below 1.0 first (a
              // physical wind-up), then the whole lockup flies AT the viewer to
              // ~5.5x while rotating a few degrees, so it reads as a violent
              // burst past the camera rather than a polite scale-up. The fade
              // is held off until the punch is well underway, and a white flash
              // fires at the very end to blow out into the next screen.
              final t = _exitCtrl.value;
              final punch = Curves.easeInBack.transform(t);
              final scale = 1.0 + 4.5 * punch;
              final spin = 0.06 * punch; // radians — a slight barrel roll
              final fade = const Interval(0.55, 1.0, curve: Curves.easeIn).transform(t);
              return Opacity(
                opacity: (1 - fade).clamp(0.0, 1.0),
                child: Transform.rotate(
                  angle: spin,
                  child: Transform.scale(scale: scale, child: child),
                ),
              );
            },
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Clock-style loader: a dial + sweeping hand behind the logo mark.
              SizedBox(
                width: 200, height: 200,
                child: Stack(alignment: Alignment.center, children: [
                  AnimatedBuilder(
                    animation: Listenable.merge([_handCtrl, _glowCtrl]),
                    builder: (_, __) => CustomPaint(
                      size: const Size(200, 200),
                      painter: _ClockSweepPainter(t: _handCtrl.value, glow: _glowCtrl.value),
                    ),
                  ),
                  // The AFOS monogram punches in letter-by-letter — a dramatic
                  // spring pop toward the viewer, tinted with the brand duo.
                  AnimatedBuilder(
                    animation: _introCtrl,
                    builder: (_, __) => ShaderMask(
                      shaderCallback: (r) => AppColors.holoGradient.createShader(r),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        for (var i = 0; i < 4; i++) _monoLetter('AFOS'[i], i),
                      ]),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 28),
              // Wordmark revealed right-to-left by the clock wipe.
              AnimatedBuilder(
                animation: _revealCtrl,
                builder: (_, __) => ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (rect) => _wipeShader(rect, _revealCtrl.value),
                  child: ShaderMask(
                    shaderCallback: (rect) => AppColors.holoGradient.createShader(rect),
                    child: const Text('All Facilities One System',
                        style: TextStyle(color: Colors.white, fontSize: 22, letterSpacing: 1.8, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              AnimatedOpacity(
                opacity: _showTagline ? 1 : 0, duration: LiquidGlass.motionStandard, curve: LiquidGlass.motionCurve,
                child: const Text('Daffodil International University',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ),
              const SizedBox(height: 22),
              AnimatedOpacity(
                opacity: _showSub ? 1 : 0, duration: LiquidGlass.motionStandard, curve: LiquidGlass.motionCurve,
                child: Text('AFOS v${AppConfig.appVersion}',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontFamily: 'monospace', letterSpacing: 1)),
              ),
            ]),
          ),
        ),
        // Blow-out flash at the very end of the punch, so the hand-off to the
        // next screen lands hard instead of politely cross-fading. Deliberately
        // ONE brief brand-tinted flash capped below full white — a repeated or
        // pure-white strobe is a photosensitivity hazard — and skipped entirely
        // when the user has asked for reduced motion.
        if (!MediaQuery.of(context).disableAnimations)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _exitCtrl,
                builder: (_, __) {
                  // Rise THEN fall, finishing at zero.
                  //
                  // This used to be a single 0.74->1.0 ramp, so the flash was at
                  // its brightest exactly when the controller ended — and
                  // `await _exitCtrl.forward()` is immediately followed by
                  // `context.go(target)`. The final splash frame was therefore a
                  // 70%-opaque near-white sheet, left on screen for however long
                  // the next route took to build its first frame: the "last frame
                  // sticks and goes white".
                  //
                  // Peaking at 0.88 and falling back to 0 by 1.0 keeps the punch
                  // but guarantees the last frame handed over is clean.
                  final v = _exitCtrl.value;
                  final up = const Interval(0.74, 0.88, curve: Curves.easeIn).transform(v);
                  final down = const Interval(0.88, 1.0, curve: Curves.easeOut).transform(v);
                  final f = (up - down).clamp(0.0, 1.0);
                  return Opacity(
                    opacity: (f * 0.7).clamp(0.0, 1.0),
                    child: const ColoredBox(color: Color(0xFFEAFFF6)),
                  );
                },
              ),
            ),
          ),
      ]),
    );
  }

  /// One monogram letter, popped in with a staggered elastic spring so the
  /// word "AFOS" bursts toward the viewer letter-by-letter at launch.
  Widget _monoLetter(String ch, int i) {
    final v = _introCtrl.value;
    // Tighter stagger (0.09) so the four letters land as one hard burst rather
    // than a leisurely one-by-one drift.
    final start = i * 0.09;
    final pop = Interval(start, (start + 0.55).clamp(0.0, 1.0), curve: Curves.elasticOut).transform(v);
    final op = Interval(start, (start + 0.18).clamp(0.0, 1.0), curve: Curves.easeOut).transform(v);
    return Opacity(
      opacity: op.clamp(0.0, 1.0),
      child: Transform.scale(
        scale: 0.3 + 0.7 * pop,
        child: Text(ch, style: const TextStyle(
            color: Colors.white, fontSize: 56, fontWeight: FontWeight.w900, letterSpacing: 1, height: 1.0)),
      ),
    );
  }

  /// A right-to-left wipe: fully opaque up to the reveal front, feathered edge,
  /// transparent beyond. `p` in 0..1 drives the front from the right edge to
  /// the left.
  Shader _wipeShader(Rect rect, double p) {
    final front = 1.0 - p; // 1 → 0 (right → left)
    return LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: const [Colors.white, Colors.white, Colors.transparent],
      stops: [0.0, (front - 0.12).clamp(0.0, 1.0), front.clamp(0.0, 1.0)],
    ).createShader(rect);
  }
}

class _AmbientWash extends StatelessWidget {
  const _AmbientWash();
  @override
  Widget build(BuildContext context) => const IgnorePointer(
    child: Stack(fit: StackFit.expand, children: [
      DecoratedBox(decoration: BoxDecoration(gradient: RadialGradient(
        center: Alignment(-0.8, -0.8), radius: 1.1,
        colors: [Color(0x1A3ECF8E), Color(0x003ECF8E)]))),
      DecoratedBox(decoration: BoxDecoration(gradient: RadialGradient(
        center: Alignment(0.9, 0.9), radius: 1.2,
        colors: [Color(0x1A5AB8FF), Color(0x005AB8FF)]))),
    ]),
  );
}

class _Particle {
  double x, y, r, dx, dy, opacity;
  _Particle({required this.x, required this.y, required this.r, required this.dx, required this.dy, required this.opacity});
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double tick;
  _ParticlePainter(this.particles, this.tick);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final p in particles) {
      p.x = (p.x + p.dx) % 1.0;
      p.y = (p.y + p.dy) % 1.0;
      paint.color = AppColors.blueLight.withValues(alpha: p.opacity);
      canvas.drawCircle(Offset(p.x * size.width, p.y * size.height), p.r, paint);
    }
  }
  @override bool shouldRepaint(_) => true;
}

/// A clock dial with tick marks, an orbit ring, and a sweeping hand that
/// leaves a fading radar-style trail — the "clock-style loading animation".
class _ClockSweepPainter extends CustomPainter {
  final double t;    // 0..1 hand rotation
  final double glow; // 0..1 pulse
  _ClockSweepPainter({required this.t, required this.glow});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 2;
    final angle = t * 2 * pi - pi / 2; // start at 12 o'clock

    // Outer ring.
    canvas.drawCircle(c, radius, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = AppColors.holoBlue.withValues(alpha: 0.35 + glow * 0.25));

    // 12 tick marks.
    final tickPaint = Paint()..strokeCap = StrokeCap.round;
    for (int i = 0; i < 12; i++) {
      final a = i * pi / 6 - pi / 2;
      final major = i % 3 == 0;
      tickPaint
        ..strokeWidth = major ? 2.2 : 1.2
        ..color = AppColors.holoTeal.withValues(alpha: major ? 0.6 : 0.3);
      final r1 = radius - (major ? 10 : 6);
      canvas.drawLine(
        c + Offset(cos(a), sin(a)) * r1,
        c + Offset(cos(a), sin(a)) * (radius - 2),
        tickPaint,
      );
    }

    // Sweeping trail (a fading arc behind the hand).
    const trail = 1.1; // radians of trailing glow
    final rect = Rect.fromCircle(center: c, radius: radius - 4);
    canvas.drawArc(
      rect, angle - trail, trail, false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: angle - trail,
          endAngle: angle,
          colors: [AppColors.holoBlue.withValues(alpha: 0), AppColors.holoBlue.withValues(alpha: 0.8)],
          transform: const GradientRotation(0),
        ).createShader(rect),
    );

    // The hand.
    canvas.drawLine(
      c,
      c + Offset(cos(angle), sin(angle)) * (radius - 6),
      Paint()
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..color = AppColors.holoTeal,
    );
    // Glowing hub.
    canvas.drawCircle(c, 4 + glow * 1.5, Paint()
      ..color = AppColors.green.withValues(alpha: 0.9)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
  }

  @override
  bool shouldRepaint(covariant _ClockSweepPainter old) => old.t != t || old.glow != glow;
}
