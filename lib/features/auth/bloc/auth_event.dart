abstract class AuthEvent {}
class AuthLoginRequested extends AuthEvent {
  final String email, password;
  AuthLoginRequested(this.email, this.password);
}
class AuthRegisterRequested extends AuthEvent {
  final String email, password, studentId, fullName, department;
  final int semester;
  AuthRegisterRequested({required this.email, required this.password,
    required this.studentId, required this.fullName,
    required this.department, required this.semester});
}
class AuthLogoutRequested    extends AuthEvent {}
class AuthCheckRequested     extends AuthEvent {}
class AuthForgotPassword     extends AuthEvent { final String email; AuthForgotPassword(this.email); }
