import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../config/app_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/liquid_glass_tokens.dart';
import '../../../core/utils/last_route.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _particleCtrl;
  late AnimationController _glowCtrl;
  late AnimationController _scanCtrl;
  final List<_Particle> _particles = [];
  bool _showTagline = false, _showSub = false, _showTeam = false;

  // Brand teal→blue duo only (the two-accent cap) — the old per-letter
  // teal/indigo/violet/red set was off-palette.
  static const _letterColors = [
    AppColors.green,      // A — brand teal
    AppColors.teal,       // F — cyan bridge
    AppColors.blueLight,  // O — blue
    AppColors.blue,       // S — deep blue
  ];

  @override
  void initState() {
    super.initState();
    _particleCtrl = AnimationController(vsync:this, duration:const Duration(seconds:10))
      ..repeat();
    _glowCtrl = AnimationController(vsync:this, duration:const Duration(seconds:3))
      ..repeat(reverse:true);
    _scanCtrl = AnimationController(vsync:this, duration:const Duration(milliseconds:1400))
      ..repeat();
    final rng = Random();
    for(int i=0; i<60; i++) {
      _particles.add(_Particle(
        x: rng.nextDouble(), y: rng.nextDouble(),
        r: rng.nextDouble()*2+0.5,
        dx: (rng.nextDouble()-0.5)*0.001,
        dy: (rng.nextDouble()-0.5)*0.001,
        opacity: rng.nextDouble()*0.5+0.1,
      ));
    }
    _animate();
  }

  Future<void> _animate() async {
    await Future.delayed(const Duration(milliseconds:2000));
    if(mounted) setState(()=>_showTagline=true);
    await Future.delayed(const Duration(milliseconds:500));
    if(mounted) setState(()=>_showSub=true);
    await Future.delayed(const Duration(milliseconds:500));
    if(mounted) setState(()=>_showTeam=true);
    await Future.delayed(const Duration(milliseconds:1500));
    if(!mounted) return;
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) { context.go('/auth/login'); return; }
    // Resume where the user actually left off (a force-close, not a real
    // logout, shouldn't drop them back to the dashboard every time) — the
    // router's own redirect gates (profile completion, approval, role)
    // still run normally against this target, so an invalid/stale saved
    // route just falls through to its normal guard behavior.
    final lastRoute = await loadLastRoute();
    if (!mounted) return;
    context.go(lastRoute ?? '/home');
  }

  @override
  void dispose() { _particleCtrl.dispose(); _glowCtrl.dispose(); _scanCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(children:[
        // Ambient teal/blue washes so the glass tiles have something to refract.
        const _AmbientWash(),
        RepaintBoundary(
          child: AnimatedBuilder(animation:_particleCtrl, builder:(_,__)=>
            CustomPaint(painter:_ParticlePainter(_particles,_particleCtrl.value),
              size: Size.infinite)),
        ),
        // Holographic glow pulse behind logo
        Center(
          child: AnimatedBuilder(
            animation: _glowCtrl,
            builder: (_, __) => Container(
              width: 300, height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors:[
                  AppColors.holoBlue.withValues(alpha: 0.10 + _glowCtrl.value*0.12),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
        ),
        Center(child: Column(mainAxisSize:MainAxisSize.min, children:[
          Row(mainAxisSize:MainAxisSize.min, children:[
            _letter('A', _letterColors[0], 0),
            const SizedBox(width:12),
            _letter('F', _letterColors[1], 300),
            const SizedBox(width:12),
            _letter('O', _letterColors[2], 600),
            const SizedBox(width:12),
            _letter('S', _letterColors[3], 900),
          ]),
          const SizedBox(height:28),
          AnimatedOpacity(opacity:_showTagline?1:0, duration:600.ms, curve: Curves.easeOutCubic,
            child: ShaderMask(
              shaderCallback: (rect) => AppColors.holoGradient.createShader(rect),
              child: const Text('All Facilities One System',
                style: TextStyle(color:Colors.white, fontSize:16,
                  letterSpacing:1.5, fontWeight:FontWeight.w400)),
            )),
          const SizedBox(height:6),
          AnimatedOpacity(opacity:_showSub?1:0, duration:600.ms, curve: Curves.easeOutCubic,
            child: const Text('Daffodil International University',
              style: TextStyle(color:AppColors.textSecondary, fontSize:13))),
          const SizedBox(height:32),
          AnimatedOpacity(opacity:_showTeam?1:0, duration:600.ms, curve: Curves.easeOutCubic,
            child: Column(children:[
              SizedBox(width:120, height:3, child: AnimatedBuilder(
                animation: _scanCtrl,
                builder: (_, __) => CustomPaint(painter: _ScanBarPainter(t: _scanCtrl.value)),
              )),
              const SizedBox(height:12),
              Text('AFOS v${AppConfig.appVersion}', style: const TextStyle(color:AppColors.textMuted,fontSize:11,
                fontFamily:'monospace', letterSpacing:1)),
            ])),
        ])),
      ]),
    );
  }

  /// Frosted glass letter tile — brand-colored glow + glossy sheen, with the
  /// signature top-right corner cut.
  Widget _letter(String l, Color c, int delayMs) {
    final radius = LiquidGlass.signatureRadius(18);
    return ClipRRect(
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          width:70, height:70,
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color:c.withValues(alpha: 0.5), width:1),
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors:[c.withValues(alpha: 0.22), c.withValues(alpha: 0.06)]),
            boxShadow: [BoxShadow(color:c.withValues(alpha: 0.35), blurRadius: 18, spreadRadius: -4)],
          ),
          alignment: Alignment.center,
          child: Stack(alignment: Alignment.center, children: [
            Positioned.fill(child: IgnorePointer(child: DecoratedBox(
              decoration: BoxDecoration(gradient: LiquidGlass.sheen(isDark: true))))),
            Text(l, style:TextStyle(color:c,fontSize:32,fontWeight:FontWeight.w900)),
          ]),
        ),
      ),
    )
    .animate(delay:Duration(milliseconds:delayMs))
    .slideY(begin:-0.5,end:0,duration:520.ms,curve:Curves.easeOutBack)
    .fadeIn(duration:420.ms)
    .then()
    .shimmer(duration:1200.ms, color: Colors.white.withValues(alpha: 0.25));
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

class _Particle { double x,y,r,dx,dy,opacity;
  _Particle({required this.x,required this.y,required this.r,
    required this.dx,required this.dy,required this.opacity}); }

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double tick;
  _ParticlePainter(this.particles, this.tick);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for(final p in particles) {
      p.x = (p.x + p.dx) % 1.0;
      p.y = (p.y + p.dy) % 1.0;
      paint.color = AppColors.blueLight.withValues(alpha: p.opacity);
      canvas.drawCircle(Offset(p.x*size.width, p.y*size.height), p.r, paint);
    }
  }
  @override bool shouldRepaint(_) => true;
}

/// A sweeping highlight scanning back and forth across the track, replacing
/// a plain static progress line under the version label.
class _ScanBarPainter extends CustomPainter {
  final double t;
  _ScanBarPainter({required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final trackPaint = Paint()..color = AppColors.border;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.height / 2)),
      trackPaint,
    );
    // Bounce 0->1->0 across the track rather than a hard reset each loop.
    final pos = t < 0.5 ? t * 2 : (1 - t) * 2;
    final sweepWidth = size.width * 0.32;
    final center = pos * size.width;
    final rect = Rect.fromCenter(center: Offset(center, size.height / 2), width: sweepWidth, height: size.height);
    final gradient = LinearGradient(colors: [
      AppColors.holoBlue.withValues(alpha: 0),
      AppColors.holoBlue,
      AppColors.holoBlue.withValues(alpha: 0),
    ]).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.height / 2)),
      Paint()..shader = gradient,
    );
  }

  @override
  bool shouldRepaint(covariant _ScanBarPainter oldDelegate) => oldDelegate.t != t;
}
