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
import '../../../core/utils/validators.dart';

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
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc,AuthState>(
      listener:(ctx,state) {
        if(state is AuthPasswordResetSent) setState(()=>_sent=true);
        if(state is AuthError) ctx.showSnack(state.message,isError:true);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(leading:IconButton(icon:const Icon(Icons.arrow_back),onPressed:()=>context.pop())),
        body: Padding(
          padding: const EdgeInsets.all(28),
          child: _sent ? _SuccessView() : Form(
            key:_formKey,
            child: Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
              const SizedBox(height:24),
              const Icon(Icons.lock_reset, color:AppColors.blue, size:48)
                .animate().scale(duration:600.ms,curve:Curves.easeOutBack),
              const SizedBox(height:24),
              Text('Reset Password', style:AppTextStyles.displayMedium)
                .animate(delay:200.ms).fadeIn(),
              const SizedBox(height:8),
              Text('Enter your email. We\'ll send a reset link.',
                style:AppTextStyles.bodyMedium).animate(delay:300.ms).fadeIn(),
              const SizedBox(height:32),
              AfosTextField(hint:'Email address', controller:_ctrl,
                prefixIcon:Icons.email_outlined, keyboardType:TextInputType.emailAddress,
                validator:AppValidators.email)
                .animate(delay:400.ms).fadeIn().slideY(begin:0.1),
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
              ).animate(delay:500.ms).fadeIn(),
            ]),
          ),
        ),
      ),
    );
  }
}

class _SuccessView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(child: Column(mainAxisSize:MainAxisSize.min, children:[
      const Icon(Icons.mark_email_read_outlined, color:AppColors.green, size:72)
        .animate().scale(duration:600.ms,curve:Curves.easeOutBack),
      const SizedBox(height:24),
      Text('Check your inbox!', style:AppTextStyles.displayMedium, textAlign:TextAlign.center),
      const SizedBox(height:12),
      Text('A password reset link has been sent to your email.',
        style:AppTextStyles.bodyMedium, textAlign:TextAlign.center),
      const SizedBox(height:32),
      AfosButton(label:'Back to Login', onTap:()=>GoRouter.of(context).go('/auth/login')),
    ]));
  }
}
