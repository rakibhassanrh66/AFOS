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
  void dispose() { _emailCtrl.dispose(); _passCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (ctx, state) {
        if(state is AuthAuthenticated) ctx.go('/home');
        if(state is AuthError) ctx.showSnack(state.message, isError:true);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(children:[
          // Background gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
            ),
          ),
          // Subtle grid lines
          CustomPaint(painter:_GridPainter(), size: Size.infinite),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal:28, vertical:24),
              child: GlassCard(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Form(
                    key: _formKey,
                    child: Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
                      const SizedBox(height:40),
                      // Logo
                      Center(child: Row(mainAxisSize:MainAxisSize.min, children:[
                        _logoLetter('A', Colors.white),
                        const SizedBox(width:8),
                        _logoLetter('F', Colors.white),
                        const SizedBox(width:8),
                        _logoLetter('O', Colors.white),
                        const SizedBox(width:8),
                        _logoLetter('S', Colors.white),
                      ])).animate().fadeIn(duration:600.ms).slideY(begin:-0.3),
                      const SizedBox(height:40),
                      Text('Welcome back 👋', style:AppTextStyles.displayMedium.copyWith(color: Colors.white))
                        .animate(delay:200.ms).fadeIn().slideX(begin:-0.1),
                      const SizedBox(height:4),
                      Text('Sign in to your AFOS account',
                        style:AppTextStyles.bodyMedium.copyWith(color: Colors.white70))
                        .animate(delay:300.ms).fadeIn(),
                      const SizedBox(height:36),
                      AfosTextField(
                        hint:'Email address', controller:_emailCtrl,
                        prefixIcon:Icons.email_outlined,
                        keyboardType:TextInputType.emailAddress,
                        validator:AppValidators.email,
                      ).animate(delay:400.ms).fadeIn().slideY(begin:0.1),
                      const SizedBox(height:16),
                      AfosTextField(
                        hint:'Password', controller:_passCtrl,
                        prefixIcon:Icons.lock_outline, obscure:true,
                        validator:AppValidators.password,
                      ).animate(delay:500.ms).fadeIn().slideY(begin:0.1),
                      const SizedBox(height:12),
                      Align(
                        alignment:Alignment.centerRight,
                        child: TextButton(
                          onPressed:()=>context.push('/auth/forgot-password'),
                          child:const Text('Forgot password?',
                            style:TextStyle(color:Colors.white, fontSize:13)),
                        ),
                      ),
                      const SizedBox(height:24),
                      BlocBuilder<AuthBloc,AuthState>(
                        builder:(ctx,state) => Container(
                          decoration:BoxDecoration(
                            gradient:LinearGradient(colors: [Colors.blue.shade300, Colors.blue.shade600]),
                            borderRadius:BorderRadius.circular(12),
                            boxShadow:[BoxShadow(color:Colors.blue.withOpacity(0.3),blurRadius:20,offset:const Offset(0,8))],
                          ),
                          child: AfosButton(
                            label:'Sign in to AFOS',
                            loading:state is AuthLoading,
                            onTap:(){
                              if(_formKey.currentState!.validate()) {
                                ctx.read<AuthBloc>().add(
                                  AuthLoginRequested(_emailCtrl.text.trim(),_passCtrl.text));
                              }
                            },
                          ),
                        ),
                      ).animate(delay:600.ms).fadeIn().slideY(begin:0.1),
                      const SizedBox(height:32),
                      Row(mainAxisAlignment:MainAxisAlignment.center, children:[
                        Text("Don't have an account?", style:AppTextStyles.bodyMedium.copyWith(color: Colors.white70)),
                        TextButton(
                          onPressed:()=>context.push('/auth/register'),
                          child:const Text('Create account →',
                            style:TextStyle(color:Colors.white,fontWeight:FontWeight.w600)),
                        ),
                      ]).animate(delay:700.ms).fadeIn(),
                      const SizedBox(height:24),
                      Center(child: Text('Daffodil International University',
                        style:AppTextStyles.labelSmall.copyWith(color: Colors.white70)))
                        .animate(delay:800.ms).fadeIn(),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _logoLetter(String l, Color c) => Container(
    width:44, height:44,
    decoration:BoxDecoration(
      borderRadius:BorderRadius.circular(10),
      border:Border.all(color:c.withOpacity(0.4)),
      color:c.withOpacity(0.1),
    ),
    alignment:Alignment.center,
    child:Text(l,style:TextStyle(color:c,fontSize:22,fontWeight:FontWeight.w900)),
  );
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color=const Color(0xFF1A2840)..strokeWidth=0.3;
    for(double x=0;x<size.width;x+=40) canvas.drawLine(Offset(x,0),Offset(x,size.height),p);
    for(double y=0;y<size.height;y+=40) canvas.drawLine(Offset(0,y),Offset(size.width,y),p);
  }
  @override bool shouldRepaint(_)=>false;
}
