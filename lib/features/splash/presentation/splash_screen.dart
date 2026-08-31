import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../config/app_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/depth.dart';
import '../../../config/theme/liquid_glass_tokens.dart';
import '../../../config/theme/motion.dart';
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
    // Three ambient loops. The durations are correct — these are atmosphere,
    // not transitions, so the 620ms ceiling does not govern them. They are
    // started in _run() only when motion is allowed, rather than unconditionally
    // here: perpetual animation is the single worst thing to inflict on someone
    // who asked the system to stop moving things.
    _particleCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 10));
    _glowCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 3));
    _handCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
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
    // Resolve where we are going STRAIGHT AWAY, in parallel with the arc below
    // — not after it. Previously the session check, the biometric lookup and
    // the last-route read all ran only once the ~1.85s of `Future.delayed` had
    // finished, so their latency was ADDED to the splash rather than hidden by
    // it. The doctrine's rule for this screen is "total blocking time = 0": the
    // animation should be covering real work, and if the work outlasts the
    // animation we should be waiting on the work, not on padding.
    _destination = _resolveDestination();
  }

  /// Where to go once the arc finishes. Started in [initState] and awaited at
  /// the end of [_run], so it costs nothing unless it is slower than the
  /// animation.
  late final Future<String> _destination;

  bool _runStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // _run() reads MediaQuery (via AppMotion.isReduced), which throws if
    // touched from initState — dependOnInheritedElement() is only legal once
    // the element has actually mounted. didChangeDependencies is the
    // framework's designated place for that; it still fires before the first
    // frame, so nothing here is delayed relative to before. Guarded because
    // didChangeDependencies can fire more than once (e.g. system theme
    // change) and _run() must only ever start the arc a single time.
    if (!_runStarted) {
      _runStarted = true;
      _run();
    }
  }

  Future<String> _resolveDestination() async {
    final session = Supabase.instance.client.auth.currentSession;

    // TIMED, NEVER UNBOUNDED. This is exactly the shape that once froze the
    // app permanently at splash (flutter_secure_storage stripped by R8) --
    // and confirmed live on a device with no lock-screen PIN set: Android's
    // Keystore-backed EncryptedSharedPreferences can hang indefinitely
    // reading a value that was never even written, rather than returning
    // null quickly, on at least one real OEM build. One slow secure-storage
    // read must never be able to take the whole launch down with it again --
    // if it doesn't answer promptly, treat quick-login as "not set up" and
    // let the user sign in normally, which is a full recovery, not a failure.
    //
    // 3s TIGHTENED TO 1.5s -- reported live as "stuck sometimes". _destination
    // starts in initState, in parallel with the ~1.85s visual arc, so a slow
    // path hitting the OLD 3s ceiling meant up to (3 - 1.85) ≈ 1.15s of dead
    // air AFTER the reveal had already finished and nothing new was left to
    // show -- ambient motion (particles, the clock hand) never stops, but
    // that alone does not read as "still loading" once the wordmark is fully
    // revealed and the tagline is showing. 1.5s keeps the same safety net for
    // a genuinely hung read while landing close to where the visual arc ends
    // anyway on the slow path, instead of stalling well past it.
    bool biometricEnabled = false;
    if (!kIsWeb) {
      try {
        biometricEnabled = await BiometricTokenStore.isEnabled()
            .timeout(const Duration(milliseconds: 1500), onTimeout: () => false);
      } catch (_) {
        biometricEnabled = false;
      }
    }
    if (biometricEnabled) {
      // Biometric quick-login is set up on this device — gate behind the
      // Unlock screen (the session is usually already auto-restored; Unlock
      // recovers it from secure storage otherwise).
      return '/auth/unlock';
    }
    if (session == null) return '/auth/login';
    String? last;
    try {
      last = await loadLastRoute().timeout(const Duration(milliseconds: 1500), onTimeout: () => null);
    } catch (_) {
      last = null;
    }
    return last ?? '/home';
  }

  Future<void> _run() async {
    // The AFOS logo punches in first (letter-by-letter spring pop), then the
    // clock sweeps the wordmark open right-to-left.
    //
    // The four waits below used to total 3350ms (600+900+450+1400) PLUS the
    // 820ms exit animation — a mandatory ~4.2s on EVERY launch, no matter how
    // fast the backend responded, which is exactly what "the whole app still
    // takes time to load" was reporting. The last 1400ms in particular held
    // on a fully-static, already-fully-revealed screen — pure idle padding,
    // nothing left animating. Trimmed to ~1.85s total (still enough for the
    // pop-in and wipe-reveal to read cleanly) without touching the animation
    // controllers' own durations, so the motion itself is unchanged, only
    // how long it's held on screen before handing off.
    // REDUCED MOTION SKIPS THE WHOLE ARC, not just the exit. Only the exit
    // animation used to be guarded, so a user who had asked the system to stop
    // moving things still sat through 1.85s of choreography they could not
    // turn off — on the very first screen of the app.
    if (!mounted) return;
    if (AppMotion.isReduced(context)) {
      final target = await _destination;
      if (!mounted) return;
      context.go(target);
      return;
    }

    _particleCtrl.repeat();
    _glowCtrl.repeat(reverse: true);
    _handCtrl.repeat();
    _introCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    _revealCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 700));
    if (mounted) setState(() => _showTagline = true);
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) setState(() => _showSub = true);
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;

    // Already in flight since initState — this awaits only whatever is LEFT of
    // it, which on a warm start is nothing.
    final target = await _destination;
    if (!mounted) return;
    await _exitCtrl.forward();
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
                  // The machined bezel the dial sits in — Law 2 and Law 6 in
                  // one object: the app's single signature surface, and the
                  // only place the metal ramp is spent.
                  //
                  // It is a real specular, not a gradient pretending to be one:
                  // AppDepth.metal places the highlight in a 4% band at stops
                  // 42/46 running top-left to bottom-right, and casts its
                  // shadow along the SAME light. Before this, the splash had no
                  // lit surface at all — which is why the lockup read as flat
                  // artwork on a dark rectangle rather than as an object.
                  // RepaintBoundary here and on the two AnimatedBuilders below:
                  // three independently-animating layers were sharing one
                  // render region with no isolation between them, so every
                  // frame of the clock hand's own 1600ms loop forced the
                  // static bezel and the (ShaderMask-heavy, saveLayer-costing)
                  // monogram to be recomposited too, and vice versa. This is
                  // the single biggest lever for keeping the busiest 1.3s of
                  // the splash (bezel + sweep + monogram all animating at
                  // once) cheap on weaker GPUs — each layer is now cached and
                  // repainted only when ITS OWN animation actually changes.
                  RepaintBoundary(
                    child: Container(
                      width: 188,
                      height: 188,
                      decoration: AppDepth.metal(
                        level: 3,
                        isDark: true,
                        radius: BorderRadius.circular(94),
                      ),
                    ),
                  ),
                  RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: Listenable.merge([_handCtrl, _glowCtrl]),
                      builder: (_, __) => CustomPaint(
                        size: const Size(200, 200),
                        painter: _ClockSweepPainter(t: _handCtrl.value, glow: _glowCtrl.value),
                      ),
                    ),
                  ),
                  // The AFOS monogram punches in letter-by-letter — a dramatic
                  // spring pop toward the viewer, tinted with the brand duo.
                  RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: _introCtrl,
                      builder: (_, __) => ShaderMask(
                        shaderCallback: (r) => AppColors.holoGradient.createShader(r),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          for (var i = 0; i < 4; i++) _monoLetter('AFOS'[i], i),
                        ]),
                      ),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 28),
              // Its own boundary too -- two NESTED ShaderMasks (the wipe, then
              // the gradient tint) each cost a saveLayer; isolating them stops
              // that cost from also forcing the clock/monogram stack above
              // (and the particle field behind everything) to recomposite on
              // every one of this animation's frames, and vice versa.
              RepaintBoundary(
                child: AnimatedBuilder(
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
                    child: const ColoredBox(color: AppColors.splashSheen),
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
        colors: AppColors.splashGlowTeal))),
      DecoratedBox(decoration: BoxDecoration(gradient: RadialGradient(
        center: Alignment(0.9, 0.9), radius: 1.2,
        colors: AppColors.splashGlowBlue))),
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

    // Three satellite marks, orbiting slower and counter to the hand --
    // cheap (three more drawCircle calls on the SAME canvas this painter
    // already owns, no new layer, no new shader) but reads as a real
    // instrument with more than one thing in motion, not a single hand on a
    // static face. Glow-linked so the whole dial breathes as one system
    // rather than two unrelated loops. Placed INSIDE the outer ring, not
    // beyond it -- the canvas is exactly 200x200 (center at 100,100, so ~98
    // is already the safe max radius the outer ring itself uses); anything
    // past that clips against the Stack's own hardEdge bound.
    final orbitR = radius - 9;
    for (int i = 0; i < 3; i++) {
      final a = -t * 2 * pi * 0.4 + i * (2 * pi / 3);
      canvas.drawCircle(
        c + Offset(cos(a), sin(a)) * orbitR,
        1.1 + glow * 0.4,
        Paint()..color = AppColors.holoTeal.withValues(alpha: 0.25 + glow * 0.35),
      );
    }

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
