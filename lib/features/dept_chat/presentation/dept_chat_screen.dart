import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/user_model.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../shell/presentation/top_app_bar.dart';

class DeptChatScreen extends StatefulWidget {
  const DeptChatScreen({super.key});
  @override State<DeptChatScreen> createState() => _DeptChatState();
}

class _DeptChatState extends State<DeptChatScreen> {
  UserModel? _user;
  List<Map<String, dynamic>> _channels = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) { setState(() => _loading = false); return; }
    try {
      final p = await SupabaseConfig.client.from('profiles').select().eq('id', uid).single();
      final user = UserModel.fromJson(p);
      final channels = await SupabaseConfig.client.from('dept_channels')
          .select().eq('department', user.department)
          .order('channel_name') as List;
      if (mounted) setState(() {
        _user = user;
        _channels = channels.cast();
      });
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AfosAppBar(title: _user != null ? '${_user!.department} Channels' : 'Dept Chat'),
      body: _loading
          ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList())
          : _channels.isEmpty
              ? _EmptyChannels(dept: _user?.department ?? '')
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _channels.length,
                  itemBuilder: (ctx, i) => _ChannelTile(
                      channel: _channels[i], user: _user!, index: i)),
    );
  }
}

class _EmptyChannels extends StatelessWidget {
  final String dept;
  const _EmptyChannels({required this.dept});
  @override
  Widget build(BuildContext context) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(Icons.chat_bubble_outline_rounded, color: AppColors.textMutedOf(context), size: 56),
    const SizedBox(height: 16),
    Text('No channels for $dept yet', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context))),
    const SizedBox(height: 8),
    Text('Channels are created by department admins', style: TextStyle(color: AppColors.textMutedOf(context), fontSize: 12)),
  ]));
}

class _ChannelTile extends StatelessWidget {
  final Map<String, dynamic> channel; final UserModel user; final int index;
  const _ChannelTile({required this.channel, required this.user, required this.index});

  static const _channelColors = {
    'general': AppColors.blue, 'notices': AppColors.red,
    'academic': AppColors.green, 'events': AppColors.purple,
  };

  @override
  Widget build(BuildContext context) {
    final name = channel['channel_name'] as String? ?? 'general';
    final color = _channelColors[name] ?? AppColors.indigo;
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => _ChatRoomScreen(channel: channel, user: user))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borderOf(context), width: 0.5)),
        child: Row(children: [
          Container(width: 44, height: 44,
              decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
              child: Center(child: Text('#', style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w800)))),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('#$name', style: AppTextStyles.titleLarge.copyWith(color: AppColors.textPrimaryOf(context))),
            Text(channel['description'] ?? 'Department channel', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context))),
          ])),
          Icon(Icons.chevron_right_rounded, color: AppColors.textSecondaryOf(context)),
        ]),
      ),
    ).animate(delay: Duration(milliseconds: index * 60)).fadeIn().slideX(begin: -0.05);
  }
}

class _ChatRoomScreen extends StatefulWidget {
  final Map<String, dynamic> channel; final UserModel user;
  const _ChatRoomScreen({required this.channel, required this.user});
  @override State<_ChatRoomScreen> createState() => _ChatRoomState();
}

class _ChatRoomState extends State<_ChatRoomScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  RealtimeChannel? _realtimeChannel;

  @override
  void initState() { super.initState(); _loadMessages(); _subscribeRealtime(); }

  @override
  void dispose() {
    _msgCtrl.dispose(); _scrollCtrl.dispose();
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    try {
      final res = await SupabaseConfig.client.from('dept_messages')
          .select('*, profiles(full_name,avatar_url,role)')
          .eq('channel_id', widget.channel['id'])
          .order('created_at') as List;
      if (mounted) setState(() { _messages = res.cast(); _loading = false; });
      _scrollToBottom();
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  void _subscribeRealtime() {
    _realtimeChannel = SupabaseConfig.client
        .channel('dept_chat_${widget.channel['id']}')
        .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public', table: 'dept_messages',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'channel_id', value: widget.channel['id']),
            callback: (payload) {
              _loadMessages();
            })
        .subscribe();
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    _msgCtrl.clear();
    try {
      await SupabaseConfig.client.from('dept_messages').insert({
        'channel_id': widget.channel['id'], 'sender_id': SupabaseConfig.uid,
        'content': text, 'message_type': 'text',
      });
    } catch (_) {}
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    });
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.channel['channel_name'] as String? ?? 'chat';
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceOf(context),
        title: Text('#$name', style: AppTextStyles.headlineMed.copyWith(color: AppColors.textPrimaryOf(context))),
        iconTheme: IconThemeData(color: AppColors.textPrimaryOf(context)),
        actions: [Icon(Icons.push_pin_outlined, color: AppColors.textSecondaryOf(context)), const SizedBox(width: 16)],
        bottom: PreferredSize(preferredSize: const Size.fromHeight(0.5),
            child: Divider(height: 0.5, color: AppColors.borderOf(context))),
      ),
      body: Column(children: [
        Expanded(child: _loading
            ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList(count: 6))
            : _messages.isEmpty
                ? Center(child: Text('No messages yet. Say hello! 👋',
                    style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context))))
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (ctx, i) => _MsgBubble(
                        msg: _messages[i], isMe: _messages[i]['sender_id'] == SupabaseConfig.uid,
                        showAvatar: i == 0 || _messages[i]['sender_id'] != _messages[i - 1]['sender_id']))),
        _InputBar(ctrl: _msgCtrl, onSend: _send),
      ]),
    );
  }
}

class _MsgBubble extends StatelessWidget {
  final Map<String, dynamic> msg; final bool isMe, showAvatar;
  const _MsgBubble({required this.msg, required this.isMe, required this.showAvatar});

  @override
  Widget build(BuildContext context) {
    final profile = msg['profiles'] as Map<String, dynamic>? ?? {};
    final role = profile['role'] as String? ?? 'student';
    final isFaculty = role == 'faculty' || role == 'admin';
    final content = msg['content'] as String? ?? '';
    final time = msg['created_at'] != null ? DateTime.tryParse(msg['created_at']) : null;

    return Padding(
      padding: EdgeInsets.only(bottom: 6, left: isMe ? 60 : 0, right: isMe ? 0 : 60),
      child: Column(crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
        if (showAvatar && !isMe) Padding(padding: const EdgeInsets.only(bottom: 4, left: 4),
            child: Row(children: [
              Text(profile['full_name'] ?? '', style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(context))),
              if (isFaculty) Container(margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: AppColors.gold.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                  child: const Text('Faculty', style: TextStyle(color: AppColors.gold, fontSize: 9, fontWeight: FontWeight.w700))),
            ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
              gradient: isMe ? AppColors.blueGradient : null,
              color: isMe ? null : AppColors.surfaceOf(context),
              borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16), topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 4), bottomRight: Radius.circular(isMe ? 4 : 16)),
              border: isFaculty && !isMe ? const Border(left: BorderSide(color: AppColors.gold, width: 2)) : null),
          child: Text(content, style: TextStyle(color: isMe ? Colors.white : AppColors.textPrimaryOf(context), fontSize: 14)),
        ),
        if (time != null) Padding(padding: const EdgeInsets.only(top: 3, left: 4, right: 4),
            child: Text(AppFormatters.time(time), style: AppTextStyles.labelSmall.copyWith(fontSize: 10, color: AppColors.textMutedOf(context)))),
      ]),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController ctrl; final VoidCallback onSend;
  const _InputBar({required this.ctrl, required this.onSend});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceOf(context),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      child: Row(children: [
        Expanded(child: TextField(
            controller: ctrl,
            style: TextStyle(color: AppColors.textPrimaryOf(context), fontSize: 14),
            decoration: InputDecoration(
                hintText: 'Message...', contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: AppColors.borderOf(context), width: 0.5)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: AppColors.borderOf(context), width: 0.5)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24),
                    borderSide: const BorderSide(color: AppColors.blue, width: 1.5)),
                filled: true, fillColor: AppColors.surfaceOf(context)),
            onSubmitted: (_) => onSend(),
        )),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onSend,
          child: Container(width: 44, height: 44,
              decoration: BoxDecoration(gradient: AppColors.blueGradient, shape: BoxShape.circle),
              child: const Icon(Icons.send_rounded, color: Colors.white, size: 20)),
        ),
      ]),
    );
  }
}
