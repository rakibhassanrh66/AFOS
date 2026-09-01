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
/// [mailReason] says WHY there is no mail, when [mailFailed] is true:
///   'quota'    — today's provider allowance is spent. Ours, temporary, and
///                nothing is wrong with the applicant's address.
///   'provider' — the provider refused this specific address.
/// The distinction is not pedantry: telling someone to re-check their spelling
/// when our own allowance ran out is how you lose an applicant who did nothing
/// wrong. Null when the mail went out normally.
///
/// [supportEmail] / [supportTelegram] come from the SERVER with the response
/// rather than being compiled into the app, so support contacts can change
/// without shipping a release to every installed phone.
class AuthRegistrationCodeSent extends AuthState {
  final String email;
  final int resendAfterSeconds;
  final String lane;
  final bool manualFallback;
  final bool mailFailed;
  final String? mailReason;
  final String? supportEmail;
  final String? supportTelegram;
  AuthRegistrationCodeSent(this.email, {this.resendAfterSeconds = 60, this.lane = 'inline',
      this.manualFallback = true, this.mailFailed = false, this.mailReason,
      this.supportEmail, this.supportTelegram});
}
class AuthPasswordResetSent  extends AuthState {}
