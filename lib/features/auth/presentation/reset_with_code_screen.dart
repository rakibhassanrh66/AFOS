import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/motion.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/extensions/context_ext.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/afos_text_field.dart';
import '../../../shared/widgets/glass_card.dart';
import '../data/repositories/auth_repository.dart';
import 'widgets/auth_brand_panel.dart';

/// Code-first password reset.
///
/// Replaces the recovery-link round trip for the reason documented in
/// password-reset/index.ts: DIU's mail runs link scanners that fetch every URL
/// in a message, and the old flow's token was spent by that GET — so the
/// student saw "link expired" on their first click, every time, with nothing
/// to tell them why. A typed code cannot be consumed by a scanner.
///
/// The emailed button still works: it lands here as `?token=…`, and the token
/// is spent only by the POST this screen makes after a new password is chosen.
class ResetWithCodeScreen extends StatefulWidget {
  const ResetWithCodeScreen({super.key, this.email, this.token});

  final String? email;
  final String? token;

  @override
  State<ResetWithCodeScreen> createState() => _ResetWithCodeScreenState();
}

class _ResetWithCodeScreenState extends State<ResetWithCodeScreen> {
  final _repo = AuthRepository();
  final _formKey = GlobalKey<FormState>();
  final _codeCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confCtrl = TextEditingController();

  bool _busy = false;
  String? _error;

  bool get _isLinkPath => (widget.token ?? '').isNotEmpty;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _passCtrl.dispose();
    _confCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _busy = true; _error = null; });
    try {
      await _repo.confirmPasswordReset(
        token: _isLinkPath ? widget.token : null,
        email: _isLinkPath ? null : widget.email,
        code: _isLinkPath ? null : _codeCtrl.text.replaceAll(RegExp(r'\D'), ''),
        newPassword: _passCtrl.text,
      );
      AppHaptics.success();
      if (mounted) {
        // Deliberately sent to a fresh sign-in rather than auto-authenticated:
        // it proves the new password actually works before they leave, and the
        // account is never entered from a credential that arrived by email.
        context.showSnack('Password updated — please sign in.');
        context.go('/auth/login');
      }
    } catch (e) {
      if (mounted) {
        AppHaptics.warning();
        setState(() { _busy = false; _error = friendlyError(e); });
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
        final card = SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsetsDirectional.fromSTEB(24, 8, 24, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    maxWidth: outer.maxWidth >= Responsive.mediumBreakpoint ? 460 : double.infinity),
                child: GlassCard(
                  glowColor: AppColors.holoBlue,
                  animated: true,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _formKey,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(
                          width: 56, height: 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.holoBlue.withValues(alpha: 0.12),
                            border: Border.all(color: AppColors.holoBlue.withValues(alpha: 0.4)),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(Icons.lock_reset_rounded, color: AppColors.holoBlue, size: 28),
                        ).animate()
                            .scale(duration: AppMotion.durationOf(context, AppMotion.slow), curve: AppMotion.standard)
                            .fadeIn(duration: AppMotion.durationOf(context, AppMotion.base)),
                        const SizedBox(height: 24),
                        Text('Set a new password',
                            style: AppTextStyles.displayMedium.copyWith(color: textPrimary))
                            .animate(delay: AppMotion.sequenceDelay(context, 3))
                            .fadeIn(duration: AppMotion.durationOf(context, AppMotion.base))
                            .slideX(begin: -0.06, curve: AppMotion.standard),
                        const SizedBox(height: 8),
                        Text(
                          _isLinkPath
                              ? 'Choose a new password for your AFOS account.'
                              : 'Enter the 6-digit code we emailed to ${widget.email ?? 'your address'}, then choose a new password.',
                          style: AppTextStyles.bodyMedium.copyWith(color: textSecondary),
                        ),
                        const SizedBox(height: 28),

                        if (!_isLinkPath) ...[
                          TextFormField(
                            controller: _codeCtrl,
                            enabled: !_busy,
                            keyboardType: TextInputType.number,
                            autofillHints: const [AutofillHints.oneTimeCode],
                            maxLength: 6,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(6),
                            ],
                            textAlign: TextAlign.center,
                            style: AppTextStyles.displayMedium.copyWith(
                              color: textPrimary, letterSpacing: 14,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                            validator: (v) =>
                                (v ?? '').replaceAll(RegExp(r'\D'), '').length == 6 ? null : 'Enter all 6 digits',
                            decoration: InputDecoration(
                              counterText: '',
                              hintText: '······',
                              hintStyle: AppTextStyles.displayMedium.copyWith(
                                  color: textSecondary.withValues(alpha: 0.35), letterSpacing: 14),
                              filled: true,
                              fillColor: AppColors.surfaceOf(context).withValues(alpha: 0.5),
                              contentPadding: const EdgeInsets.symmetric(vertical: 18),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: textSecondary.withValues(alpha: 0.25)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: AppColors.holoBlue, width: 1.6),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        AfosTextField(
                          hint: 'New password', controller: _passCtrl,
                          prefixIcon: Icons.lock_outline, obscure: true,
                          validator: AppValidators.password,
                        ),
                        const SizedBox(height: 16),
                        AfosTextField(
                          hint: 'Confirm new password', controller: _confCtrl,
                          prefixIcon: Icons.lock_outline, obscure: true,
                          validator: (v) => v != _passCtrl.text ? 'Passwords don\'t match' : null,
                        ),

                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Icon(Icons.error_outline, color: AppColors.red, size: 16),
                            const SizedBox(width: 6),
                            Expanded(child: Text(_error!,
                                style: AppTextStyles.labelSmall.copyWith(color: AppColors.red))),
                          ]),
                        ],

                        const SizedBox(height: 24),
                        AfosButton(label: 'Update password', loading: _busy, onTap: _submit),
                        const SizedBox(height: 10),
                        Center(
                          child: TextButton(
                            onPressed: () => context.go('/auth/forgot-password'),
                            child: Text('Request a new code', style: TextStyle(color: textSecondary)),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        if (outer.maxWidth >= Responsive.expandedBreakpoint) {
          return Row(children: [
            const Expanded(flex: 5, child: AuthBrandPanel()),
            Expanded(flex: 4, child: card),
          ]);
        }
        return card;
      }),
    );
  }
}
