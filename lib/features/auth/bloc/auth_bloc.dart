import 'package:flutter_bloc/flutter_bloc.dart';
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
      if(user != null) {
        emit(AuthAuthenticated(user));
      } else {
        emit(AuthEmailVerificationSent());
      }
    } catch(err) {
      emit(AuthError(err.toString().replaceAll('Exception: ','')));
    }
  }

  Future<void> _onLogout(AuthLogoutRequested e, Emitter<AuthState> emit) async {
    await _repo.signOut();
    emit(AuthUnauthenticated());
  }

  Future<void> _onCheck(AuthCheckRequested e, Emitter<AuthState> emit) async {
    final user = await _repo.getCurrentUser();
    if(user!=null) emit(AuthAuthenticated(user)); else emit(AuthUnauthenticated());
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
