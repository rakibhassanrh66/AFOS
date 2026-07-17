import 'package:flutter/material.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../shared/animations/page_transitions.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/feature_header.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../shell/presentation/top_app_bar.dart';

/// Super Admin / admin cross-department moderation view — the regular
/// DeptChatScreen hard-filters to the viewer's own department for every
/// role (dept_chat_screen.dart:31-33), so there was previously no way for
/// anyone to see or moderate another department's channels at all. The
/// admin_read_all_channels/admin_read_all_messages/admin_delete_any_message
/// RLS policies (20260704240000) back this with a real server-side bypass,
/// not just a client-side view.
class ManageDeptChatScreen extends StatefulWidget {
  const ManageDeptChatScreen({super.key});
  @override State<ManageDeptChatScreen> createState() => _ManageDeptChatScreenState();
}

class _ManageDeptChatScreenState extends State<ManageDeptChatScreen> {
  List<Map<String, dynamic>> _channels = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final res = await SupabaseConfig.client.from('dept_channels')
          .select().order('department').order('channel_name') as List;
      if (mounted) setState(() { _channels = res.cast(); _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const AfosAppBar(title: 'Moderate Dept Chats'),
      body: Column(children: [
        FeatureHeader(
          title: 'Moderate Dept Chats',
          subtitle: _loading ? 'Loading…' : '${_channels.length} channels across all departments',
          icon: Icons.forum_rounded,
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [AppColors.indigo, AppColors.blue]),
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        ),
        Expanded(child: _loading
          ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList())
          : _channels.isEmpty
              ? const EmptyState(icon: Icons.chat_bubble_outline_rounded, title: 'No channels', subtitle: 'Nothing to moderate yet')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: _channels.length,
                  itemBuilder: (ctx, i) {
                    final ch = _channels[i];
                    final audience = ch['audience'] as String? ?? 'all';
                    final audienceLabel = switch (audience) {
                      'students' => 'Students only',
                      'teachers' => 'Faculty only',
                      _ => 'Everyone',
                    };
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.borderOf(context), width: 0.5)),
                      child: InkWell(
                        onTap: () => Navigator.push(context,
                            appPageRoute(_ModerateChatRoomScreen(channel: ch))),
                        child: Row(children: [
                          Container(width: 40, height: 40,
                              decoration: BoxDecoration(
                                  gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                                      colors: [AppColors.indigo, AppColors.blue]),
                                  borderRadius: BorderRadius.circular(10)),
                              child: const Icon(Icons.tag_rounded, color: Colors.white, size: 20)),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${ch['department'] ?? ''} · #${ch['channel_name'] ?? ''}',
                                style: AppTextStyles.titleMedium.copyWith(color: textPrimary)),
                            Text(audienceLabel, style: AppTextStyles.labelSmall.copyWith(color: textSecondary)),
                          ])),
                          Icon(Icons.chevron_right_rounded, color: textSecondary),
                        ]),
                      ),
                    );
                  })),
      ]),
    );
  }
}

class _ModerateChatRoomScreen extends StatefulWidget {
  final Map<String, dynamic> channel;
  const _ModerateChatRoomScreen({required this.channel});
  @override State<_ModerateChatRoomScreen> createState() => _ModerateChatRoomState();
}

class _ModerateChatRoomState extends State<_ModerateChatRoomScreen> {
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final res = await SupabaseConfig.client.from('dept_messages')
          .select('*, profiles(full_name,role)')
          .eq('channel_id', widget.channel['id'])
          .order('created_at') as List;
      if (mounted) setState(() { _messages = res.cast(); _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete(String id) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dctx) => AlertDialog(
              title: const Text('Remove this message?'),
              content: const Text('This deletes it for everyone immediately.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Cancel')),
                TextButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('Remove')),
              ],
            ));
    if (confirmed != true) return;
    await SupabaseConfig.client.from('dept_messages').delete().eq('id', id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AfosAppBar(title: '#${widget.channel['channel_name'] ?? 'chat'}'),
      body: _loading
          ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList())
          : _messages.isEmpty
              ? const EmptyState(icon: Icons.chat_bubble_outline_rounded, title: 'No messages', subtitle: 'Nothing posted here yet')
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _messages.length,
                  itemBuilder: (ctx, i) {
                    final m = _messages[i];
                    final profile = m['profiles'] as Map<String, dynamic>? ?? {};
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.borderOf(context), width: 0.5)),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${profile['full_name'] ?? 'Unknown'} · ${profile['role'] ?? ''}',
                              style: AppTextStyles.labelSmall.copyWith(color: textSecondary)),
                          const SizedBox(height: 4),
                          Text(m['content'] ?? '', style: AppTextStyles.bodyMedium.copyWith(color: textPrimary)),
                        ])),
                        IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.red),
                            onPressed: () => _delete(m['id'])),
                      ]),
                    );
                  }),
    );
  }
}
