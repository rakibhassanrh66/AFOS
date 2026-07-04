import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/auth/role_session.dart';
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
      emit(AuthError(err.toString().replaceAll('Exception: ','')));
    }
  }

  Future<void> _onRegister(AuthRegisterRequested e, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final user = await _repo.signUp(
        email: e.email,
        password: e.password,
        fullName: e.fullName,
        studentId: e.studentId,
        department: e.department,
        semester: e.semester,
        accountType: e.accountType,
        programId: e.programId,
        batch: e.batch,
        section: e.section,
        designation: e.designation,
      );
      // Regardless of whether Supabase returned a session immediately,
      // route the user through a real login step: stash the credentials
      // for the login screen to prefill, sign the auto-created session
      // back out (so the router's redirect doesn't bounce /auth/login
      // straight back to /home), then land on login.
      await PendingCredentialsStore.save(e.email, e.password);
      if (user != null) {
        await _repo.signOut();
      }
      emit(AuthRegistrationSuccess());
    } catch(err) {
      emit(AuthError(err.toString().replaceAll('Exception: ','')));
    }
  }

  Future<void> _onLogout(AuthLogoutRequested e, Emitter<AuthState> emit) async {
    await _repo.signOut();
    RoleSession.clear();
    emit(AuthUnauthenticated());
  }

  Future<void> _onCheck(AuthCheckRequested e, Emitter<AuthState> emit) async {
    final user = await _repo.getCurrentUser();
    if (user != null) {
      RoleSession.set(user.role, profileCompleted: user.profileCompleted);
      emit(AuthAuthenticated(user));
    } else {
      RoleSession.clear();
      emit(AuthUnauthenticated());
    }
  }

  Future<void> _onForgot(AuthForgotPassword e, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      await _repo.forgotPassword(e.email);
      emit(AuthPasswordResetSent());
    } catch(err) {
      emit(AuthError(err.toString()));
    }
  }
}
