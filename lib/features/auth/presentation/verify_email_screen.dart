import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/motion.dart';
import '../../../core/auth/role_session.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../core/utils/otp_code.dart';
import '../../../core/utils/pending_credentials_store.dart';
import '../../../core/utils/responsive.dart';
import '../../../shared/extensions/context_ext.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/glass_card.dart';
import '../data/repositories/auth_repository.dart';
import 'widgets/auth_brand_panel.dart';

/// Proves the user controls the DIU mailbox they registered with.
///
/// Reached two ways, both landing on the same server-side row:
///   - from the signup wizard, with `extra['email']`, to type the 6-digit code
///   - from the emailed link, as `/auth/verify?token=…`
///
/// The link path does NOT auto-redeem on arrival by accident of navigation —
/// it redeems by POSTing to register-verify. That distinction is the fix for
/// the defect in the old password-reset flow: institutional mail scanners
/// fetch every URL in a message, and a token spent by a GET is burned before
/// the student ever clicks.
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key, this.email, this.token, this.resendAfterSeconds = 60,
      this.lane = 'inline', this.manualFallback = true, this.mailFailed = false,
      this.mailReason, this.supportEmail, this.supportTelegram,
      this.expiresInSeconds = 600});

  final String? email;
  final String? token;
  final int resendAfterSeconds;
  final String lane;

  /// The server's own window, not a second copy of it. See
  /// AuthRegistrationCodeSent.expiresInSeconds -- the sentence below the code
  /// field used to hardcode "10 minutes" while the server decided the real
  /// number, so raising the window would have left the screen lying.
  final int expiresInSeconds;

  /// Mirrors app_config.manual_approval_fallback. While mail delivery is
  /// unreliable this offers the only route an applicant has when no code ever
  /// arrives; once a verified sending domain is in place it is switched off
  /// server-side and this stops being offered.
  final bool manualFallback;

  /// The provider permanently refused the address, so no code is coming. The
  /// signup is still staged server-side — that is why this is a state and not
  /// an error — so the screen leads with manual approval instead of telling
  /// someone to check an inbox nothing was sent to.
  final bool mailFailed;

  /// Why there is no mail: 'quota' (our daily allowance is spent) or
  /// 'provider' (this address was refused). Drives which copy is shown, because
  /// the two need opposite reassurance — one is entirely our fault and
  /// temporary, the other may be a typo in their address.
  final String? mailReason;

  /// Support contacts, supplied by the server so they can change without an
  /// app release. Null falls back to showing no contact block at all rather
  /// than a stale address nobody reads.
  final String? supportEmail;
  final String? supportTelegram;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final _repo = AuthRepository();
  final _codeCtrl = TextEditingController();
  final _codeFocus = FocusNode();

  bool _busy = false;
  String? _error;
  int _resendIn = 0;
  Timer? _ticker;

  /// The applicant has raised their hand for human review. Kept in this screen
  /// rather than routed away to a new page: the code stays redeemable while
  /// they wait, so they must be able to come back to the field.
  bool _reviewRequested = false;
  bool _reviewBusy = false;

  bool get _isLinkPath => (widget.token ?? '').isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (_isLinkPath) {
      // Redeem immediately: the person has already expressed intent by tapping
      // the button in their mail, so making them press another one is friction
      // with no security value — the token is the proof either way.
      WidgetsBinding.instance.addPostFrameCallback((_) => _verifyWithToken());
    } else {
      _startResendCountdown(widget.resendAfterSeconds);
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _codeCtrl.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  void _startResendCountdown(int seconds) {
    _ticker?.cancel();
    setState(() => _resendIn = seconds);
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _resendIn--);
      if (_resendIn <= 0) t.cancel();
    });
  }

  Future<void> _verifyWithToken() async {
    setState(() { _busy = true; _error = null; });
    try {
      final res = await _repo.verifyRegistrationToken(widget.token!);
      await _onVerified(res);
    } catch (e) {
      if (mounted) setState(() { _busy = false; _error = friendlyError(e); });
    }
  }

  Future<void> _verifyWithCode() async {
    // Without an address there is nothing to verify against, and the old
    // `widget.email!` was a null-check crash waiting for anyone who reopened
    // the app on this route — the `extra` carrying the email does not survive
    // a reload, so the screen can legitimately exist with neither argument.
    if (widget.email == null) {
      setState(() => _error = 'Start again from the sign-up form to get a new code.');
      return;
    }
    final code = _codeCtrl.text.replaceAll(RegExp(r'\D'), '');
    if (code.length != 6) {
      setState(() => _error = 'Enter all 6 digits.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final res = await _repo.verifyRegistration(email: widget.email!, code: code);
      await _onVerified(res);
    } catch (e) {
      if (mounted) {
        setState(() { _busy = false; _error = friendlyError(e); });
        AppHaptics.warning();
        _codeCtrl.clear();
        _codeFocus.requestFocus();
      }
    }
  }

  /// The account now exists. Sign in with the credentials held from the wizard
  /// so nobody retypes a password they chose ninety seconds ago — and so the
  /// password is proven to work before we tell them they're done.
  Future<void> _onVerified(Map<String, dynamic> res) async {
    AppHaptics.success();
    final creds = await PendingCredentialsStore.consume();

    if (creds != null) {
      try {
        await _repo.signIn(creds.$1, creds.$2);
        // Cleared rather than set, so the router refetches role, completion
        // and verification state straight from the database. The approval
        // policy is evaluated server-side and this screen should not try to
        // predict its outcome.
        RoleSession.clear();
        if (mounted) context.go('/home');
        return;
      } catch (_) {
        // Falls through to the login screen — the account is real either way,
        // and a failed auto-sign-in must not read as a failed verification.
      }
    }

    if (mounted) {
      context.showSnack(res['autoApproved'] == true
          ? 'Email confirmed. Sign in to continue.'
          : 'Email confirmed. Your account is waiting for approval.');
      context.go('/auth/login');
    }
  }

  Future<void> _resend() async {
    context.showSnack('Start again from the sign-up form to get a new code.');
    context.go('/auth/register');
  }

  /// Pulls the code out of the clipboard and submits it in one tap.
  ///
  /// WHY A BUTTON AND NOT AN AUTOMATIC SNIFF. Reading the clipboard on Android
  /// 12+ raises a system toast — "AFOS pasted from your clipboard" — every
  /// single time. Checking silently on open, and again on every resume, would
  /// fire that toast repeatedly at someone in the middle of signing up and
  /// read as an app going through their clipboard uninvited. A button makes
  /// the read something they asked for, so the toast is an expected
  /// confirmation instead of an accusation.
  ///
  /// Parsing lives in [extractOtpCode], which tolerates the separators a mail
  /// client puts on the clipboard — including `4 8 2 9 1 3` from selecting the
  /// email's per-digit chips — while still refusing to slice six digits out of
  /// a longer number. See its tests; that tolerance is what let the email be
  /// designed properly.
  Future<void> _pasteCode() async {
    String? found;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      found = extractOtpCode(data?.text);
    } catch (_) {
      // A denied or empty clipboard is not an error worth a red banner.
    }
    if (!mounted) return;
    if (found == null) {
      context.showSnack('No 6-digit code found in your clipboard. Copy it from the email first.');
      return;
    }
    setState(() {
      _codeCtrl.text = found!;
      _error = null;
    });
    AppHaptics.selection();
    // Straight through to verification: they copied a code and pressed paste,
    // so making them reach for a second button is the friction this removes.
    await _verifyWithCode();
  }

  /// The escape hatch for someone no code will ever reach.
  ///
  /// The server answers identically whether or not a staged signup exists for
  /// this address — that is deliberate anti-enumeration — so this screen must
  /// NOT claim the request definitely landed on a real row. It says what was
  /// sent, not what was found.
  Future<void> _requestManualApproval() async {
    if (widget.email == null) return;
    setState(() { _reviewBusy = true; _error = null; });
    try {
      await _repo.requestManualApproval(widget.email!);
      AppHaptics.success();
      if (mounted) setState(() { _reviewBusy = false; _reviewRequested = true; });
    } catch (e) {
      if (mounted) {
        setState(() { _reviewBusy = false; _error = friendlyError(e); });
        AppHaptics.warning();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);

    return Scaffold(
      backgroundColor: AppColors.surfaceOf(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textPrimary),
          onPressed: () => context.go('/auth/login'),
        ),
      ),
      body: LayoutBuilder(builder: (context, outer) {
        final pane = VerifyEmailPane(
          isLinkPath: _isLinkPath,
          email: widget.email,
          lane: widget.lane,
          busy: _busy,
          error: _error,
          resendIn: _resendIn,
          codeCtrl: _codeCtrl,
          codeFocus: _codeFocus,
          textPrimary: textPrimary,
          textSecondary: textSecondary,
          onSubmit: _verifyWithCode,
          onResend: _resendIn > 0 ? null : _resend,
          onRetryToken: _verifyWithToken,
          onPasteCode: _pasteCode,
          manualFallback: widget.manualFallback,
          mailFailed: widget.mailFailed,
          mailReason: widget.mailReason,
          supportEmail: widget.supportEmail,
          supportTelegram: widget.supportTelegram,
          expiresInSeconds: widget.expiresInSeconds,
          reviewBusy: _reviewBusy,
          reviewRequested: _reviewRequested,
          onRequestReview: _requestManualApproval,
          onBackToCode: () => setState(() => _reviewRequested = false),
          cardMaxWidth: outer.maxWidth >= Responsive.mediumBreakpoint ? 460 : double.infinity,
        );

        if (outer.maxWidth >= Responsive.expandedBreakpoint) {
          return Row(children: [
            const Expanded(flex: 5, child: AuthBrandPanel()),
            Expanded(flex: 4, child: pane),
          ]);
        }
        return pane;
      }),
    );
  }
}

class VerifyEmailPane extends StatelessWidget {
  const VerifyEmailPane({
    required this.isLinkPath,
    required this.email,
    required this.lane,
    required this.busy,
    required this.error,
    required this.resendIn,
    required this.codeCtrl,
    required this.codeFocus,
    required this.textPrimary,
    required this.textSecondary,
    required this.onSubmit,
    required this.onResend,
    required this.onRetryToken,
    required this.onPasteCode,
    required this.manualFallback,
    required this.mailFailed,
    required this.mailReason,
    required this.supportEmail,
    required this.supportTelegram,
    required this.expiresInSeconds,
    required this.reviewBusy,
    required this.reviewRequested,
    required this.onRequestReview,
    required this.onBackToCode,
    required this.cardMaxWidth,
  });

  final bool isLinkPath;
  final String? email;
  final String lane;
  final bool busy;
  final String? error;
  final int resendIn;
  final TextEditingController codeCtrl;
  final FocusNode codeFocus;
  final Color textPrimary;
  final Color textSecondary;
  final VoidCallback onSubmit;
  final VoidCallback? onResend;
  final VoidCallback onRetryToken;
  final VoidCallback onPasteCode;
  final bool manualFallback;
  final bool mailFailed;
  final String? mailReason;
  final String? supportEmail;
  final String? supportTelegram;
  final int expiresInSeconds;
  final bool reviewBusy;
  final bool reviewRequested;
  final VoidCallback onRequestReview;
  final VoidCallback onBackToCode;
  final double cardMaxWidth;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.fromSTEB(24, 8, 24, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: cardMaxWidth),
            child: GlassCard(
              glowColor: AppColors.holoTeal,
              animated: true,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  // Four states. The 'lost' one is reached by anyone who lands
                  // on /auth/verify with neither a token nor the email in
                  // `extra` — a reload, a bookmark, a shared URL — and used to
                  // render the code form with a dangling "sent a code to ."
                  // and crash on submit. The 'submitted' one is where someone
                  // waits after asking for a human, and is checked BEFORE the
                  // code form so the answer replaces the question.
                  children: isLinkPath
                      ? _linkBody(context)
                      : email == null
                          ? _lostBody(context)
                          : reviewRequested
                              ? _submittedBody(context)
                              : mailFailed
                                  ? _mailFailedBody(context)
                                  : _codeBody(context),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _badge(BuildContext context, IconData icon, Color tint) => Container(
        width: 56, height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: tint.withValues(alpha: 0.12),
          border: Border.all(color: tint.withValues(alpha: 0.4)),
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: tint, size: 28),
      ).animate()
          .scale(duration: AppMotion.durationOf(context, AppMotion.slow), curve: AppMotion.standard)
          .fadeIn(duration: AppMotion.durationOf(context, AppMotion.base));

  List<Widget> _linkBody(BuildContext context) => [
        _badge(context, error == null ? Icons.verified_outlined : Icons.error_outline,
            error == null ? AppColors.holoTeal : AppColors.red),
        const SizedBox(height: 24),
        Text(error == null ? 'Confirming your account' : 'That link didn\'t work',
            style: AppTextStyles.displayMedium.copyWith(color: textPrimary)),
        const SizedBox(height: 8),
        Text(
          // The server's rejection is deliberately one generic string for both
          // redemption paths (so it cannot be used to tell them apart), but on
          // this screen we KNOW it was a link — and "That link didn't work"
          // above "That code is invalid" reads like two different failures.
          error == null
              ? 'One moment — we\'re checking the link from your email.'
              : 'This link is invalid or has expired. Ask for a new one and use '
                  'the most recent email.',
          style: AppTextStyles.bodyMedium.copyWith(color: error == null ? textSecondary : AppColors.red),
        ),
        const SizedBox(height: 24),
        if (busy)
          const Center(child: Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.4)),
          ))
        else if (error != null) ...[
          AfosButton(label: 'Try again', onTap: onRetryToken),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: () => context.go('/auth/register'),
              child: Text('Start over', style: TextStyle(color: textSecondary)),
            ),
          ),
        ],
      ];

  /// No token, no address — nothing this screen can act on. Says so plainly
  /// and offers the only route forward, instead of presenting a code field
  /// that cannot succeed.
  List<Widget> _lostBody(BuildContext context) => [
        _badge(context, Icons.link_off_rounded, AppColors.amber),
        const SizedBox(height: 24),
        Text('Pick up where you left off',
            style: AppTextStyles.displayMedium.copyWith(color: textPrimary)),
        const SizedBox(height: 8),
        Text(
          'We can\'t tell which sign-up this is. Start the form again and we\'ll '
          'send a fresh code — nothing you entered has been lost from your side.',
          style: AppTextStyles.bodyMedium.copyWith(color: textSecondary),
        ),
        const SizedBox(height: 24),
        AfosButton(label: 'Back to sign up', onTap: () => context.go('/auth/register')),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: () => context.go('/auth/login'),
            child: Text('I already have an account', style: TextStyle(color: textSecondary)),
          ),
        ),
      ];

  List<Widget> _codeBody(BuildContext context) => [
        _badge(context, Icons.mark_email_unread_outlined, AppColors.holoTeal),
        const SizedBox(height: 24),
        Text('Check your email',
            style: AppTextStyles.displayMedium.copyWith(color: textPrimary))
            .animate(delay: AppMotion.sequenceDelay(context, 3))
            .fadeIn(duration: AppMotion.durationOf(context, AppMotion.base))
            .slideX(begin: -0.06, curve: AppMotion.standard),
        const SizedBox(height: 8),
        RichText(
          text: TextSpan(
            style: AppTextStyles.bodyMedium.copyWith(color: textSecondary),
            children: [
              const TextSpan(text: 'We sent a 6-digit code to '),
              TextSpan(text: email ?? '', style: TextStyle(color: textPrimary, fontWeight: FontWeight.w600)),
              const TextSpan(text: '. Enter it below, or tap the button in the email.'),
            ],
          ),
        ),
        // Honest about the overflow lane rather than showing a spinner that
        // implies the mail is already in flight when it is sitting in a queue.
        if (lane == 'queued') ...[
          const SizedBox(height: 12),
          Text('We\'re sending a lot of mail right now, so this one may take an extra moment.',
              style: AppTextStyles.labelSmall.copyWith(color: AppColors.amber)),
        ],
        const SizedBox(height: 28),

        // One field rather than six boxes, deliberately: six separate inputs
        // break paste, break one-time-code autofill, and are a nightmare for
        // screen readers. This keeps all three and still reads as a code.
        TextField(
          controller: codeCtrl,
          focusNode: codeFocus,
          autofocus: true,
          enabled: !busy,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.oneTimeCode],
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
          textAlign: TextAlign.center,
          style: AppTextStyles.displayMedium.copyWith(
            color: textPrimary, letterSpacing: 14, fontFeatures: const [FontFeature.tabularFigures()],
          ),
          decoration: InputDecoration(
            counterText: '',
            hintText: '······',
            hintStyle: AppTextStyles.displayMedium.copyWith(color: textSecondary.withValues(alpha: 0.35), letterSpacing: 14),
            filled: true,
            fillColor: AppColors.surfaceOf(context).withValues(alpha: 0.5),
            contentPadding: const EdgeInsets.symmetric(vertical: 18),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: textSecondary.withValues(alpha: 0.25)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.holoTeal, width: 1.6),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.red),
            ),
          ),
          onChanged: (v) {
            // Submits itself the instant the sixth digit lands — including on
            // an autofilled paste — so nobody types a full code and then hunts
            // for a button.
            if (v.replaceAll(RegExp(r'\D'), '').length == 6 && !busy) onSubmit();
          },
          onSubmitted: (_) => onSubmit(),
        ),

        // ONE TAP FROM THE EMAIL TO SIGNED IN.
        //
        // The real friction in a code flow is not typing six digits, it is the
        // trip: open mail, select the code without grabbing the words around
        // it, switch apps, long-press the field, find Paste. This collapses all
        // of it — copy anything containing the code (the whole line is fine)
        // and press once. It fills AND submits.
        //
        // No clipboard is read until this is pressed; see _pasteCode for why
        // that matters on Android 12+.
        const SizedBox(height: 10),
        Center(
          child: TextButton.icon(
            onPressed: busy ? null : onPasteCode,
            icon: const Icon(Icons.content_paste_rounded, size: 16),
            label: const Text('Paste code from email'),
            style: TextButton.styleFrom(foregroundColor: AppColors.holoTeal),
          ),
        ),

        if (error != null) ...[
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.error_outline, color: AppColors.red, size: 16),
            const SizedBox(width: 6),
            Expanded(child: Text(error!, style: AppTextStyles.labelSmall.copyWith(color: AppColors.red))),
          ]),
        ],

        const SizedBox(height: 20),
        AfosButton(label: 'Confirm account', loading: busy, onTap: onSubmit),
        const SizedBox(height: 12),

        Center(
          child: TextButton(
            onPressed: onResend,
            child: Text(
              resendIn > 0 ? 'Resend available in ${resendIn}s' : 'Didn\'t get it? Start again',
              style: TextStyle(color: resendIn > 0 ? textSecondary : AppColors.holoBlue),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text('The code expires in $_expiryText and works once.',
              textAlign: TextAlign.center,
              style: AppTextStyles.labelSmall.copyWith(color: textSecondary)),
        ),

        // THE ESCAPE HATCH.
        //
        // Deliberately below the code field and visually quieter than it: the
        // code is still the primary gate and settles someone in seconds,
        // whereas this puts them in a queue behind a human. But it is a real
        // button, not a support address, because the alternative for someone
        // no mail can reach was nothing at all.
        if (manualFallback) ...[
          const SizedBox(height: 24),
          Divider(color: textSecondary.withValues(alpha: 0.18), height: 1),
          const SizedBox(height: 16),
          Text('No email, even after a few minutes?',
              style: AppTextStyles.titleMedium.copyWith(color: textPrimary)),
          const SizedBox(height: 4),
          Text(
            'Check your spam folder first. If there\'s nothing there, ask a '
            'university administrator to confirm your details and approve the '
            'account by hand.',
            style: AppTextStyles.labelSmall.copyWith(color: textSecondary),
          ),
          const SizedBox(height: 12),
          AfosButton(
            label: 'Ask an administrator to approve me',
            outlined: true,
            loading: reviewBusy,
            onTap: onRequestReview,
          ),
        ],
      ];

  /// The provider refused the address outright, so no code is coming and a
  /// code field would be furniture. The signup IS staged, so this is not an
  /// error page — it is the same fallback the code state offers, promoted to
  /// the primary action because it is now the only one that can work.
  /// True when the mail is missing because OUR daily allowance ran out.
  ///
  /// Worth branching on rather than showing one message for both: a quota is
  /// entirely our doing and clears by itself, while a rejected address might
  /// genuinely be a typo. Telling someone their address looks wrong when it was
  /// our allowance that ran out is how you lose an applicant who did nothing
  /// wrong — and they cannot fix it by trying again, so an unqualified "we
  /// couldn't email you" invites exactly the retry that will also fail.
  bool get _quotaExhausted => mailReason == 'quota';

  /// The window in words, from the server's number rather than a second
  /// copy of it. Rounds to whole minutes because that is how the email
  /// phrases it too, and falls back to seconds below a minute so a short
  /// window never renders as "0 minutes".
  String get _expiryText {
    if (expiresInSeconds < 60) return '$expiresInSeconds seconds';
    final minutes = (expiresInSeconds / 60).round();
    return minutes == 1 ? '1 minute' : '$minutes minutes';
  }

  List<Widget> _mailFailedBody(BuildContext context) => [
        _badge(context, _quotaExhausted ? Icons.schedule_send_outlined : Icons.unsubscribe_outlined,
            AppColors.amber),
        const SizedBox(height: 24),
        Text(_quotaExhausted ? 'Our email limit is reached for today' : 'We couldn\'t email you',
            style: AppTextStyles.displayMedium.copyWith(color: textPrimary)),
        const SizedBox(height: 8),
        if (_quotaExhausted)
          Text(
            'This is our end, not you — nothing is wrong with your address or '
            'your details, and your sign-up is saved. An administrator has '
            'already been alerted automatically and will approve you shortly.',
            style: AppTextStyles.bodyMedium.copyWith(color: textSecondary),
          )
        else
          RichText(
            text: TextSpan(
              style: AppTextStyles.bodyMedium.copyWith(color: textSecondary),
              children: [
                const TextSpan(text: 'Our mail service wouldn\'t accept '),
                TextSpan(text: email ?? '', style: TextStyle(color: textPrimary, fontWeight: FontWeight.w600)),
                const TextSpan(
                  text: ', so no code is on its way. This is a problem on our side, not '
                      'yours — and your sign-up details are saved.',
                ),
              ],
            ),
          ),
        const SizedBox(height: 24),
        if (manualFallback) ...[
          AfosButton(
            label: 'Ask an administrator to approve me',
            loading: reviewBusy,
            onTap: onRequestReview,
          ),
          const SizedBox(height: 8),
          Text(
            'An administrator confirms your details by hand and approves the '
            'account. You\'ll be able to sign in with the password you just chose.',
            style: AppTextStyles.labelSmall.copyWith(color: textSecondary),
          ),
          ..._supportBlock(context),
        ] else ...[
          Text(
            'Please contact AFOS support so someone can set your account up manually.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.amber),
          ),
          ..._supportBlock(context),
        ],

        if (error != null) ...[
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.error_outline, color: AppColors.red, size: 16),
            const SizedBox(width: 6),
            Expanded(child: Text(error!, style: AppTextStyles.labelSmall.copyWith(color: AppColors.red))),
          ]),
        ],

        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: () => context.go('/auth/login'),
            child: Text('Back to sign in', style: TextStyle(color: textSecondary)),
          ),
        ),
      ];

  /// Where to go if waiting is not good enough.
  ///
  /// TAPPABLE, not printed. An applicant reading this is already stuck, and
  /// asking them to memorise an address and retype it into another app is the
  /// point where most people simply stop. The email opens a composer with the
  /// subject pre-filled; Telegram opens the chat.
  ///
  /// Renders nothing at all when the server sent no contacts — an empty
  /// "Contact:" label is worse than silence, and an OLD deployed function
  /// omits these fields entirely.
  List<Widget> _supportBlock(BuildContext context) {
    final mail = (supportEmail ?? '').trim();
    final tg = (supportTelegram ?? '').trim();
    if (mail.isEmpty && tg.isEmpty) return const [];

    // Telegram handles are given as @name but the link needs the bare name.
    final tgUser = tg.startsWith('@') ? tg.substring(1) : tg;

    return [
      const SizedBox(height: 16),
      Divider(color: AppColors.borderOf(context), height: 1),
      const SizedBox(height: 12),
      Text('Need it sooner?',
          style: AppTextStyles.titleMedium.copyWith(color: textPrimary)),
      const SizedBox(height: 6),
      Text(
        'Message us and we will approve you by hand — usually within minutes.',
        style: AppTextStyles.labelSmall.copyWith(color: textSecondary),
      ),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (mail.isNotEmpty)
          OutlinedButton.icon(
            onPressed: () => launchUrl(Uri(
              scheme: 'mailto',
              path: mail,
              query: 'subject=AFOS sign-up needs approval'
                  '&body=My email: ${email ?? ''}\n\n(Sent from the AFOS app)',
            )),
            icon: const Icon(Icons.mail_outline_rounded, size: 16),
            label: Text(mail, overflow: TextOverflow.ellipsis),
          ),
        if (tgUser.isNotEmpty)
          OutlinedButton.icon(
            onPressed: () => launchUrl(Uri.parse('https://t.me/$tgUser'),
                mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.send_rounded, size: 16),
            label: Text(tg, overflow: TextOverflow.ellipsis),
          ),
      ]),
    ];
  }

  /// After the hand is raised. Says only what is actually true: the request
  /// was sent. The server answers identically whether or not a staged signup
  /// exists for the address — anti-enumeration — so promising "an
  /// administrator can now see you" would be a claim this client cannot make.
  List<Widget> _submittedBody(BuildContext context) => [
        _badge(context, Icons.how_to_reg_outlined, AppColors.holoBlue),
        const SizedBox(height: 24),
        Text('Request sent',
            style: AppTextStyles.displayMedium.copyWith(color: textPrimary)),
        const SizedBox(height: 8),
        RichText(
          text: TextSpan(
            style: AppTextStyles.bodyMedium.copyWith(color: textSecondary),
            children: [
              const TextSpan(text: 'We\'ve asked the AFOS administrators to approve '),
              TextSpan(text: email ?? '', style: TextStyle(color: textPrimary, fontWeight: FontWeight.w600)),
              const TextSpan(
                text: ' by hand. Nothing is created until one of them agrees, so you '
                    'can\'t sign in yet — they may contact you to confirm who you are.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'The password you chose is already saved with the request. When the '
          'account is approved, sign in with it.',
          style: AppTextStyles.labelSmall.copyWith(color: textSecondary),
        ),
        const SizedBox(height: 24),
        AfosButton(label: 'Back to sign in', onTap: () => context.go('/auth/login')),
        const SizedBox(height: 10),

        // The code stays redeemable the whole time — register-verify does not
        // care that a review is pending, and proof beats a queue. If the mail
        // turns up late, this is the way back to the field rather than a dead
        // end that outranks the faster route.
        Center(
          child: TextButton(
            onPressed: onBackToCode,
            child: const Text('The email arrived after all', style: TextStyle(color: AppColors.holoBlue)),
          ),
        ),
      ];
}
