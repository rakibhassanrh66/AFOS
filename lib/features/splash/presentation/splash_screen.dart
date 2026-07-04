import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../config/theme/app_colors.dart';

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
    context.go(session!=null ? '/home' : '/auth/login');
  }

  @override
  void dispose() { _particleCtrl.dispose(); _glowCtrl.dispose(); _scanCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(children:[
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
              width: 260, height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors:[
                  AppColors.holoBlue.withOpacity(0.10 + _glowCtrl.value*0.10),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
        ),
        Center(child: Column(mainAxisSize:MainAxisSize.min, children:[
          Row(mainAxisSize:MainAxisSize.min, children:[
            _letter('A', AppColors.holoBlue, 0),
            const SizedBox(width:10),
            _letter('F', AppColors.gold, 300),
            const SizedBox(width:10),
            _letter('O', AppColors.holoviolet, 600),
            const SizedBox(width:10),
            _letter('S', AppColors.holoTeal, 900),
          ]),
          const SizedBox(height:24),
          AnimatedOpacity(opacity:_showTagline?1:0, duration:600.ms, curve: Curves.easeOutCubic,
            child: ShaderMask(
              shaderCallback: (rect) => AppColors.holoGradient.createShader(rect),
              child: const Text('All Facilities One System',
                style: TextStyle(color:Colors.white, fontSize:16,
                  letterSpacing:1.5, fontWeight:FontWeight.w300)),
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
              const Text('AFOS v1.0.0', style:TextStyle(color:AppColors.textMuted,fontSize:11,
                fontFamily:'monospace', letterSpacing:1)),
            ])),
        ])),
      ]),
    );
  }

  Widget _letter(String l, Color c, int delayMs) {
    return Container(
      width:64, height:64,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color:c.withOpacity(0.4), width:1),
        gradient: RadialGradient(colors:[c.withOpacity(0.15),Colors.transparent],radius:1),
      ),
      alignment: Alignment.center,
      child: Text(l, style:TextStyle(color:c,fontSize:30,fontWeight:FontWeight.w900)),
    )
    .animate(delay:Duration(milliseconds:delayMs))
    .slideY(begin:-0.5,end:0,duration:500.ms,curve:Curves.easeOutBack)
    .fadeIn(duration:400.ms);
  }
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
      paint.color = const Color(0xFF1E6FFF).withOpacity(p.opacity);
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
      AppColors.holoBlue.withOpacity(0),
      AppColors.holoBlue,
      AppColors.holoBlue.withOpacity(0),
    ]).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.height / 2)),
      Paint()..shader = gradient,
    );
  }

  @override
  bool shouldRepaint(covariant _ScanBarPainter oldDelegate) => oldDelegate.t != t;
}
