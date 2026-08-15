import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/motion.dart';
import '../../../shared/extensions/context_ext.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/afos_text_field.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../core/utils/validators.dart';
import '../../../core/utils/responsive.dart';

/// Reached only via a Supabase password-recovery link (bootstrap.dart's
/// AuthChangeEvent.passwordRecovery listener routes here) -- there was
/// previously no screen at all tied to that event, so clicking the emailed
/// reset link landed the user in an authenticated-but-nothing-happens state
/// with no way to actually set a new password.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});
  @override State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passCtrl = TextEditingController();
  final _confCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() { _passCtrl.dispose(); _confCtrl.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.updateUser(UserAttributes(password: _passCtrl.text));
      // The recovery session already proved account ownership, but signing
      // out and sending them to a fresh login confirms the new password
      // actually works rather than silently continuing in a session that
      // came from an emailed link (which could have been forwarded/opened
      // by someone else).
      // Global: after a password change every other session that was signed
      // in with the OLD password must stop working -- that is the whole point
      // of resetting it.
      await Supabase.instance.client.auth.signOut(scope: SignOutScope.global);
      if (mounted) {
        context.showSnack('Password updated — please sign in.');
        context.go('/auth/login');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        context.showSnack('Could not update password. The reset link may have expired — request a new one.', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    return Scaffold(
      backgroundColor: AppColors.surfaceOf(context),
      body: LayoutBuilder(builder: (context, outer) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: Center(child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: outer.maxWidth >= Responsive.mediumBreakpoint ? 460 : double.infinity),
              child: GlassCard(
                glowColor: AppColors.holoBlue,
                animated: true,
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
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
                        child: const Icon(Icons.lock_open_rounded, color: AppColors.holoBlue, size: 28),
                      ).animate()
                          .scale(duration: AppMotion.durationOf(context, AppMotion.slow), curve: AppMotion.standard)
                          .fadeIn(duration: AppMotion.durationOf(context, AppMotion.base)),
                      const SizedBox(height: 24),
                      Text('Set a new password', style: AppTextStyles.displayMedium.copyWith(color: textPrimary))
                          .animate(delay: AppMotion.sequenceDelay(context, 3))
                          .fadeIn(duration: AppMotion.durationOf(context, AppMotion.base))
                          .slideX(begin: -0.06, curve: AppMotion.standard),
                      const SizedBox(height: 8),
                      Text('Choose a new password for your AFOS account.',
                          style: AppTextStyles.bodyMedium.copyWith(color: textSecondary))
                          .animate(delay: AppMotion.sequenceDelay(context, 5))
                          .fadeIn(duration: AppMotion.durationOf(context, AppMotion.base)),
                      const SizedBox(height: 32),
                      AfosTextField(hint: 'New password', controller: _passCtrl,
                          prefixIcon: Icons.lock_outline, obscure: true,
                          validator: AppValidators.password)
                          .animate(delay: AppMotion.sequenceDelay(context, 7))
                          .fadeIn(duration: AppMotion.durationOf(context, AppMotion.base))
                          .slideY(begin: 0.08, curve: AppMotion.standard),
                      const SizedBox(height: 16),
                      AfosTextField(hint: 'Confirm new password', controller: _confCtrl,
                          prefixIcon: Icons.lock_outline, obscure: true,
                          validator: (v) => v != _passCtrl.text ? 'Passwords don\'t match' : null)
                          .animate(delay: AppMotion.sequenceDelay(context, 8))
                          .fadeIn(duration: AppMotion.durationOf(context, AppMotion.base))
                          .slideY(begin: 0.08, curve: AppMotion.standard),
                      const SizedBox(height: 24),
                      AfosButton(label: 'Update password', loading: _loading, onTap: _submit)
                          .animate(delay: AppMotion.sequenceDelay(context, 9))
                          .fadeIn(duration: AppMotion.durationOf(context, AppMotion.base))
                          .slideY(begin: 0.08, curve: AppMotion.standard),
                    ]),
                  ),
                ),
              ),
            )),
          ),
        );
      }),
    );
  }
}
