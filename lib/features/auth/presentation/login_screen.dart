import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';
import '../data/repositories/auth_repository.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/auth/biometric_lock.dart';
import '../../../shared/extensions/context_ext.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/afos_text_field.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../core/utils/validators.dart';
import '../../../core/utils/pending_credentials_store.dart';
import '../../../core/utils/last_route.dart';
import '../../../core/utils/responsive.dart';
import 'widgets/auth_brand_panel.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AuthBloc(AuthRepository()),
      child: const _LoginBody(),
    );
  }
}

class _LoginBody extends StatefulWidget {
  const _LoginBody();
  @override State<_LoginBody> createState() => _LoginBodyState();
}

class _LoginBodyState extends State<_LoginBody> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();

  // True only when this device can do biometrics AND a session was previously
  // stored on-device (quick-login enabled) — gates the visible unlock button.
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _prefillFromRegistration();
    _refreshBiometricAvailability();
  }

  Future<void> _prefillFromRegistration() async {
    final pending = await PendingCredentialsStore.consume();
    if (pending == null || !mounted) return;
    setState(() {
      _emailCtrl.text = pending.$1;
      _passCtrl.text = pending.$2;
    });
  }

  Future<void> _refreshBiometricAvailability() async {
    final can = await BiometricAuth.canUse();
    final enabled = await BiometricTokenStore.isEnabled();
    if (!can) {
      debugPrint('[biometric] unavailable on this device '
          '(unsupported or no enrolled fingerprint/face) — unlock button hidden');
    }
    if (mounted) setState(() => _biometricAvailable = can && enabled);
  }

  /// The always-visible fingerprint / Face ID button on the login form: gates
  /// local retrieval of a session a previous password login already produced —
  /// it never mints or validates a session itself. On failure it shows a
  /// visible message and leaves the password form fully usable.
  Future<void> _biometricLogin(BuildContext ctx) async {
    final ok = await BiometricAuth.authenticate('Sign in to AFOS');
    if (!ctx.mounted) return;
    if (!ok) {
      ctx.showSnack('Fingerprint not recognized — try again or use your password', isError: true);
      return;
    }
    try {
      if (Supabase.instance.client.auth.currentSession == null) {
        final stored = await BiometricTokenStore.readSession();
        if (stored == null) {
          if (ctx.mounted) ctx.showSnack('Saved session expired — please sign in with your password', isError: true);
          return;
        }
        await Supabase.instance.client.auth.recoverSession(stored);
      }
    } catch (_) {
      if (ctx.mounted) ctx.showSnack("Couldn't restore your session — please sign in with your password", isError: true);
      return;
    }
    if (!ctx.mounted) return;
    final target = await loadLastRoute() ?? '/home';
    if (ctx.mounted) ctx.go(target);
  }

  @override
  void dispose() { _emailCtrl.dispose(); _passCtrl.dispose(); super.dispose(); }

  /// After a successful login, offer to enable biometric quick-login once
  /// (mobile only, if the device supports it and it isn't already set up),
  /// then continue to home. Storing the session JSON only gates a future
  /// local unlock — it never changes how Supabase issues/validates sessions.
  Future<void> _afterLogin(BuildContext ctx) async {
    final session = Supabase.instance.client.auth.currentSession;
    final canUse = await BiometricAuth.canUse();
    if (!canUse) {
      debugPrint('[biometric] device cannot use biometrics '
          '(unsupported or none enrolled) — enable prompt skipped');
    }
    if (session != null &&
        canUse &&
        !await BiometricTokenStore.isEnabled() &&
        !await BiometricTokenStore.wasPrompted()) {
      if (!ctx.mounted) return;
      final enable = await showDialog<bool>(
        context: ctx,
        builder: (dctx) => AlertDialog(
          backgroundColor: AppColors.surfaceOf(dctx),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(children: [
            const Icon(Icons.fingerprint_rounded, color: AppColors.holoBlue),
            const SizedBox(width: 10),
            Expanded(child: Text('Faster sign-in?', style: TextStyle(color: AppColors.textPrimaryOf(dctx)))),
          ]),
          content: Text('Use your fingerprint or Face ID to unlock AFOS next time, without typing your password.',
              style: TextStyle(color: AppColors.textSecondaryOf(dctx))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dctx, false),
                child: Text('Not now', style: TextStyle(color: AppColors.textSecondaryOf(dctx)))),
            TextButton(onPressed: () => Navigator.pop(dctx, true),
                child: const Text('Enable', style: TextStyle(color: AppColors.holoBlue, fontWeight: FontWeight.w700))),
          ],
        ),
      );
      if (enable == true) {
        await BiometricTokenStore.enable(jsonEncode(session.toJson()));
      } else if (enable == false) {
        // Only remember the decline on an explicit "Not now" — an accidental
        // dismiss (barrier tap / back) re-offers on the next login rather than
        // killing the prompt forever.
        await BiometricTokenStore.markPrompted();
      }
    }
    if (ctx.mounted) ctx.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);

    return BlocListener<AuthBloc, AuthState>(
      listener: (ctx, state) {
        if(state is AuthAuthenticated) _afterLogin(ctx);
        if(state is AuthError) ctx.showSnack(state.message, isError:true);
      },
      child: Scaffold(
        backgroundColor: AppColors.surfaceOf(context),
        // The form card had no width limit anywhere in its tree (GlassCard
        // doesn't impose one, and the form fields inside fill whatever
        // width they're offered), so on a desktop-width browser window it
        // stretched to fill nearly the whole screen -- fine on a 390px
        // phone, "super weird" on a 1920px monitor. >=1024px now gets a
        // proper two-pane layout instead: a branding panel explaining what
        // AFOS actually is on the left, the same login form -- just
        // width-capped -- on the right. 600-1024px (tablet / a narrower
        // desktop window) is too tight to fit both panes comfortably, so it
        // just gets the width cap without the branding panel.
        body: LayoutBuilder(
          builder: (context, outer) {
            if (outer.maxWidth >= Responsive.expandedBreakpoint) {
              return Row(children: [
                const Expanded(flex: 5, child: AuthBrandPanel()),
                Expanded(flex: 4, child: _FormPane(
                    isDark: isDark, textPrimary: textPrimary, textSecondary: textSecondary,
                    formKey: _formKey, emailCtrl: _emailCtrl, passCtrl: _passCtrl, cardMaxWidth: 440,
                    showBiometric: _biometricAvailable, onBiometric: () => _biometricLogin(context))),
              ]);
            }
            return _FormPane(
                isDark: isDark, textPrimary: textPrimary, textSecondary: textSecondary,
                formKey: _formKey, emailCtrl: _emailCtrl, passCtrl: _passCtrl,
                cardMaxWidth: outer.maxWidth >= Responsive.mediumBreakpoint ? 460 : double.infinity,
                showBiometric: _biometricAvailable, onBiometric: () => _biometricLogin(context));
          },
        ),
      ),
    );
  }
}

class _FormPane extends StatelessWidget {
  final bool isDark;
  final Color textPrimary, textSecondary;
  final GlobalKey<FormState> formKey;
  final TextEditingController emailCtrl, passCtrl;
  final double cardMaxWidth;
  final bool showBiometric;
  final VoidCallback onBiometric;
  const _FormPane({
    required this.isDark, required this.textPrimary, required this.textSecondary,
    required this.formKey, required this.emailCtrl, required this.passCtrl, required this.cardMaxWidth,
    required this.showBiometric, required this.onBiometric,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(children:[
          // Background gradient — holographic hero backdrop, theme-aware
          RepaintBoundary(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  // The middle stop was noticeably more saturated-blue than
                  // its neighbors, which competed with holoBlue UI text
                  // sitting on top of it (the "Forgot password?" link
                  // specifically) instead of reading as a gentle backdrop.
                  colors: isDark
                    ? const [Color(0xFF0B1220), Color(0xFF102035), Color(0xFF121B2E)]
                    : const [Color(0xFFF0F4FF), Colors.white, Color(0xFFE8EEFC)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          // Subtle grid lines
          RepaintBoundary(child: CustomPaint(painter:_GridPainter(isDark:isDark), size: Size.infinite)),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal:28, vertical:24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Center(child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: cardMaxWidth),
                    child: GlassCard(
                glowColor: AppColors.holoBlue,
                // A slow rotating shimmer costs a continuous Gaussian blur
                // recompute -- not something to turn on for a list of
                // cards, but login is a single, brief, high-visibility
                // hero moment where that cost is worth the "more animated"
                // feel.
                animated: true,
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Form(
                    key: formKey,
                    child: Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
                      const SizedBox(height:16),
                      // Logo
                      Center(child: Image.asset('assets/images/diu_logo.png', height:88,
                          errorBuilder: (_, __, ___) => Row(mainAxisSize:MainAxisSize.min, children:[
                            _logoLetter('A', AppColors.holoBlue, context),
                            const SizedBox(width:8),
                            _logoLetter('F', AppColors.gold, context),
                            const SizedBox(width:8),
                            _logoLetter('O', AppColors.teal, context),
                            const SizedBox(width:8),
                            _logoLetter('S', AppColors.holoTeal, context),
                          ])))
                        .animate().fadeIn(duration:500.ms,curve:Curves.easeOutCubic).slideY(begin:-0.3,curve:Curves.easeOutCubic),
                      const SizedBox(height:32),
                      Text('Welcome back', style:AppTextStyles.displayMedium.copyWith(color: textPrimary))
                        .animate(delay:120.ms).fadeIn(duration:350.ms).slideX(begin:-0.08,curve:Curves.easeOutCubic),
                      const SizedBox(height:4),
                      Text('Sign in to your AFOS account',
                        style:AppTextStyles.bodyMedium.copyWith(color: textSecondary))
                        .animate(delay:200.ms).fadeIn(duration:350.ms),
                      const SizedBox(height:32),
                      AfosTextField(
                        hint:'Email address', controller:emailCtrl,
                        prefixIcon:Icons.email_outlined,
                        keyboardType:TextInputType.emailAddress,
                        autocorrect:false, enableSuggestions:false,
                        validator:AppValidators.loginEmail,
                      ).animate(delay:280.ms).fadeIn(duration:300.ms).slideY(begin:0.08,curve:Curves.easeOutCubic),
                      const SizedBox(height:16),
                      AfosTextField(
                        hint:'Password', controller:passCtrl,
                        prefixIcon:Icons.lock_outline, obscure:true,
                        validator:AppValidators.loginPassword,
                      ).animate(delay:340.ms).fadeIn(duration:300.ms).slideY(begin:0.08,curve:Curves.easeOutCubic),
                      const SizedBox(height:8),
                      Align(
                        alignment:Alignment.centerRight,
                        child: TextButton(
                          onPressed:()=>context.push('/auth/forgot-password'),
                          child:const Text('Forgot password?',
                            style:TextStyle(color:AppColors.holoBlue, fontSize:13, fontWeight:FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(height:16),
                      BlocBuilder<AuthBloc,AuthState>(
                        builder:(ctx,state) => AfosButton(
                          label:'Sign in to AFOS',
                          loading:state is AuthLoading,
                          onTap:(){
                            if(formKey.currentState!.validate()) {
                              ctx.read<AuthBloc>().add(
                                AuthLoginRequested(emailCtrl.text.trim(),passCtrl.text));
                            }
                          },
                        ),
                      ).animate(delay:420.ms).fadeIn(duration:300.ms).slideY(begin:0.08,curve:Curves.easeOutCubic),
                      // Always-visible biometric unlock — shown only when this
                      // device supports biometrics AND a session was previously
                      // stored (quick-login enabled). Never relies on an
                      // automatic prompt that can silently fail to appear.
                      if (showBiometric) ...[
                        const SizedBox(height:18),
                        Row(children:[
                          Expanded(child: Divider(color: textSecondary.withValues(alpha:0.25))),
                          Padding(padding: const EdgeInsets.symmetric(horizontal:12),
                              child: Text('or', style: AppTextStyles.labelSmall.copyWith(color: textSecondary))),
                          Expanded(child: Divider(color: textSecondary.withValues(alpha:0.25))),
                        ]),
                        const SizedBox(height:18),
                        SizedBox(width: double.infinity, child: OutlinedButton.icon(
                          onPressed: onBiometric,
                          icon: const Icon(Icons.fingerprint_rounded, color: AppColors.holoBlue),
                          label: Text('Sign in with fingerprint / Face ID',
                              style: TextStyle(color: textPrimary, fontWeight: FontWeight.w600)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical:14),
                            side: BorderSide(color: AppColors.holoBlue.withValues(alpha:0.5)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        )).animate(delay:460.ms).fadeIn(duration:300.ms),
                      ],
                      const SizedBox(height:28),
                      Row(mainAxisAlignment:MainAxisAlignment.center, children:[
                        Text("Don't have an account?", style:AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
                        TextButton(
                          onPressed:()=>context.push('/auth/register'),
                          child:Text('Create account →',
                            style:TextStyle(color:textPrimary,fontWeight:FontWeight.w600)),
                        ),
                      ]).animate(delay:480.ms).fadeIn(duration:300.ms),
                      const SizedBox(height:12),
                      Center(child: Text('Daffodil International University',
                        style:AppTextStyles.labelSmall.copyWith(color: textSecondary)))
                        .animate(delay:540.ms).fadeIn(duration:300.ms),
                    ]),
                  ),
                ),
              ))),
                ),
              ),
            ),
          ),
        ]);
  }
}

Widget _logoLetter(String l, Color c, BuildContext context) => Container(
    width:44, height:44,
    decoration:BoxDecoration(
      borderRadius:BorderRadius.circular(10),
      border:Border.all(color:c.withValues(alpha: 0.5)),
      color:c.withValues(alpha: 0.12),
    ),
    alignment:Alignment.center,
    child:Text(l,style:TextStyle(color:c,fontSize:22,fontWeight:FontWeight.w900)),
  );

class _GridPainter extends CustomPainter {
  final bool isDark;
  _GridPainter({required this.isDark});
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = (isDark ? const Color(0xFF1A2840) : const Color(0xFF0A1628)).withValues(alpha: isDark ? 1 : 0.05)
      ..strokeWidth=0.3;
    for(double x=0;x<size.width;x+=40) {
      canvas.drawLine(Offset(x,0),Offset(x,size.height),p);
    }
    for(double y=0;y<size.height;y+=40) {
      canvas.drawLine(Offset(0,y),Offset(size.width,y),p);
    }
  }
  @override bool shouldRepaint(covariant _GridPainter old)=>old.isDark!=isDark;
}
