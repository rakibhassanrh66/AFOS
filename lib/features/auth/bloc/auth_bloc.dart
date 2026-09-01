import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/auth/permission_session.dart';
import '../../../core/auth/role_session.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../core/utils/pending_credentials_store.dart';
import '../data/repositories/auth_repository.dart';
import 'auth_event.dart';
import 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository _repo;
  AuthBloc(this._repo) : super(AuthInitial()) {
    on<AuthLoginRequested>(_onLogin);
    on<AuthRegisterRequested>(_onRegister);
    on<AuthLogoutRequested>(_onLogout);
    on<AuthCheckRequested>(_onCheck);
    on<AuthForgotPassword>(_onForgot);
  }

  Future<void> _onLogin(AuthLoginRequested e, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final user = await _repo.signIn(e.email, e.password);
      RoleSession.set(user.role, profileCompleted: user.profileCompleted);
      emit(AuthAuthenticated(user));
    } catch(err) {
      emit(AuthError(friendlyError(err)));
    }
  }

  Future<void> _onRegister(AuthRegisterRequested e, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      // Stages the signup and sends the code. NOTHING is created yet — no
      // auth user, no profile, no student/teacher/staff row. That is the whole
      // point of the change: auth.signUp used to create a confirmed account
      // before anyone had proved they own the mailbox.
      final res = await _repo.requestRegistration(
        email: e.email,
        password: e.password,
        fullName: e.fullName,
        studentId: e.studentId,
        department: e.department,
        semester: e.semester,
        accountType: e.accountType,
        gender: e.gender,
        programId: e.programId,
        batch: e.batch,
        section: e.section,
        designation: e.designation,
        staffCategory: e.staffCategory,
        office: e.office,
      );
      // Held so the verify screen can sign in the moment the code is accepted,
      // rather than making someone who just typed a password type it again.
      await PendingCredentialsStore.save(e.email, e.password);
      emit(AuthRegistrationCodeSent(
        e.email,
        resendAfterSeconds: (res['resendAfterSeconds'] as num?)?.toInt() ?? 60,
        lane: res['lane'] as String? ?? 'inline',
        // Defaults ON when the server omits it, which is what an older
        // deployed function does. Hiding the only route a stuck applicant has
        // is the worse failure of the two.
        manualFallback: res['manualFallback'] as bool? ?? true,
        mailFailed: res['mailFailed'] as bool? ?? false,
        // All three are null on an older deployed function, and every reader
        // treats null as "say the generic thing" — so a version skew degrades
        // to the previous copy rather than rendering "null" at an applicant.
        mailReason: res['mailReason'] as String?,
        supportEmail: res['supportEmail'] as String?,
        supportTelegram: res['supportTelegram'] as String?,
      ));
    } catch(err) {
      emit(AuthError(friendlyError(err)));
    }
  }

  Future<void> _onLogout(AuthLogoutRequested e, Emitter<AuthState> emit) async {
    await _repo.signOut();
    RoleSession.clear();
    PermissionSession.clear();
    emit(AuthUnauthenticated());
  }

  Future<void> _onCheck(AuthCheckRequested e, Emitter<AuthState> emit) async {
    final user = await _repo.getCurrentUser();
    if (user != null) {
      RoleSession.set(user.role, profileCompleted: user.profileCompleted);
      emit(AuthAuthenticated(user));
    } else {
      RoleSession.clear();
      PermissionSession.clear();
      emit(AuthUnauthenticated());
    }
  }

  Future<void> _onForgot(AuthForgotPassword e, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      // Was auth.resetPasswordForEmail — Supabase's capped built-in mailer,
      // sending a link-only, GET-consumed token. University mail scanners
      // fetch every URL in a message, which spent that single-use token before
      // the student ever clicked, so reset failed on the FIRST attempt with a
      // misleading "link expired". Now a typed code, which no scanner can
      // consume, over the same provider the verification mail uses.
      await _repo.requestPasswordResetCode(e.email);
      emit(AuthPasswordResetSent());
    } catch(err) {
      emit(AuthError(friendlyError(err)));
    }
  }
}
