import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/utils/responsive.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../shell/presentation/top_app_bar.dart';

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
      final res = await SupabaseConfig.client.from('app_releases')
          .select().order('release_date', ascending: false) as List;
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
                        padding: const EdgeInsets.all(16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          _HeroLatest(release: _releases.first, textPrimary: textPrimary, textSecondary: textSecondary),
                          const SizedBox(height: 28),
                          Text('Release history', style: AppTextStyles.headlineMed.copyWith(color: textPrimary))
                              .animate().fadeIn(duration: 300.ms),
                          const SizedBox(height: 12),
                          for (var i = 0; i < _releases.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _ReleaseRow(release: _releases[i], isLatest: i == 0)
                                  .animate(delay: (i * 70).ms).fadeIn(duration: 300.ms).slideY(begin: 0.06, curve: Curves.easeOutCubic),
                            ),
                          const SizedBox(height: 12),
                        ]),
                      ),
                    )),
                  ),
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
                borderRadius: BorderRadius.circular(20),
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
          const SizedBox(height: 4),
          Text(_formatDate(release['release_date']), style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
          const SizedBox(height: 16),
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
    ).animate().fadeIn(duration: 400.ms, curve: Curves.easeOutExpo)
        .slideY(begin: -0.08, end: 0, duration: 450.ms, curve: Curves.easeOutExpo);
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
        onTap: () => setState(() => _expanded = !_expanded),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: AppColors.surfaceOf(context),
            borderRadius: BorderRadius.circular(14),
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
                const SizedBox(width: 12),
                // Title column
                Expanded(child: Text(r['title'] ?? '',
                    style: AppTextStyles.titleMedium.copyWith(color: textPrimary),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
                AnimatedRotation(
                  duration: const Duration(milliseconds: 200),
                  turns: _expanded ? 0.5 : 0,
                  child: Icon(Icons.expand_more_rounded, size: 20, color: textSecondary),
                ),
              ]),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 220),
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
      padding: const EdgeInsets.only(left: 4),
      child: Icon(icon, size: 15, color: active ? AppColors.holoBlue : secondary.withValues(alpha: 0.3)),
    );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      chip(Icons.language_rounded, platforms.contains('web')),
      chip(Icons.android_rounded, platforms.contains('android')),
      chip(Icons.apple_rounded, platforms.contains('ios')),
    ]);
  }
}
