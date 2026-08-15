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
import '../../../config/theme/motion.dart';
import '../../../shared/extensions/context_ext.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/afos_text_field.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../core/utils/validators.dart';
import '../../../core/utils/responsive.dart';
import 'widgets/auth_brand_panel.dart';

class ForgotPasswordScreen extends StatelessWidget {
  const ForgotPasswordScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return BlocProvider(create:(_)=>AuthBloc(AuthRepository()), child:const _ForgotBody());
  }
}

class _ForgotBody extends StatefulWidget {
  const _ForgotBody();
  @override State<_ForgotBody> createState() => _ForgotBodyState();
}

class _ForgotBodyState extends State<_ForgotBody> {
  final _formKey = GlobalKey<FormState>();
  final _ctrl = TextEditingController();
  bool _sent = false;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    return BlocListener<AuthBloc,AuthState>(
      listener:(ctx,state) {
        if(state is AuthPasswordResetSent) setState(()=>_sent=true);
        if(state is AuthError) ctx.showSnack(state.message,isError:true);
      },
      child: Scaffold(
        backgroundColor: AppColors.surfaceOf(context),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading:IconButton(
            icon:Icon(Icons.arrow_back, color: textPrimary),
            onPressed:()=>context.pop()),
        ),
        body: LayoutBuilder(
          builder: (context, outer) {
            final formCard = SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                child: Center(child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: outer.maxWidth >= Responsive.mediumBreakpoint ? 460 : double.infinity),
                  child: GlassCard(
                    glowColor: AppColors.teal,
                    animated: true,
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: _sent
                        ? _SuccessView(textPrimary: textPrimary, textSecondary: textSecondary)
                        : Form(
                            key:_formKey,
                            child: Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
                              Container(
                                width:56, height:56,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.holoBlue.withValues(alpha: 0.12),
                                  border: Border.all(color: AppColors.holoBlue.withValues(alpha: 0.4)),
                                ),
                                alignment: Alignment.center,
                                child: const Icon(Icons.lock_reset, color:AppColors.holoBlue, size:28),
                              ).animate()
          .scale(duration: AppMotion.durationOf(context, AppMotion.slow), curve: AppMotion.standard)
          .fadeIn(duration: AppMotion.durationOf(context, AppMotion.base)),
                              const SizedBox(height:24),
                              Text('Reset Password', style:AppTextStyles.displayMedium.copyWith(color: textPrimary))
                                .animate(delay: AppMotion.sequenceDelay(context, 3))
                                .fadeIn(duration: AppMotion.durationOf(context, AppMotion.base))
                                .slideX(begin:-0.06, curve: AppMotion.standard),
                              const SizedBox(height:8),
                              Text("Enter your email. We'll send a reset link.",
                                style:AppTextStyles.bodyMedium.copyWith(color: textSecondary))
                                .animate(delay: AppMotion.sequenceDelay(context, 5))
        .fadeIn(duration: AppMotion.durationOf(context, AppMotion.base)),
                              const SizedBox(height:32),
                              AfosTextField(hint:'Email address', controller:_ctrl,
                                prefixIcon:Icons.email_outlined, keyboardType:TextInputType.emailAddress,
                                validator:AppValidators.loginEmail)
                                .animate(delay: AppMotion.sequenceDelay(context, 7))
                                .fadeIn(duration: AppMotion.durationOf(context, AppMotion.base))
                                .slideY(begin:0.08, curve: AppMotion.standard),
                              const SizedBox(height:24),
                              BlocBuilder<AuthBloc,AuthState>(
                                builder:(ctx,state) => AfosButton(
                                  label:'Send Reset Link',
                                  loading:state is AuthLoading,
                                  onTap:(){
                                    if(_formKey.currentState!.validate()) {
                                      ctx.read<AuthBloc>().add(AuthForgotPassword(_ctrl.text.trim()));
                                    }
                                  },
                                ),
                              ).animate(delay: AppMotion.sequenceDelay(context, 8))
                                .fadeIn(duration: AppMotion.durationOf(context, AppMotion.base))
                                .slideY(begin:0.08, curve: AppMotion.standard),
                            ]),
                          ),
                    ),
                  ),
                )),
              ),
            );
            if (outer.maxWidth >= Responsive.expandedBreakpoint) {
              return Row(children: [
                const Expanded(flex: 5, child: AuthBrandPanel()),
                Expanded(flex: 4, child: formCard),
              ]);
            }
            return formCard;
          },
        ),
      ),
    );
  }
}

class _SuccessView extends StatelessWidget {
  final Color textPrimary, textSecondary;
  const _SuccessView({required this.textPrimary, required this.textSecondary});
  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize:MainAxisSize.min, children:[
      Container(
        width:72, height:72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.green.withValues(alpha: 0.12),
          border: Border.all(color: AppColors.green.withValues(alpha: 0.4)),
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.mark_email_read_outlined, color:AppColors.green, size:36),
      ).animate()
          .scale(duration: AppMotion.durationOf(context, AppMotion.slow), curve: AppMotion.standard)
          .fadeIn(duration: AppMotion.durationOf(context, AppMotion.base)),
      const SizedBox(height:24),
      Text('Check your inbox', style:AppTextStyles.displayMedium.copyWith(color: textPrimary), textAlign:TextAlign.center)
        .animate(delay: AppMotion.sequenceDelay(context, 3))
        .fadeIn(duration: AppMotion.durationOf(context, AppMotion.base)),
      const SizedBox(height:12),
      Text('We sent a password reset link to your email.',
        style:AppTextStyles.bodyMedium.copyWith(color: textSecondary), textAlign:TextAlign.center)
        .animate(delay: AppMotion.sequenceDelay(context, 5))
        .fadeIn(duration: AppMotion.durationOf(context, AppMotion.base)),
      const SizedBox(height:32),
      AfosButton(label:'Back to Login', onTap:()=>GoRouter.of(context).go('/auth/login'))
        .animate(delay: AppMotion.sequenceDelay(context, 7))
        .fadeIn(duration: AppMotion.durationOf(context, AppMotion.base)),
    ]);
  }
}
