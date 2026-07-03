import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/academic_repository.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../shared/extensions/context_ext.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/afos_text_field.dart';
import '../../../shared/widgets/glass_card.dart';
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
  final _academicRepo = AcademicRepository();
  int _step = 0;
  final _formKeys = [GlobalKey<FormState>(), GlobalKey<FormState>(), GlobalKey<FormState>()];
  final _nameCtrl = TextEditingController();
  final _idCtrl   = TextEditingController();
  final _emailCtrl= TextEditingController();
  final _passCtrl = TextEditingController();
  final _confCtrl = TextEditingController();
  final _batchCtrl = TextEditingController();
  final _sectionCtrl = TextEditingController();
  final _designationCtrl = TextEditingController();

  AccountType _accountType = AccountType.student;
  double _sem = 1;

  bool _loadingDepts = true;
  List<DepartmentOption> _departments = [];
  DepartmentOption? _selectedDept;
  List<ProgramOption> _programs = [];
  ProgramOption? _selectedProgram;
  bool _loadingPrograms = false;

  @override
  void initState() {
    super.initState();
    _loadDepartments();
  }

  Future<void> _loadDepartments() async {
    try {
      final depts = await _academicRepo.fetchDepartments();
      if(!mounted) return;
      setState(() { _departments = depts; _loadingDepts = false; });
    } catch(_) {
      if(!mounted) return;
      setState(() => _loadingDepts = false);
    }
  }

  Future<void> _onDeptChanged(DepartmentOption? d) async {
    setState(() { _selectedDept = d; _selectedProgram = null; _programs = []; _loadingPrograms = d != null; });
    if(d == null) return;
    try {
      final programs = await _academicRepo.fetchPrograms(d.id);
      if(!mounted) return;
      setState(() {
        _programs = programs;
        _selectedProgram = programs.isNotEmpty ? programs.first : null;
        _sem = 1;
        _loadingPrograms = false;
      });
    } catch(_) {
      if(!mounted) return;
      setState(() => _loadingPrograms = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _idCtrl.dispose();
    _emailCtrl.dispose(); _passCtrl.dispose(); _confCtrl.dispose();
    _batchCtrl.dispose(); _sectionCtrl.dispose(); _designationCtrl.dispose();
    super.dispose();
  }

  bool get _isStudent => _accountType == AccountType.student;

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    return BlocListener<AuthBloc, AuthState>(
      listener:(ctx,state) {
        if(state is AuthAuthenticated) {
          ctx.showSnack('Account created! Welcome to AFOS.');
          ctx.go('/home');
        }
        if(state is AuthEmailVerificationSent) {
          ctx.showSnack('Account created! Check your email to verify.');
          ctx.go('/auth/login');
        }
        if(state is AuthError) ctx.showSnack(state.message, isError:true);
      },
      child: Scaffold(
        backgroundColor: AppColors.surfaceOf(context),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title:Text('Create Account', style: AppTextStyles.headlineMed.copyWith(color: textPrimary)),
          leading:IconButton(icon:Icon(Icons.arrow_back, color: textPrimary),onPressed:()=>context.pop())),
        body: SafeArea(
          child: Padding(
            padding:const EdgeInsets.symmetric(horizontal:20, vertical:8),
            child: Column(children:[
              const SizedBox(height:8),
              _StepIndicator(step:_step)
                .animate().fadeIn(duration:300.ms).slideY(begin:-0.1,curve:Curves.easeOutCubic),
              const SizedBox(height:20),
              Expanded(
                child: GlassCard(
                  glowColor: AppColors.holoTeal,
                  padding: const EdgeInsets.all(20),
                  child: SingleChildScrollView(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds:320),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween<Offset>(begin: const Offset(0.06,0), end: Offset.zero).animate(anim),
                          child: child,
                        ),
                      ),
                      child: KeyedSubtree(
                        key: ValueKey(_step),
                        child: _step == 0
                          ? Form(key:_formKeys[0], child:_Step1(
                              nameCtrl:_nameCtrl, idCtrl:_idCtrl,
                              accountType:_accountType,
                              onAccountType:(t){ setState(()=>_accountType=t); },
                            ))
                          : _step == 1
                            ? Form(key:_formKeys[1], child:_Step2(
                                accountType:_accountType,
                                loadingDepts:_loadingDepts,
                                departments:_departments,
                                selectedDept:_selectedDept,
                                onDept:_onDeptChanged,
                                loadingPrograms:_loadingPrograms,
                                programs:_programs,
                                selectedProgram:_selectedProgram,
                                onProgram:(p){ setState(() { _selectedProgram = p; _sem = 1; }); },
                                batchCtrl:_batchCtrl,
                                sectionCtrl:_sectionCtrl,
                                designationCtrl:_designationCtrl,
                                sem:_sem,
                                onSem:(v){ setState(()=>_sem=v); },
                              ))
                            : Form(key:_formKeys[2], child:_Step3(emailCtrl:_emailCtrl,
                                passCtrl:_passCtrl, confCtrl:_confCtrl)),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height:16),
              BlocBuilder<AuthBloc,AuthState>(
                builder:(ctx,state) => Row(children:[
                  if(_step>0) Expanded(child: AfosButton(
                    label:'Back', outlined:true,
                    onTap:()=>setState(()=>_step--))),
                  if(_step>0) const SizedBox(width:12),
                  Expanded(child: AfosButton(
                    label: _step==2?'Create Account':'Next →',
                    loading: state is AuthLoading,
                    onTap:(){
                      if(_step==1 && _isStudent && _selectedDept==null) {
                        ctx.showSnack('Select a department', isError:true);
                        return;
                      }
                      if(_formKeys[_step].currentState!.validate()) {
                        if(_step<2) { setState(()=>_step++); }
                        else {
                          ctx.read<AuthBloc>().add(AuthRegisterRequested(
                            email:_emailCtrl.text.trim(),
                            password:_passCtrl.text,
                            studentId:_idCtrl.text.trim(),
                            fullName:_nameCtrl.text.trim(),
                            department:_selectedDept?.code ?? '',
                            semester:_isStudent ? _sem.toInt() : 1,
                            accountType: _isStudent ? 'student' : 'teacher',
                            programId: _isStudent ? _selectedProgram?.id : null,
                            batch: _isStudent && _batchCtrl.text.trim().isNotEmpty ? _batchCtrl.text.trim() : null,
                            section: _isStudent && _sectionCtrl.text.trim().isNotEmpty ? _sectionCtrl.text.trim() : null,
                            designation: !_isStudent && _designationCtrl.text.trim().isNotEmpty ? _designationCtrl.text.trim() : null,
                          ));
                        }
                      }
                    },
                  )),
                ]),
              ),
              const SizedBox(height:12),
            ]),
          ),
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
    final textSecondary = AppColors.textSecondaryOf(context);
    final border = AppColors.borderOf(context);
    return Row(children: List.generate(3,(i) => Expanded(child: Row(children:[
      AnimatedContainer(
        duration: const Duration(milliseconds:250),
        curve: Curves.easeOutCubic,
        width:28,height:28,
        decoration:BoxDecoration(
          shape:BoxShape.circle,
          color: i<=step ? AppColors.holoBlue : Colors.transparent,
          border:Border.all(color:i<=step?AppColors.holoBlue:border),
          boxShadow: i<=step ? [
            BoxShadow(color: AppColors.holoBlue.withOpacity(0.35), blurRadius:10, spreadRadius:0),
          ] : null,
        ),
        alignment:Alignment.center,
        child: i<step
          ? const Icon(Icons.check,size:14,color:Colors.white)
          : Text('${i+1}',style:TextStyle(fontSize:12,
              color:i==step?Colors.white:textSecondary,fontWeight:FontWeight.w600)),
      ),
      if(i<2) Expanded(child:AnimatedContainer(
        duration: const Duration(milliseconds:250),
        height:1,
        color:i<step?AppColors.holoBlue:border)),
    ]))));
  }
}

class _AccountTypeToggle extends StatelessWidget {
  final AccountType value;
  final ValueChanged<AccountType> onChanged;
  const _AccountTypeToggle({required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final textSecondary = AppColors.textSecondaryOf(context);
    final border = AppColors.borderOf(context);
    Widget option(String label, AccountType type) {
      final selected = value == type;
      return Expanded(child: GestureDetector(
        onTap: () => onChanged(type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds:220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical:12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.holoBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? AppColors.holoBlue : border, width:0.8),
          ),
          child: Text(label, style: TextStyle(
            color: selected ? Colors.white : textSecondary,
            fontWeight: FontWeight.w600, fontSize: 13)),
        ),
      ));
    }
    return Row(children: [
      option('Student', AccountType.student),
      const SizedBox(width:12),
      option('Teacher / Staff', AccountType.teacher),
    ]);
  }
}

class _Step1 extends StatelessWidget {
  final TextEditingController nameCtrl, idCtrl;
  final AccountType accountType;
  final ValueChanged<AccountType> onAccountType;
  const _Step1({required this.nameCtrl, required this.idCtrl,
    required this.accountType, required this.onAccountType});
  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    return Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
      Text('Personal Info', style:AppTextStyles.headlineLarge.copyWith(color: textPrimary)),
      const SizedBox(height:6),
      Text('Tell us who you are', style:AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
      const SizedBox(height:24),
      _AccountTypeToggle(value:accountType, onChanged:onAccountType),
      const SizedBox(height:24),
      AfosTextField(hint:'Full Name', controller:nameCtrl, prefixIcon:Icons.person_outline,
        validator:(v)=>AppValidators.required(v,f:'Full name')),
      const SizedBox(height:16),
      AfosTextField(
        hint: accountType==AccountType.student ? 'Student ID (e.g. 221-15-5678)' : 'Employee ID',
        controller:idCtrl,
        prefixIcon:Icons.badge_outlined,
        validator:(v)=>AppValidators.studentId(v, type:accountType),
        keyboardType: accountType==AccountType.student ? TextInputType.number : TextInputType.text),
    ]);
  }
}

class _Step2 extends StatelessWidget {
  final AccountType accountType;
  final bool loadingDepts;
  final List<DepartmentOption> departments;
  final DepartmentOption? selectedDept;
  final ValueChanged<DepartmentOption?> onDept;
  final bool loadingPrograms;
  final List<ProgramOption> programs;
  final ProgramOption? selectedProgram;
  final ValueChanged<ProgramOption?> onProgram;
  final TextEditingController batchCtrl, sectionCtrl, designationCtrl;
  final double sem;
  final ValueChanged<double> onSem;
  const _Step2({
    required this.accountType, required this.loadingDepts, required this.departments,
    required this.selectedDept, required this.onDept,
    required this.loadingPrograms, required this.programs,
    required this.selectedProgram, required this.onProgram,
    required this.batchCtrl, required this.sectionCtrl, required this.designationCtrl,
    required this.sem, required this.onSem,
  });

  InputDecoration _decoration(BuildContext context, String hint, IconData icon) => InputDecoration(
    hintText:hint,
    hintStyle: TextStyle(color: AppColors.textSecondaryOf(context)),
    prefixIcon:Icon(icon, color:AppColors.textSecondaryOf(context), size:20),
    filled:true, fillColor:AppColors.glassFill(context),
    border:OutlineInputBorder(borderRadius:BorderRadius.circular(12),
      borderSide:BorderSide(color:AppColors.borderOf(context),width:0.5)),
    enabledBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(12),
      borderSide:BorderSide(color:AppColors.borderOf(context),width:0.5)),
    focusedBorder:OutlineInputBorder(borderRadius:BorderRadius.circular(12),
      borderSide:const BorderSide(color:AppColors.holoBlue,width:1.2)),
  );

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    final isStudent = accountType == AccountType.student;
    final semRange = selectedProgram?.semesterRange ?? 12;
    return Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
      Text('Academic Info', style:AppTextStyles.headlineLarge.copyWith(color: textPrimary)),
      const SizedBox(height:6),
      Text(isStudent ? 'Your department and program' : 'Your department', style:AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
      const SizedBox(height:24),
      if(loadingDepts)
        const Center(child:Padding(padding:EdgeInsets.all(16), child:CircularProgressIndicator()))
      else
        DropdownButtonFormField<DepartmentOption>(
          value: selectedDept,
          decoration: _decoration(context, 'Department', Icons.school_outlined),
          dropdownColor: AppColors.surfaceOf(context),
          style: TextStyle(color:textPrimary),
          items: departments.map((d)=>DropdownMenuItem(value:d,child:Text(d.name))).toList(),
          onChanged: onDept,
        ),
      const SizedBox(height:16),
      if(isStudent) ...[
        if(loadingPrograms)
          const Center(child:Padding(padding:EdgeInsets.all(16), child:CircularProgressIndicator()))
        else if(selectedDept != null)
          DropdownButtonFormField<ProgramOption>(
            value: selectedProgram,
            decoration: _decoration(context, 'Program', Icons.menu_book_outlined),
            dropdownColor: AppColors.surfaceOf(context),
            style: TextStyle(color:textPrimary),
            items: programs.map((p)=>DropdownMenuItem(value:p,child:Text(p.name))).toList(),
            onChanged: onProgram,
          ),
        const SizedBox(height:16),
        Row(children:[
          Expanded(child: AfosTextField(hint:'Batch (e.g. 61)', controller:batchCtrl,
            prefixIcon:Icons.groups_outlined,
            validator:(v)=>AppValidators.required(v,f:'Batch'))),
          const SizedBox(width:12),
          Expanded(child: AfosTextField(hint:'Section (e.g. A)', controller:sectionCtrl,
            prefixIcon:Icons.class_outlined,
            validator:(v)=>AppValidators.required(v,f:'Section'))),
        ]),
        const SizedBox(height:24),
        Text('Semester: ${sem.toInt()} of $semRange', style:AppTextStyles.titleMedium.copyWith(color: textPrimary)),
        Slider(value: sem.clamp(1, semRange.toDouble()), min:1, max:semRange.toDouble(),
          divisions: semRange>1 ? semRange-1 : 1,
          activeColor:AppColors.holoBlue, inactiveColor:AppColors.borderOf(context),
          label:'${sem.toInt()}', onChanged:onSem),
      ] else
        AfosTextField(hint:'Designation (e.g. Lecturer)', controller:designationCtrl,
          prefixIcon:Icons.work_outline,
          validator:(v)=>AppValidators.required(v,f:'Designation')),
    ]);
  }
}

class _Step3 extends StatelessWidget {
  final TextEditingController emailCtrl, passCtrl, confCtrl;
  const _Step3({required this.emailCtrl,required this.passCtrl,required this.confCtrl});
  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    return Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
      Text('Account Setup', style:AppTextStyles.headlineLarge.copyWith(color: textPrimary)),
      const SizedBox(height:6),
      Text('Create your login credentials', style:AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
      const SizedBox(height:24),
      AfosTextField(hint:'University email (edu.bd)', controller:emailCtrl,
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
}
