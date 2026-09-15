import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/depth.dart';
import '../../../config/theme/liquid_glass_tokens.dart';
import '../../../config/theme/motion.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/utils/responsive.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../shell/presentation/top_app_bar.dart';

import '../../../core/layout/nav_insets.dart';
import '../../../config/theme/spacing.dart';
/// Public version history / changelog -- pulls from app_releases (a real
/// table, not a hardcoded list, so future releases can be added without a
/// redeploy) rather than just showing the single current build number the
/// way Settings' "App Info" section already did.
class ReleasesScreen extends StatefulWidget {
  const ReleasesScreen({super.key});
  @override State<ReleasesScreen> createState() => _ReleasesScreenState();
}

class _ReleasesScreenState extends State<ReleasesScreen> {
  List<Map<String, dynamic>> _releases = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      // `release_date` is a DATE, and four releases share 2026-07-19, so
      // ordering on it alone left those four in whatever order Postgres
      // happened to return — live, that was 2.3.1, 2.0.1, 2.1.0, 2.0.2, i.e.
      // What's New listed an older release above a newer one.
      //
      // `created_at` is the tiebreaker because it carries the build number in
      // its time component (…00:15 = +15, 00:20 = +20), so it orders same-day
      // releases correctly. Sorting on the `version` text instead would look
      // right today but break the first time a "2.10.0" ships, since "2.10.0"
      // sorts below "2.9.0" lexicographically.
      final res = await SupabaseConfig.client.from('app_releases')
          .select()
          .order('release_date', ascending: false)
          .order('created_at', ascending: false) as List;
      if (mounted) setState(() { _releases = res.cast(); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    return Scaffold(
      backgroundColor: AppColors.surfaceOf(context),
      appBar: const AfosAppBar(title: 'What\'s New'),
      body: _loading
          ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList(count: 4))
          : _releases.isEmpty
              ? const EmptyState(icon: Icons.new_releases_outlined,
                  title: 'No releases yet', subtitle: 'Check back soon')
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppColors.blue,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Center(child: ConstrainedBox(
                      constraints: BoxConstraints(
                          maxWidth: Responsive.isDesktop(context) ? 720 : double.infinity),
                      child: Padding(
                        padding: EdgeInsetsDirectional.fromSTEB(16, 16, 16, 16 + NavInsets.of(context)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          _HeroLatest(release: _releases.first, textPrimary: textPrimary, textSecondary: textSecondary),
                          const SizedBox(height: 28),
                          Text('Release history', style: AppTextStyles.headlineMed.copyWith(color: textPrimary))
                              .animate().fadeIn(duration: AppMotion.durationOf(context, AppMotion.base)),
                          const SizedBox(height: AppSpace.md),
                          for (var i = 0; i < _releases.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _ReleaseRow(release: _releases[i], isLatest: i == 0)
                                  .animate(delay: AppMotion.staggerFor(context, i))
                                  .fadeIn(duration: AppMotion.durationOf(context, AppMotion.base))
                                  .slideY(begin: 0.06, curve: AppMotion.standard),
                            ),
                          const SizedBox(height: AppSpace.xl),
                          const _HowUpdatingWorks(),
                          const SizedBox(height: AppSpace.md),
                        ]),
                      ),
                    )),
                  ),
                ),
    );
  }
}

/// What actually happens when a new AFOS ships, said once, where someone is
/// already looking at release history.
///
/// WHY THIS IS IN THE APP AND NOT ONLY ON THE RELEASE PAGE. AFOS is not on the
/// Play Store, so every user has at some point installed an APK by hand and
/// has no reason to assume the app can update itself. The GitHub release page
/// lists four similarly-named files, and someone who goes looking there will
/// pick one and sideload it — which works, but is slower, is the path that
/// produces "App not installed" signature conflicts, and is entirely
/// unnecessary for anyone already running the app.
///
/// The one thing worth telling them is that they never have to do that. The
/// rest of this card answers the questions that follow from it.
class _HowUpdatingWorks extends StatelessWidget {
  const _HowUpdatingWorks();

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);

    Widget point(IconData icon, String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.lg),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 18, color: AppColors.holoBlue),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    style: AppTextStyles.bodyMedium.copyWith(
                        color: textPrimary, fontWeight: FontWeight.w700)),
                const SizedBox(height: AppSpace.xs),
                Text(body,
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: textSecondary, height: 1.45)),
              ]),
            ),
          ]),
        );

    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('How updating works',
              style: AppTextStyles.headlineMed.copyWith(color: textPrimary)),
          const SizedBox(height: AppSpace.lg),
          point(
            Icons.system_update_outlined,
            'The app updates itself',
            'You never need to download a file or visit a website. When a '
                'release goes out, AFOS offers it here and in Settings. Tap '
                'Update and it downloads and installs over the copy you '
                'already have.',
          ),
          point(
            Icons.notifications_active_outlined,
            'You are told when there is one',
            'A new release reaches you whether the app is open or closed. If '
                'AFOS is open, the update card appears on its own; if it is '
                'closed, you get a notification.',
          ),
          point(
            Icons.sim_card_download_outlined,
            'It downloads only what your phone needs',
            'AFOS picks the build matching your phone rather than the '
                'universal one, which is roughly a third of the size. On '
                'campus mobile data that is the difference between an update '
                'that completes and one that does not.',
          ),
          point(
            Icons.lock_outline_rounded,
            'You stay signed in',
            'Updating keeps your session and your fingerprint or face login. '
                'You are not asked to sign in again afterwards.',
          ),
          point(
            Icons.language_rounded,
            'On the web there is nothing to do',
            'The browser version is always the current release. Reload the '
                'page and you have it.',
          ),
          // Last, and deliberately hedged: this is the fallback, not the
          // route anyone should be taking. Naming the file pattern is what
          // stops someone downloading the 91 MB universal build by default.
          Text(
            'If the in-app update cannot reach GitHub, the release page has '
                'the same build to install by hand. Take the file ending in '
                'arm64-v8a unless you know your phone is 32-bit.',
            style: AppTextStyles.bodyMedium
                .copyWith(color: textSecondary, height: 1.45),
          ),
        ]),
      ),
    );
  }
}

class _HeroLatest extends StatelessWidget {
  final Map<String, dynamic> release;
  final Color textPrimary, textSecondary;
  const _HeroLatest({required this.release, required this.textPrimary, required this.textSecondary});

  @override
  Widget build(BuildContext context) {
    final highlights = (release['highlights'] as List?)?.cast<String>() ?? const [];
    return GlassCard(
      glowColor: AppColors.holoBlue,
      animated: true,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [AppColors.holoBlue, AppColors.teal]),
                borderRadius: BorderRadius.circular(LiquidGlass.radiusPill),
              ),
              child: const Text('LATEST',
                  textHeightBehavior: TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
                  style: TextStyle(color: Colors.white, fontSize: 10, height: 1.0, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
            ),
            const SizedBox(width: 10),
            Text('v${release['version']}', style: AppTextStyles.monoMedium.copyWith(color: textSecondary)),
            const Spacer(),
            _PlatformIcons(platforms: (release['platforms'] as List?)?.cast<String>() ?? const []),
          ]),
          const SizedBox(height: 14),
          Text(release['title'] ?? '', style: AppTextStyles.displayMedium.copyWith(color: textPrimary)),
          const SizedBox(height: AppSpace.xs),
          Text(_formatDate(release['release_date']), style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
          const SizedBox(height: AppSpace.lg),
          for (final h in highlights)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(padding: const EdgeInsets.only(top: 6),
                    child: Container(width: 5, height: 5,
                        decoration: const BoxDecoration(color: AppColors.holoBlue, shape: BoxShape.circle))),
                const SizedBox(width: 10),
                Expanded(child: Text(h, style: AppTextStyles.bodyLarge.copyWith(color: textPrimary, height: 1.4))),
              ]),
            ),
        ]),
      ),
    ).animate()
        .fadeIn(duration: AppMotion.durationOf(context, AppMotion.slow), curve: AppMotion.standard)
        .slideY(begin: -0.08, end: 0,
            duration: AppMotion.durationOf(context, AppMotion.slow), curve: AppMotion.standard);
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}

class _ReleaseRow extends StatefulWidget {
  final Map<String, dynamic> release;
  final bool isLatest;
  const _ReleaseRow({required this.release, required this.isLatest});
  @override State<_ReleaseRow> createState() => _ReleaseRowState();
}

class _ReleaseRowState extends State<_ReleaseRow> {
  bool _expanded = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.release;
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    final highlights = (r['highlights'] as List?)?.cast<String>() ?? const [];
    final d = DateTime.tryParse(r['release_date'] ?? '');
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () { AppHaptics.selection(); setState(() => _expanded = !_expanded); },
        child: AnimatedContainer(
          duration: AppMotion.durationOf(context, AppMotion.tight),
          curve: AppMotion.standard,
          decoration: BoxDecoration(
            color: AppColors.surfaceOf(context),
            borderRadius: AppDepth.radius(1),
            border: Border.all(color: _hover
                ? AppColors.holoBlue.withValues(alpha: 0.4)
                : AppColors.borderOf(context), width: _hover ? 1 : 0.5),
            boxShadow: _hover ? [
              BoxShadow(color: AppColors.holoBlue.withValues(alpha: 0.12), blurRadius: 16, spreadRadius: -4),
            ] : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                // Version column
                SizedBox(width: 78, child: Text('v${r['version']}',
                    style: AppTextStyles.monoSmall.copyWith(color: textSecondary))),
                // Date column
                SizedBox(width: 76, child: Text(
                    d != null ? '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}' : '',
                    style: AppTextStyles.bodyMedium.copyWith(color: textSecondary))),
                // Platform column
                _PlatformIcons(platforms: (r['platforms'] as List?)?.cast<String>() ?? const []),
                const SizedBox(width: AppSpace.md),
                // Title column
                Expanded(child: Text(r['title'] ?? '',
                    style: AppTextStyles.titleMedium.copyWith(color: textPrimary),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
                AnimatedRotation(
                  duration: AppMotion.durationOf(context, AppMotion.base),
                  curve: AppMotion.standard,
                  turns: _expanded ? 0.5 : 0,
                  child: Icon(Icons.expand_more_rounded, size: 20, color: textSecondary),
                ),
              ]),
              AnimatedCrossFade(
                duration: AppMotion.durationOf(context, AppMotion.base),
                crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                firstChild: const SizedBox(width: double.infinity),
                secondChild: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final h in highlights)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Padding(padding: const EdgeInsets.only(top: 6),
                              child: Container(width: 4, height: 4,
                                  decoration: BoxDecoration(color: textSecondary, shape: BoxShape.circle))),
                          const SizedBox(width: 10),
                          Expanded(child: Text(h, style: AppTextStyles.bodyMedium.copyWith(color: textSecondary, height: 1.4))),
                        ]),
                      ),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _PlatformIcons extends StatelessWidget {
  final List<String> platforms;
  const _PlatformIcons({required this.platforms});

  @override
  Widget build(BuildContext context) {
    final secondary = AppColors.textSecondaryOf(context);
    Widget chip(IconData icon, bool active) => Padding(
      padding: const EdgeInsetsDirectional.only(start: 4),
      child: Icon(icon, size: 15, color: active ? AppColors.holoBlue : secondary.withValues(alpha: 0.3)),
    );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      chip(Icons.language_rounded, platforms.contains('web')),
      chip(Icons.android_rounded, platforms.contains('android')),
      chip(Icons.apple_rounded, platforms.contains('ios')),
    ]);
  }
}
