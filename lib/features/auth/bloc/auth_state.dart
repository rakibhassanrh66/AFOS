import '../../../shared/models/user_model.dart';
abstract class AuthState {}
class AuthInitial            extends AuthState {}
class AuthLoading            extends AuthState {}
class AuthAuthenticated      extends AuthState { final UserModel user; AuthAuthenticated(this.user); }
class AuthUnauthenticated    extends AuthState {}
class AuthError              extends AuthState { final String message; AuthError(this.message); }
class AuthRegistrationSuccess  extends AuthState {}
/// The signup is staged and a confirmation code is on its way. No account
/// exists yet — it is created only when the code or link comes back.
/// [lane] is 'inline' when the mail was handed to the provider during the
/// request, or 'queued' when the per-minute budget was full and the outbox
/// took it, so the screen can say something honest about timing.
/// [manualFallback] mirrors app_config.manual_approval_fallback: whether the
/// verify screen offers "I never got the email" as a route to human approval.
/// Server-decided rather than a client constant, so it can be switched off the
/// day a verified sending domain makes it unnecessary — without a redeploy.
/// [mailFailed] is the provider permanently refusing the address. The signup
/// IS still staged — that is the whole reason this is not an error state — so
/// the screen leads with manual approval rather than telling someone to check
/// an inbox nothing was sent to.
class AuthRegistrationCodeSent extends AuthState {
  final String email;
  final int resendAfterSeconds;
  final String lane;
  final bool manualFallback;
  final bool mailFailed;
  AuthRegistrationCodeSent(this.email, {this.resendAfterSeconds = 60, this.lane = 'inline',
      this.manualFallback = true, this.mailFailed = false});
}
class AuthPasswordResetSent  extends AuthState {}
