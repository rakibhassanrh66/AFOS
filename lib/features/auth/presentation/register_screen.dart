import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';
import '../data/repositories/auth_repository.dart';
import '../../../config/app_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../shared/extensions/context_ext.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/afos_text_field.dart';
import '../../../core/utils/validators.dart';

class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create:(_) => AuthBloc(AuthRepository()),
      child: const _RegisterBody(),
    );
  }
}

class _RegisterBody extends StatefulWidget {
  const _RegisterBody();
  @override State<_RegisterBody> createState() => _RegisterBodyState();
}

class _RegisterBodyState extends State<_RegisterBody> {
  int _step = 0;
  final _formKeys = [GlobalKey<FormState>(), GlobalKey<FormState>(), GlobalKey<FormState>()];
  final _nameCtrl = TextEditingController();
  final _idCtrl   = TextEditingController();
  final _emailCtrl= TextEditingController();
  final _passCtrl = TextEditingController();
  final _confCtrl = TextEditingController();
  String _dept = 'CSE';
  double _sem  = 1;

  @override
  void dispose() {
    _nameCtrl.dispose(); _idCtrl.dispose();
    _emailCtrl.dispose(); _passCtrl.dispose(); _confCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener:(ctx,state) {
        if(state is AuthEmailVerificationSent) {
          ctx.showSnack('Account created! Check your email to verify.');
          ctx.go('/auth/login');
        }
        if(state is AuthError) ctx.showSnack(state.message, isError:true);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title:const Text('Create Account'),
          leading:IconButton(icon:const Icon(Icons.arrow_back),onPressed:()=>context.pop())),
        body: Padding(
          padding:const EdgeInsets.symmetric(horizontal:24),
          child: Column(children:[
            const SizedBox(height:16),
            _StepIndicator(step:_step),
            const SizedBox(height:32),
            Expanded(child: IndexedStack(index:_step, children:[
              Form(key:_formKeys[0], child:_Step1(nameCtrl:_nameCtrl, idCtrl:_idCtrl)),
              Form(key:_formKeys[1], child:_Step2(dept:_dept, sem:_sem,
                onDept:(v){setState(()=>_dept=v!);}, onSem:(v){setState(()=>_sem=v);})),
              Form(key:_formKeys[2], child:_Step3(emailCtrl:_emailCtrl,
                passCtrl:_passCtrl, confCtrl:_confCtrl)),
            ])),
            const SizedBox(height:16),
            BlocBuilder<AuthBloc,AuthState>(
              builder:(ctx,state) => Row(children:[
                if(_step>0) Expanded(child:OutlinedButton(
                  onPressed:()=>setState(()=>_step--), child:const Text('Back'))),
                if(_step>0) const SizedBox(width:12),
                Expanded(child: AfosButton(
                  label: _step==2?'Create Account':'Next →',
                  loading: state is AuthLoading,
                  onTap:(){
                    if(_formKeys[_step].currentState!.validate()) {
                      if(_step<2) { setState(()=>_step++); }
                      else {
                        ctx.read<AuthBloc>().add(AuthRegisterRequested(
                          email:_emailCtrl.text.trim(),
                          password:_passCtrl.text,
                          studentId:_idCtrl.text.trim(),
                          fullName:_nameCtrl.text.trim(),
                          department:_dept,
                          semester:_sem.toInt(),
                        ));
                      }
                    }
                  },
                )),
              ]),
            ),
            const SizedBox(height:32),
          ]),
        ),
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  final int step;
  const _StepIndicator({required this.step});
  @override
  Widget build(BuildContext context) {
    return Row(children: List.generate(3,(i) => Expanded(child: Row(children:[
      Container(width:28,height:28,
        decoration:BoxDecoration(
          shape:BoxShape.circle,
          color: i<=step ? AppColors.blue : AppColors.card,
          border:Border.all(color:i<=step?AppColors.blue:AppColors.border),
        ),
        alignment:Alignment.center,
        child: i<step
          ? const Icon(Icons.check,size:14,color:Colors.white)
          : Text('${i+1}',style:TextStyle(fontSize:12,
              color:i==step?Colors.white:AppColors.textSecondary,fontWeight:FontWeight.w600)),
      ),
      if(i<2) Expanded(child:Container(height:1,
        color:i<step?AppColors.blue:AppColors.border)),
    ]))));
  }
}

class _Step1 extends StatelessWidget {
  final TextEditingController nameCtrl, idCtrl;
  const _Step1({required this.nameCtrl, required this.idCtrl});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
    Text('Personal Info', style:AppTextStyles.headlineLarge),
    const SizedBox(height:6),
    Text('Your name and student ID', style:AppTextStyles.bodyMedium),
    const SizedBox(height:24),
    AfosTextField(hint:'Full Name', controller:nameCtrl, prefixIcon:Icons.person_outline,
      validator:(v)=>AppValidators.required(v,f:'Full name')),
    const SizedBox(height:16),
    AfosTextField(hint:'Student ID (XXX-XX-XXXX)', controller:idCtrl,
      prefixIcon:Icons.badge_outlined, validator:AppValidators.studentId,
      keyboardType:TextInputType.number),
  ]);
}

class _Step2 extends StatelessWidget {
  final String dept;
  final double sem;
  final ValueChanged<String?> onDept;
  final ValueChanged<double> onSem;
  const _Step2({required this.dept,required this.sem,required this.onDept,required this.onSem});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
    Text('Academic Info', style:AppTextStyles.headlineLarge),
    const SizedBox(height:6),
    Text('Your department and semester', style:AppTextStyles.bodyMedium),
    const SizedBox(height:24),
    DropdownButtonFormField<String>(
      value: dept,
      decoration: InputDecoration(
        hintText:'Department',
        prefixIcon:const Icon(Icons.school_outlined, color:AppColors.textSecondary, size:20),
        filled:true, fillColor:AppColors.card,
        border:OutlineInputBorder(borderRadius:BorderRadius.circular(12),
          borderSide:const BorderSide(color:AppColors.border,width:0.5)),
        enabledBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(12),
          borderSide:const BorderSide(color:AppColors.border,width:0.5)),
      ),
      dropdownColor: AppColors.card,
      style: const TextStyle(color:AppColors.textPrimary),
      items: AppConfig.departments.map((d)=>DropdownMenuItem(value:d,child:Text(d))).toList(),
      onChanged: onDept,
    ),
    const SizedBox(height:24),
    Text('Semester: ${sem.toInt()}', style:AppTextStyles.titleMedium),
    Slider(value:sem, min:1, max:12, divisions:11,
      activeColor:AppColors.blue, inactiveColor:AppColors.border,
      label:'${sem.toInt()}', onChanged:onSem),
  ]);
}

class _Step3 extends StatelessWidget {
  final TextEditingController emailCtrl, passCtrl, confCtrl;
  const _Step3({required this.emailCtrl,required this.passCtrl,required this.confCtrl});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
    Text('Account Setup', style:AppTextStyles.headlineLarge),
    const SizedBox(height:6),
    Text('Create your login credentials', style:AppTextStyles.bodyMedium),
    const SizedBox(height:24),
    AfosTextField(hint:'Email address', controller:emailCtrl,
      prefixIcon:Icons.email_outlined, keyboardType:TextInputType.emailAddress,
      validator:AppValidators.email),
    const SizedBox(height:16),
    AfosTextField(hint:'Password (min 8 chars)', controller:passCtrl,
      prefixIcon:Icons.lock_outline, obscure:true, validator:AppValidators.password),
    const SizedBox(height:16),
    AfosTextField(hint:'Confirm password', controller:confCtrl,
      prefixIcon:Icons.lock_outline, obscure:true,
      validator:(v)=>AppValidators.confirmPassword(v,passCtrl.text)),
  ]);
}
