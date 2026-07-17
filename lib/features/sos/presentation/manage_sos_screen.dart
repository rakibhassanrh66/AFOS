import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/glass_chip.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../shell/presentation/top_app_bar.dart';
import '../data/repositories/sos_repository.dart';

/// Admin/staff oversight of every SOS alert system-wide -- same filter-tab
/// + refetch-on-any-change pattern as manage_hall_screen.dart, since
/// sos_alerts.stream() can't embed the sender's profile either.
class ManageSosScreen extends StatefulWidget {
  const ManageSosScreen({super.key});
  @override State<ManageSosScreen> createState() => _ManageSosScreenState();
}

class _ManageSosScreenState extends State<ManageSosScreen> {
  List<Map<String, dynamic>> _alerts = [];
  bool _loading = true;
  String? _error;
  String _filter = 'active';
  RealtimeChannel? _sub;

  static const _filters = ['active', 'resolved', 'false_alarm', 'all'];

  @override
  void initState() {
    super.initState();
    _load();
    _sub = SupabaseConfig.client.channel('manage_sos_alerts')
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public',
            table: 'sos_alerts', callback: (_) => _load())
        .subscribe();
  }

  @override
  void dispose() { _sub?.unsubscribe(); super.dispose(); }

  Future<void> _load() async {
    try {
      final res = await SosRepository.fetchAllForAdmin();
      if (mounted) setState(() { _alerts = res; _loading = false; _error = null; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = friendlyError(e); });
    }
  }

  List<Map<String, dynamic>> get _visible =>
      _filter == 'all' ? _alerts : _alerts.where((a) => (a['status'] ?? 'active') == _filter).toList();

  @override
  Widget build(BuildContext context) {
    final textSecondary = AppColors.textSecondaryOf(context);
    final activeCount = _alerts.where((a) => (a['status'] ?? 'active') == 'active').length;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const AfosAppBar(title: 'Manage SOS Alerts'),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [AppColors.red, AppColors.coral]),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(children: [
              Container(padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), shape: BoxShape.circle),
                  child: const Icon(Icons.sos_rounded, color: Colors.white, size: 24)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Manage SOS Alerts', style: AppTextStyles.titleLarge.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(_loading ? 'Loading…' : '$activeCount active system-wide',
                    style: AppTextStyles.bodyMedium.copyWith(color: Colors.white.withValues(alpha: 0.9))),
              ])),
            ]),
          ),
        ),
        SizedBox(height: 48, child: ListView(scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: _filters.map((f) {
              final sel = f == _filter;
              final txt = f.replaceAll('_', ' ');
              return Padding(padding: const EdgeInsets.only(right: 8),
                child: Center(child: GlassChip(
                  label: txt[0].toUpperCase() + txt.substring(1),
                  selected: sel,
                  color: AppColors.red,
                  onTap: () => setState(() => _filter = f))));
            }).toList())),
        Expanded(child: _loading
            ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList())
            : _error != null
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.error_outline_rounded, color: AppColors.red, size: 40),
                    const SizedBox(height: 12),
                    Text('Couldn\'t load: $_error', textAlign: TextAlign.center, style: TextStyle(color: textSecondary)),
                    const SizedBox(height: 12),
                    TextButton(onPressed: _load, child: const Text('Retry')),
                  ])))
                : _visible.isEmpty
                    ? EmptyState(icon: Icons.sos_rounded, title: 'Nothing here', subtitle: 'No "$_filter" alerts right now')
                    : ListView.builder(padding: const EdgeInsets.all(16), itemCount: _visible.length,
                        itemBuilder: (ctx, i) {
                          final a = _visible[i];
                          final sender = a['profiles'] as Map<String, dynamic>? ?? {};
                          final status = a['status'] as String? ?? 'active';
                          return Container(
                            key: ValueKey(a['id']),
                            margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: status == 'active' ? AppColors.red : AppColors.borderOf(context),
                                    width: status == 'active' ? 1.2 : 0.5)),
                            child: InkWell(
                              onTap: () => context.push('/sos/${a['id']}'),
                              child: Row(children: [
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(children: [
                                    Flexible(child: Text(sender['full_name'] ?? 'Unknown',
                                        style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimaryOf(context)),
                                        maxLines: 1, overflow: TextOverflow.ellipsis)),
                                    if (sender['is_verified'] == true) const Padding(padding: EdgeInsets.only(left: 5),
                                        child: Icon(Icons.verified_rounded, color: AppColors.blue, size: 15)),
                                  ]),
                                  const SizedBox(height: 2),
                                  Text('${a['zone_type'] == 'campus' ? 'Campus' : 'Zila'} · ${a['recipient_count'] ?? 0} notified',
                                      style: AppTextStyles.labelSmall.copyWith(color: textSecondary)),
                                ])),
                                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                        color: (status == 'active' ? AppColors.red : AppColors.green).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(10)),
                                    child: Text(status.toUpperCase(),
                                        style: TextStyle(color: status == 'active' ? AppColors.red : AppColors.green, fontSize: 10, fontWeight: FontWeight.w700))),
                              ]),
                            ),
                          );
                        }),
        ),
      ]),
    );
  }
}
