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
import '../../../config/theme/depth.dart';
import '../../../config/theme/motion.dart';
import '../../../core/auth/biometric_lock.dart';
import '../../../core/haptics/app_haptics.dart';
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

  // A real secure-storage lookup done on screen entry (not a cached flag):
  // whether this device can do biometrics, and which account's session is
  // stored for quick-login. The in-field fingerprint icon only appears when the
  // typed email matches that account.
  bool _biometricUsable = false;
  List<String> _biometricEmails = const [];
  String? _biometricMsg; // inline message shown under the password field

  @override
  void initState() {
    super.initState();
    _prefillFromRegistration();
    _loadBiometricState();
  }

  Future<void> _prefillFromRegistration() async {
    final pending = await PendingCredentialsStore.consume();
    if (pending == null || !mounted) return;
    setState(() {
      _emailCtrl.text = pending.$1;
      _passCtrl.text = pending.$2;
    });
  }

  /// Real lookup against secure storage every time the login screen mounts:
  /// can this device do biometrics, and which accounts' emails have a
  /// quick-login session stored (possibly several — one device can now
  /// remember more than one account at once).
  Future<void> _loadBiometricState() async {
    final can = await BiometricAuth.canUse();
    final accounts = await BiometricTokenStore.listAccounts();
    if (!can) {
      debugPrint('[biometric] unavailable on this device '
          '(unsupported or no enrolled fingerprint/face) — fingerprint icon hidden');
    }
    if (mounted) {
      setState(() {
        _biometricUsable = can;
        _biometricEmails = accounts.map((a) => a.email).toList();
      });
    }
  }

  // Show the in-field fingerprint icon only when this device can do
  // biometrics and the typed email matches one of the remembered accounts.
  bool get _showFingerprint {
    final typed = _emailCtrl.text.trim().toLowerCase();
    return _biometricUsable && typed.isNotEmpty &&
        _biometricEmails.any((e) => e.toLowerCase() == typed);
  }

  /// Fingerprint trigger — the icon tap, or "Sign In" with an empty password +
  /// a matching stored session. Gates local retrieval of a session a previous
  /// password login already produced; never mints or validates a session. On
  /// failure it shows an inline message and leaves the password form usable.
  Future<void> _runBiometric(BuildContext ctx) async {
    setState(() => _biometricMsg = null);
    final ok = await BiometricAuth.authenticate('Sign in to AFOS');
    if (!ctx.mounted) return;
    if (!ok) {
      setState(() => _biometricMsg = "Fingerprint didn't match — try again or enter your password");
      return;
    }
    try {
      final account = await BiometricTokenStore.byEmail(_emailCtrl.text.trim());
      final stored = account?.sessionJson;
      if (stored == null) {
        // The `ctx.mounted` check above sits BEFORE this await. A
        // Keystore-backed secure-storage read is the one this app's own
        // splash-screen history documents as occasionally slow on some OEM
        // builds, so it is long enough to outlive the screen.
        if (!mounted) return;
        setState(() => _biometricMsg = 'Saved session expired — please enter your password');
        return;
      }
      if (Supabase.instance.client.auth.currentSession == null) {
        await Supabase.instance.client.auth.recoverSession(stored);
      }
      await BiometricTokenStore.setLastActive(account!.userId);
    } catch (_) {
      if (ctx.mounted) setState(() => _biometricMsg = "Couldn't restore your session — please enter your password");
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
        !await BiometricTokenStore.isEnabledFor(session.user.id) &&
        !await BiometricTokenStore.wasPrompted()) {
      if (!ctx.mounted) return;
      final enable = await showDialog<bool>(
        context: ctx,
        builder: (dctx) => AlertDialog(
          backgroundColor: AppColors.surfaceOf(dctx),
          shape: RoundedRectangleBorder(borderRadius: AppDepth.radius(3)),
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
        Map<String, dynamic>? profile;
        try {
          profile = await Supabase.instance.client.from('profiles')
              .select('full_name, avatar_url').eq('id', session.user.id).maybeSingle();
        } catch (_) {/* best-effort display info only */}
        await BiometricTokenStore.remember(
          userId: session.user.id,
          email: session.user.email ?? '',
          sessionJson: jsonEncode(session.toJson()),
          fullName: profile?['full_name'] as String?,
          avatarUrl: profile?['avatar_url'] as String?,
        );
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
        // Signing in is the commit; a refused sign-in is the app saying no.
        if(state is AuthAuthenticated) { AppHaptics.success(); _afterLogin(ctx); }
        if(state is AuthError) { AppHaptics.warning(); ctx.showSnack(state.message, isError:true); }
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
                    showFingerprint: _showFingerprint, onFingerprint: () => _runBiometric(context),
                    biometricMsg: _biometricMsg, onEmailChanged: () => setState(() {}))),
              ]);
            }
            return _FormPane(
                isDark: isDark, textPrimary: textPrimary, textSecondary: textSecondary,
                formKey: _formKey, emailCtrl: _emailCtrl, passCtrl: _passCtrl,
                cardMaxWidth: outer.maxWidth >= Responsive.mediumBreakpoint ? 460 : double.infinity,
                showFingerprint: _showFingerprint, onFingerprint: () => _runBiometric(context),
                biometricMsg: _biometricMsg, onEmailChanged: () => setState(() {}));
          },
        ),
      ),
    );
  }
}

/// Vertical padding of the login scroll view. Named because `minHeight` has to
/// subtract exactly this to keep the card centred and the page unscrollable —
/// if the two ever drift apart the page starts sliding again.
const double _vPad = 24;

class _FormPane extends StatelessWidget {
  final bool isDark;
  final Color textPrimary, textSecondary;
  final GlobalKey<FormState> formKey;
  final TextEditingController emailCtrl, passCtrl;
  final double cardMaxWidth;
  // Fingerprint quick-login (in the password field's suffix). Only shown when a
  // matching stored session exists for the typed email; onFingerprint runs the
  // OS biometric prompt; biometricMsg is the inline status under the field;
  // onEmailChanged lets the parent re-evaluate showFingerprint as the user types.
  final bool showFingerprint;
  final VoidCallback onFingerprint;
  final String? biometricMsg;
  final VoidCallback onEmailChanged;
  const _FormPane({
    required this.isDark, required this.textPrimary, required this.textSecondary,
    required this.formKey, required this.emailCtrl, required this.passCtrl, required this.cardMaxWidth,
    required this.showFingerprint, required this.onFingerprint,
    required this.biometricMsg, required this.onEmailChanged,
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
                    ? AppColors.authCanvasDark
                    : AppColors.authCanvasLight,
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          // Subtle grid lines
          RepaintBoundary(child: CustomPaint(painter:_GridPainter(isDark:isDark), size: Size.infinite)),
          SafeArea(
            child: LayoutBuilder(
              // Exactly centred, and NOT draggable when it fits.
              //
              // Two things were wrong. (1) The bottom padding included
              // `GlassBottomNav.navContentClearance` — but this screen is not
              // inside the AppShell and has no bottom nav, so that was ~100px of
              // phantom space shoving the card upward off centre. It came from
              // the codemod that added clearance to 80 scrollviews; login should
              // never have been one of them. (2) `minHeight` used the FULL
              // viewport height while the scroll view added its own vertical
              // padding on top, so the content was always taller than the
              // viewport — which is why the page could be pulled up and down
              // even with room to spare.
              //
              // Subtracting the padding from minHeight makes the content exactly
              // one viewport tall, so Center puts the card dead centre on any
              // device and there is nothing to scroll — until the keyboard opens
              // or the screen is genuinely too short, when it scrolls properly.
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsetsDirectional.fromSTEB(28, _vPad, 28, _vPad),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                      minHeight: (constraints.maxHeight - _vPad * 2).clamp(0.0, double.infinity)),
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
                      // cacheWidth, because the source is 1086x1196 and decodes
                      // to ~5 MB of ARGB to paint an 88px logo. 264 = 88 at a
                      // 3x device pixel ratio, which is the densest screen this
                      // ships to, so it is still pixel-sharp at ~0.3 MB.
                      Center(child: Image.asset('assets/images/diu_logo.png', height:88, cacheWidth: 264,
                          errorBuilder: (_, __, ___) => Row(mainAxisSize:MainAxisSize.min, children:[
                            _logoLetter('A', AppColors.holoBlue, context),
                            const SizedBox(width:8),
                            _logoLetter('F', AppColors.gold, context),
                            const SizedBox(width:8),
                            _logoLetter('O', AppColors.teal, context),
                            const SizedBox(width:8),
                            _logoLetter('S', AppColors.holoTeal, context),
                          ])))
                        .animate()
                        .fadeIn(duration: AppMotion.durationOf(context, AppMotion.slow), curve: AppMotion.standard)
                        .slideY(begin:-0.3, curve: AppMotion.standard),
                      const SizedBox(height:32),
                      // Centered to match the logo above and the university
                      // footer below — the enclosing Column is
                      // CrossAxisAlignment.start (correct for the form fields
                      // beneath), so these two lines need their own Center or
                      // they hug the left edge under a centered logo.
                      Center(child: Text('Welcome back', style:AppTextStyles.displayMedium.copyWith(color: textPrimary)))
                        .animate(delay: AppMotion.sequenceDelay(context, 3))
                        .fadeIn(duration: AppMotion.durationOf(context, AppMotion.base))
                        .slideX(begin:-0.08, curve: AppMotion.standard),
                      const SizedBox(height:4),
                      Center(child: Text('Sign in to your AFOS account',
                        style:AppTextStyles.bodyMedium.copyWith(color: textSecondary)))
                        .animate(delay: AppMotion.sequenceDelay(context, 5))
                        .fadeIn(duration: AppMotion.durationOf(context, AppMotion.base)),
                      const SizedBox(height:32),
                      AfosTextField(
                        hint:'Email address', controller:emailCtrl,
                        prefixIcon:Icons.email_outlined,
                        keyboardType:TextInputType.emailAddress,
                        autocorrect:false, enableSuggestions:false,
                        validator:AppValidators.loginEmail,
                        // Re-evaluate whether the fingerprint icon should show:
                        // it only appears when the typed email matches the
                        // account whose session is stored on this device.
                        onChanged:(_) => onEmailChanged(),
                      ).animate(delay: AppMotion.sequenceDelay(context, 7))
                        .fadeIn(duration: AppMotion.durationOf(context, AppMotion.base))
                        .slideY(begin:0.08, curve: AppMotion.standard),
                      const SizedBox(height:16),
                      AfosTextField(
                        hint:'Password', controller:passCtrl,
                        prefixIcon:Icons.lock_outline, obscure:true,
                        validator:AppValidators.loginPassword,
                        // Fingerprint quick-login sits in the password field's
                        // suffix, beside the show/hide eye. Only rendered when a
                        // stored session matches the typed email.
                        trailingIcon: showFingerprint ? Icons.fingerprint_rounded : null,
                        onTrailingIconTap: showFingerprint ? onFingerprint : null,
                        trailingTooltip: 'Sign in with fingerprint / Face ID',
                      ).animate(delay: AppMotion.sequenceDelay(context, 8))
                        .fadeIn(duration: AppMotion.durationOf(context, AppMotion.base))
                        .slideY(begin:0.08, curve: AppMotion.standard),
                      if (biometricMsg != null) ...[
                        const SizedBox(height:10),
                        Row(crossAxisAlignment:CrossAxisAlignment.start, children:[
                          const Padding(padding: EdgeInsets.only(top:1),
                              child: Icon(Icons.info_outline, size:15, color: AppColors.holoBlue)),
                          const SizedBox(width:6),
                          Expanded(child: Text(biometricMsg!,
                              style: AppTextStyles.labelSmall.copyWith(color: AppColors.holoBlue))),
                        ]),
                      ],
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
                            // Trigger 2: pressing Sign In with an empty password
                            // when a matching biometric session exists runs the
                            // fingerprint prompt instead of a "password required"
                            // error. Otherwise, normal password auth is untouched.
                            if (showFingerprint && passCtrl.text.isEmpty) {
                              onFingerprint();
                              return;
                            }
                            if(formKey.currentState!.validate()) {
                              ctx.read<AuthBloc>().add(
                                AuthLoginRequested(emailCtrl.text.trim(),passCtrl.text));
                            }
                          },
                        ),
                      ).animate(delay: AppMotion.sequenceDelay(context, 10))
                        .fadeIn(duration: AppMotion.durationOf(context, AppMotion.base))
                        .slideY(begin:0.08, curve: AppMotion.standard),
                      const SizedBox(height:28),
                      // Wrap, not Row. As a Row these two children have a
                      // combined intrinsic width that exceeds the card below
                      // ~350px, and a release build CLIPS rather than showing
                      // the debug overflow stripes: at 320px — the responsive
                      // floor this project commits to — "Create account →"
                      // rendered as "Create acco", and at 340px the arrow was
                      // cut off. Measured in Chromium at 320/340/360.
                      // Wrap flows the link onto its own line instead.
                      Wrap(alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center, children:[
                        Text("Don't have an account?", style:AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
                        TextButton(
                          onPressed:()=>context.push('/auth/register'),
                          child:Text('Create account →',
                            style:TextStyle(color:textPrimary,fontWeight:FontWeight.w600)),
                        ),
                      ]).animate(delay: AppMotion.sequenceDelay(context, 12))
                        .fadeIn(duration: AppMotion.durationOf(context, AppMotion.base)),
                      const SizedBox(height:12),
                      Center(child: Text('Daffodil International University',
                        style:AppTextStyles.labelSmall.copyWith(color: textSecondary)))
                        .animate(delay: AppMotion.sequenceDelay(context, 13))
                        .fadeIn(duration: AppMotion.durationOf(context, AppMotion.base)),
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
      borderRadius: AppDepth.radius(1),
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
      ..color = (isDark ? AppColors.authGridDark : AppColors.authGridLight)
          .withValues(alpha: isDark ? 1 : 0.05)
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
