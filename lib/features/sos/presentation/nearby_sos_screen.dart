import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../shell/presentation/top_app_bar.dart';
import '../data/repositories/sos_repository.dart';

/// Active SOS alerts within 5km of the current user -- gated entirely by
/// sos_alerts' nearby_select_sos_alerts RLS policy (live-verified), not
/// client-side filtering. Anyone reachable here is someone who could
/// plausibly go help, whether or not they were an official
/// trigger-sos-alert recipient.
class NearbySosScreen extends StatefulWidget {
  const NearbySosScreen({super.key});
  @override State<NearbySosScreen> createState() => _NearbySosScreenState();
}

class _NearbySosScreenState extends State<NearbySosScreen> {
  List<Map<String, dynamic>> _alerts = [];
  bool _loading = true;
  String? _error;
  RealtimeChannel? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = SupabaseConfig.client.channel('nearby_sos_alerts')
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public',
            table: 'sos_alerts', callback: (_) => _load())
        .subscribe();
  }

  @override
  void dispose() { _sub?.unsubscribe(); super.dispose(); }

  Future<void> _load() async {
    try {
      final res = await SosRepository.fetchNearbyActive();
      if (mounted) setState(() { _alerts = res; _loading = false; _error = null; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = friendlyError(e); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AfosAppBar(title: 'Nearby SOS Alerts'),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList(count: 4))
            : _error != null
                ? ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Column(children: [
                    Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: textSecondary)),
                    const SizedBox(height: 12),
                    TextButton(onPressed: _load, child: const Text('Retry')),
                  ]))])
                : _alerts.isEmpty
                    ? ListView(children: const [EmptyState(icon: Icons.shield_outlined,
                        title: 'No active alerts near you',
                        subtitle: "You'll see it here if someone nearby needs help.")])
                    : ListView.builder(padding: const EdgeInsets.all(16), itemCount: _alerts.length,
                        itemBuilder: (ctx, i) {
                          final a = _alerts[i];
                          final sender = a['profiles'] as Map<String, dynamic>? ?? {};
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            color: AppColors.surfaceOf(context),
                            child: ListTile(
                              onTap: () => context.push('/sos/${a['id']}'),
                              leading: CircleAvatar(backgroundColor: AppColors.red.withValues(alpha: 0.15),
                                  backgroundImage: sender['avatar_url'] != null ? NetworkImage(sender['avatar_url']) : null,
                                  child: sender['avatar_url'] == null ? const Icon(Icons.person, color: AppColors.red) : null),
                              title: Row(children: [
                                Flexible(child: Text(sender['full_name'] as String? ?? 'Someone',
                                    style: AppTextStyles.titleMedium.copyWith(color: textPrimary, fontWeight: FontWeight.w700),
                                    maxLines: 1, overflow: TextOverflow.ellipsis)),
                                if (sender['is_verified'] == true) const Padding(padding: EdgeInsets.only(left: 5),
                                    child: Icon(Icons.verified_rounded, color: AppColors.blue, size: 15)),
                              ]),
                              subtitle: Text(a['zone_type'] == 'campus' ? 'On/near campus' : 'Nearby',
                                  style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
                              trailing: Icon(Icons.chevron_right, color: textSecondary),
                            ),
                          );
                        }),
      ),
    );
  }
}
