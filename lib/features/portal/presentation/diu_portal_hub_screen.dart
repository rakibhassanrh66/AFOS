import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/auth/role_session.dart';
import '../../../shared/widgets/feature_header.dart';
import '../../../shared/widgets/glass_bottom_nav.dart';
import '../../../shared/widgets/info_card.dart';
import '../../shell/presentation/top_app_bar.dart';

/// One entry point for the DIU student-portal pages, instead of scattering nine
/// links through the slide menu.
///
/// The links are the student's OWN portal records (their ledger, their waiver,
/// their transport card), so this hub is reached from the student-only section
/// of the menu — a teacher or staff member has none of these. Notice Board and
/// Student Benefits are university-wide and shown to everyone who can reach the
/// hub.
///
/// Each entry opens in-app via [DiuPortalScreen]. They are NOT scraped and
/// re-rendered natively: the portal sits behind a Cloudflare bot challenge that
/// answers HTTP 403 to every non-browser client (verified directly, including
/// with a real desktop Chrome User-Agent), so no server-side scraper can read
/// them, and working around that challenge is not something this app should do.
class DiuPortalHubScreen extends StatelessWidget {
  const DiuPortalHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final role = RoleSession.role;
    final isStudent = role == 'student';

    final links = <_PortalLink>[
      const _PortalLink('Student Portal', 'Profile, today\'s routine, semester results',
          Icons.account_balance_rounded, '/portal/dashboard', AppColors.holoBlue),
      if (isStudent)
        const _PortalLink('Payment Ledger', 'Fees paid, due and payment history',
            Icons.receipt_long_rounded, '/portal/ledger', AppColors.gold),
      if (isStudent)
        const _PortalLink('Waiver', 'Your waiver status and applications',
            Icons.percent_rounded, '/portal/waiver', AppColors.holoTeal),
      if (isStudent)
        const _PortalLink('Scholarship Circular', 'Open scholarship notices',
            Icons.school_rounded, '/portal/scholarship', AppColors.blue),
      if (isStudent)
        const _PortalLink('Transport Card', 'Apply for or renew your bus card',
            Icons.credit_card_rounded, '/portal/transport-card', AppColors.teal),
      const _PortalLink('Career Development', 'CDC services and openings',
          Icons.work_outline_rounded, '/portal/career', AppColors.indigo),
      const _PortalLink('DIU Notice Board', 'Official university notices',
          Icons.campaign_rounded, '/portal/notices', AppColors.red),
      const _PortalLink('Student Benefits', 'Discount partners and free tools',
          Icons.card_giftcard_rounded, '/portal/facilities', AppColors.pink),
      if (isStudent)
        const _PortalLink('Hall Management', 'DIU hall portal',
            Icons.apartment_rounded, '/portal/hall', AppColors.coral),
    ];

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const AfosAppBar(title: 'DIU Portal'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            16, 12, 16, 16 + GlassBottomNav.navContentClearance),
        children: [
          const FeatureHeader(
            title: 'DIU Student Portal',
            subtitle: 'Sign in once with your portal credentials',
            icon: Icons.language_rounded,
            accent: AppColors.holoBlue,
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              'These open the real DIU portal inside AFOS. Your portal login is '
              'separate from your AFOS account.',
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textSecondaryOf(context)),
            ),
          ),
          for (final l in links)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InfoCard(
                icon: l.icon,
                accent: l.color,
                title: l.title,
                subtitle: l.subtitle,
                trailing: Icon(Icons.chevron_right_rounded,
                    color: AppColors.textSecondaryOf(context)),
                onTap: () => context.push(l.route),
              ),
            ),
        ],
      ),
    );
  }
}

class _PortalLink {
  final String title, subtitle, route;
  final IconData icon;
  final Color color;
  const _PortalLink(this.title, this.subtitle, this.icon, this.route, this.color);
}
