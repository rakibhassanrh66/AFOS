import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';
import '../data/repositories/auth_repository.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../shared/extensions/context_ext.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/afos_text_field.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../core/utils/validators.dart';
import '../../../core/utils/pending_credentials_store.dart';
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

  @override
  void initState() {
    super.initState();
    _prefillFromRegistration();
  }

  Future<void> _prefillFromRegistration() async {
    final pending = await PendingCredentialsStore.consume();
    if (pending == null || !mounted) return;
    setState(() {
      _emailCtrl.text = pending.$1;
      _passCtrl.text = pending.$2;
    });
  }

  @override
  void dispose() { _emailCtrl.dispose(); _passCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);

    return BlocListener<AuthBloc, AuthState>(
      listener: (ctx, state) {
        if(state is AuthAuthenticated) ctx.go('/home');
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
                    formKey: _formKey, emailCtrl: _emailCtrl, passCtrl: _passCtrl, cardMaxWidth: 440)),
              ]);
            }
            return _FormPane(
                isDark: isDark, textPrimary: textPrimary, textSecondary: textSecondary,
                formKey: _formKey, emailCtrl: _emailCtrl, passCtrl: _passCtrl,
                cardMaxWidth: outer.maxWidth >= Responsive.mediumBreakpoint ? 460 : double.infinity);
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
  const _FormPane({
    required this.isDark, required this.textPrimary, required this.textSecondary,
    required this.formKey, required this.emailCtrl, required this.passCtrl, required this.cardMaxWidth,
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
      ..color = (isDark ? const Color(0xFF1A2840) : const Color(0xFF0A1628)).withOpacity(isDark ? 1 : 0.05)
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
