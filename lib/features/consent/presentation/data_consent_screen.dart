import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/depth.dart';
import '../../../config/theme/motion.dart';
import '../../../core/services/consent_service.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/glass_card.dart';

/// One-time, device-local data notice shown before a user ever reaches login.
/// Every category listed here is grounded in what the app's own dependencies
/// and features actually do (see docs/OFFLINE_POLICY.md) — nothing generic,
/// nothing speculative. Accepting only sets a local flag (ConsentService);
/// it is a disclosure, not a network call.
class DataConsentScreen extends StatefulWidget {
  const DataConsentScreen({super.key});
  @override State<DataConsentScreen> createState() => _DataConsentScreenState();
}

class _DataConsentScreenState extends State<DataConsentScreen> {
  bool _busy = false;

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    await ConsentService.accept();
    if (!mounted) return;
    // Splash re-runs its destination check, which now sees the accepted flag
    // and proceeds to unlock/login/home as it normally would.
    context.go('/splash');
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    return Scaffold(
      backgroundColor: AppColors.isDark(context) ? AppColors.background : AppColors.lightBg,
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 24, 20, 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Before you continue',
                    style: AppTextStyles.displayMedium.copyWith(color: textPrimary))
                    .animate().fadeIn(duration: AppMotion.durationOf(context, AppMotion.base)),
                const SizedBox(height: 8),
                Text(
                  "Here's what AFOS collects on this device and why — a one-time notice, "
                  'not a form to fill in.',
                  style: AppTextStyles.bodyMedium.copyWith(color: textSecondary),
                ),
                const SizedBox(height: 24),
                for (final item in _items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: GlassCard(
                      glowColor: item.color,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(
                              color: item.color.withValues(alpha: 0.15),
                              borderRadius: AppDepth.radius(1),
                            ),
                            alignment: Alignment.center,
                            child: Icon(item.icon, color: item.color, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(item.title, style: AppTextStyles.titleMedium.copyWith(color: textPrimary)),
                            const SizedBox(height: 4),
                            Text(item.body, style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
                          ])),
                        ]),
                      ),
                    ),
                  ),
                Text(
                  'This device also keeps some of the above (routine, exam schedule, transport '
                  'routes, your profile card) cached locally so those screens still work with no '
                  'signal — never sent anywhere new, only stored for offline viewing.',
                  style: AppTextStyles.labelSmall.copyWith(color: textSecondary),
                ),
              ]),
            ),
          ),
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(20, 12, 20, 12 + MediaQuery.of(context).padding.bottom),
            child: AfosButton(
              label: 'I understand, continue',
              loading: _busy,
              onTap: _accept,
            ),
          ),
        ]),
      ),
    );
  }
}

class _ConsentItem {
  final IconData icon; final Color color; final String title; final String body;
  const _ConsentItem(this.icon, this.color, this.title, this.body);
}

const _items = [
  _ConsentItem(Icons.badge_outlined, AppColors.holoBlue, 'Your academic profile',
      'Name, university ID, department, batch/section and email — used to sign you in and show '
      'your own routine, exams, grades and attendance.'),
  _ConsentItem(Icons.fingerprint_rounded, AppColors.green, 'Fingerprint / Face ID',
      'Matched entirely by your phone\'s own operating system. AFOS never receives or stores your '
      'biometric data — only an encrypted session token, kept in this device\'s secure keystore, '
      'so quick-login works without retyping your password.'),
  _ConsentItem(Icons.location_on_outlined, AppColors.orange, 'Location (SOS only)',
      'Only shared while an SOS alert or nearby-help sharing is active, so responders and nearby '
      'users can find you. Off by default in Settings if you never use SOS.'),
  _ConsentItem(Icons.mic_none_rounded, AppColors.red, 'Microphone (SOS only)',
      "If you record a voice note while raising an SOS alert, it's attached to that alert to help "
      'whoever responds.'),
  _ConsentItem(Icons.notifications_outlined, AppColors.gold, 'Push notifications',
      'A device identifier is registered with our notification provider so routine changes, exam '
      'updates, mentorship and approval alerts can reach you.'),
  _ConsentItem(Icons.camera_alt_outlined, AppColors.holoTeal, 'Camera & files you choose to upload',
      'Used only when you scan a QR code, take/pick a profile photo, or attach a file (assignment, '
      'lost & found listing, feedback) — stored for that feature alone.'),
];
