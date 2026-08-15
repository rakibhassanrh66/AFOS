import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/depth.dart';
import '../../../config/theme/liquid_glass_tokens.dart';
import '../../../config/theme/motion.dart';
import '../../../config/theme/spacing.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/utils/chat_naming.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/user_model.dart';
import '../../../shared/animations/page_transitions.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/feature_header.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../../shared/widgets/user_details_sheet.dart';
import '../../shell/presentation/top_app_bar.dart';

import '../../../core/layout/immersive_scope.dart';
import '../../../core/layout/nav_insets.dart';
class DeptChatScreen extends StatefulWidget {
  const DeptChatScreen({super.key});
  @override State<DeptChatScreen> createState() => _DeptChatState();
}

class _DeptChatState extends State<DeptChatScreen> {
  UserModel? _user;
  List<Map<String, dynamic>> _channels = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) { setState(() => _loading = false); return; }
    setState(() => _error = null);
    try {
      final p = await SupabaseConfig.client.from('profiles')
          .select('*, students(batch_label,section)').eq('id', uid).single();
      final user = UserModel.fromJson(p);
      final channels = await SupabaseConfig.client.from('dept_channels')
          .select().eq('department', user.department)
          .order('channel_name') as List;
      if (mounted) {
        setState(() {
        _user = user;
        _channels = channels.cast();
      });
      }
    } catch (e) {
      // Previously swallowed silently — a real load failure rendered
      // identically to "no channels for your department", same class of
      // bug found and fixed elsewhere this session.
      if (mounted) setState(() => _error = friendlyError(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AfosAppBar(title: _user != null ? '${_user!.department} Channels' : 'Dept Chat'),
      body: Column(children: [
        FeatureHeader(
          title: _user != null ? '${_user!.department} Channels' : 'Department Chat',
          subtitle: _loading ? 'Loading…' : '${_channels.length} channel${_channels.length == 1 ? '' : 's'} available',
          icon: Icons.forum_rounded,
          gradient: AppColors.holoGradient,
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        ).animate().fadeIn(duration: AppMotion.durationOf(context, AppMotion.base))
            .slideY(begin: -0.06, curve: AppMotion.standard),
        Expanded(child: _loading
            ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList())
            : _error != null
                ? ErrorView(message: _error!, onRetry: _load)
                : _channels.isEmpty
                ? _EmptyChannels(dept: _user?.department ?? '')
                : ListView.builder(
                    padding: EdgeInsets.fromLTRB(12, 0, 12, 12 + NavInsets.of(context)),
                    itemCount: _channels.length,
                    itemBuilder: (ctx, i) => _ChannelTile(
                        channel: _channels[i], user: _user!, index: i))),
      ]),
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

/// The channel row is the only thing you can press on this screen, so it is
/// the one element carrying the full press treatment (Law 6: one signature
/// element, everything else quiet).
class _ChannelTile extends StatefulWidget {
  final Map<String, dynamic> channel; final UserModel user; final int index;
  const _ChannelTile({required this.channel, required this.user, required this.index});

  static const _channelColors = {
    'general': AppColors.blue, 'notices': AppColors.red,
    'academic': AppColors.green, 'events': AppColors.teal,
    'student-lounge': AppColors.teal, 'faculty-room': AppColors.gold,
  };

  @override
  State<_ChannelTile> createState() => _ChannelTileState();
}

class _ChannelTileState extends State<_ChannelTile> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  void _open() {
    // On commit, not on touch-down: sliding off to cancel must not buzz.
    AppHaptics.selection();
    Navigator.push(context,
        appPageRoute(_ChatRoomScreen(channel: widget.channel, user: widget.user)));
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.channel['channel_name'] as String? ?? 'general';
    final audience = widget.channel['audience'] as String? ?? 'all';
    final color = _ChannelTile._channelColors[name] ?? AppColors.indigo;
    final audienceLabel = switch (audience) {
      'students' => 'Students only',
      'teachers' => 'Faculty only',
      _ => 'Everyone',
    };
    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: _open,
      child: AnimatedScale(
        scale: _pressed ? AppMotion.pressScale : 1.0,
        duration: AppMotion.durationOf(context, AppMotion.pressDuration),
        curve: AppMotion.standard,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: AppDepth.radius(1),
              border: Border.all(color: AppColors.borderOf(context), width: 0.5)),
          child: Row(children: [
            Container(width: 44, height: 44,
                decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                        colors: [color, color.withValues(alpha: 0.7)]),
                    borderRadius: AppDepth.radius(1),
                    boxShadow: [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 3))]),
                child: const Center(child: Text('#', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)))),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('#$name', style: AppTextStyles.titleLarge.copyWith(color: AppColors.textPrimaryOf(context))),
              Text(widget.channel['description'] ?? 'Department channel', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context))),
              const SizedBox(height: 4),
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: color.withValues(alpha:0.1), borderRadius: AppDepth.radius(0)),
                  child: Text(audienceLabel, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700))),
            ])),
            Icon(Icons.chevron_right_rounded, color: AppColors.textSecondaryOf(context)),
          ]),
        ),
      ),
    ).animate(delay: AppMotion.staggerFor(context, widget.index)).fadeIn().slideX(begin: -0.05);
  }
}

class _ChatRoomScreen extends StatefulWidget {
  final Map<String, dynamic> channel; final UserModel user;
  const _ChatRoomScreen({required this.channel, required this.user});
  @override State<_ChatRoomScreen> createState() => _ChatRoomState();

  static const _chatBackgrounds = {
    'default': Colors.transparent,
    'midnight': Color(0xFF0B1220),
    'forest': Color(0xFF0E1F16),
    'plum': Color(0xFF1F0E1B),
  };
}

class _ChatRoomState extends State<_ChatRoomScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  RealtimeChannel? _realtimeChannel;
  Color _chatBg = Colors.transparent;

  @override
  void initState() { super.initState(); _loadMessages(); _subscribeRealtime(); _loadChatBackground(); }

  Future<void> _loadChatBackground() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) return;
    try {
      final row = await SupabaseConfig.client.from('user_settings').select('chat_background').eq('profile_id', uid).maybeSingle();
      final key = row?['chat_background'] as String? ?? 'default';
      if (mounted) setState(() => _chatBg = _ChatRoomScreen._chatBackgrounds[key] ?? Colors.transparent);
    } catch (_) {}
  }

  @override
  void dispose() {
    _msgCtrl.dispose(); _scrollCtrl.dispose();
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    try {
      // Most-recent-first + limit, then reversed back to chronological order
      // for display — a plain ascending .order() with no bound re-fetched a
      // channel's ENTIRE history on every load (and again on every realtime
      // insert, since this is called from the subscription callback too).
      final res = await SupabaseConfig.client.from('dept_messages')
          .select('*, profiles(full_name,avatar_url,role,university_id,department,is_verified,'
              'students(batch_label,section),teachers(designation),staff(designation))')
          .eq('channel_id', widget.channel['id'])
          .order('created_at', ascending: false).limit(60) as List;
      if (mounted) {
        setState(() { _messages = res.cast<Map<String, dynamic>>().reversed.toList(); _loading = false; });
      }
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

    // Optimistic local append — the previous version relied entirely on the
    // realtime callback to show your own message, so if the postgres_changes
    // event didn't fire (or the publication wasn't set up), you only ever
    // saw it after leaving and re-entering the channel. This guarantees the
    // sender always sees their message immediately, independent of realtime.
    final tempId = 'temp-${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = {
      'id': tempId,
      'channel_id': widget.channel['id'],
      'sender_id': SupabaseConfig.uid,
      'content': text,
      'message_type': 'text',
      'created_at': DateTime.now().toIso8601String(),
      'profiles': {
        'full_name': widget.user.fullName,
        'avatar_url': widget.user.avatarUrl,
        'role': widget.user.role,
        'university_id': widget.user.studentId,
        'department': widget.user.department,
        // An account able to send a message here has already passed the
        // app-wide is_verified gate (pending_approval_screen blocks anyone
        // who hasn't) -- safe to assume true for this optimistic local echo
        // of your own just-sent message without a separate fetch.
        'is_verified': true,
        'students': widget.user.batch != null || widget.user.section != null
            ? {'batch_label': widget.user.batch, 'section': widget.user.section} : null,
      },
    };
    setState(() => _messages = [..._messages, optimistic]);
    // The optimistic append IS the commit from the sender's point of view —
    // this is the moment the message appears, so this is where the hand is told.
    AppHaptics.selection();
    _scrollToBottom();

    try {
      final row = await SupabaseConfig.client.from('dept_messages').insert({
        'channel_id': widget.channel['id'], 'sender_id': SupabaseConfig.uid,
        'content': text, 'message_type': 'text',
      }).select('*, profiles(full_name,avatar_url,role,university_id,department,students(batch_label,section))').single();
      if (mounted) {
        setState(() {
        final idx = _messages.indexWhere((m) => m['id'] == tempId);
        if (idx != -1) _messages[idx] = row;
      });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _messages.removeWhere((m) => m['id'] == tempId));
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to send: ${friendlyError(e)}'), backgroundColor: AppColors.red));
      }
    }
  }

  Future<void> _deleteMessage(String id) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dctx) => AlertDialog(
              title: const Text('Delete message?'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Cancel')),
                TextButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('Delete')),
              ],
            ));
    if (confirmed != true) return;
    AppHaptics.warning();
    await SupabaseConfig.client.from('dept_messages').delete().eq('id', id);
    _loadMessages();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // The callback can land after the route is popped; without this the
      // disposed ScrollController is touched and `context` is read off a
      // defunct State.
      if (!mounted || !_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: AppMotion.durationOf(context, AppMotion.base),
        curve: AppMotion.standard);
    });
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.channel['channel_name'] as String? ?? 'chat';
    final scaffold = Scaffold(
      backgroundColor: _chatBg == Colors.transparent ? Theme.of(context).scaffoldBackgroundColor : _chatBg,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceOf(context),
        title: Text('#$name', style: AppTextStyles.headlineMed.copyWith(color: AppColors.textPrimaryOf(context))),
        iconTheme: IconThemeData(color: AppColors.textPrimaryOf(context)),
        actions: [Icon(Icons.push_pin_outlined, color: AppColors.textSecondaryOf(context)), const SizedBox(width: 16)],
        bottom: PreferredSize(preferredSize: const Size.fromHeight(0.5),
            child: Divider(height: 0.5, color: AppColors.borderOf(context))),
      ),
      body: Column(children: [
        Container(width: double.infinity, color: AppColors.blue.withValues(alpha:0.06),
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text('Messages disappear automatically after 24 hours',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondaryOf(context), fontSize: 11))),
        Expanded(child: _loading
            ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList(count: 6))
            : _messages.isEmpty
                ? Center(child: Text('No messages in #$name yet. Start the conversation.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context))))
                : ListView.builder(
                    controller: _scrollCtrl,
                    // No bottom inset: _InputBar sits below this list and owns
                    // the bottom edge, so clearance here only opened a gap
                    // between the last message and the field.
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (ctx, i) => _MsgBubble(
                        msg: _messages[i], isMe: _messages[i]['sender_id'] == SupabaseConfig.uid,
                        showAvatar: i == 0 || _messages[i]['sender_id'] != _messages[i - 1]['sender_id'],
                        onDelete: () => _deleteMessage(_messages[i]['id'])))),
        _InputBar(ctrl: _msgCtrl, onSend: _send),
      ]),
    );

    // Only the CHANNEL is immersive, not the channel list above it — that one
    // is a top-level destination and must keep the nav. See
    // immersive_scope.dart.
    return ImmersiveScope(child: scaffold);
  }
}

class _MsgBubble extends StatelessWidget {
  final Map<String, dynamic> msg; final bool isMe, showAvatar;
  final VoidCallback? onDelete;
  const _MsgBubble({required this.msg, required this.isMe, required this.showAvatar, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final profile = msg['profiles'] as Map<String, dynamic>? ?? {};
    final role = profile['role'] as String? ?? 'student';
    final isFaculty = const ['teacher', 'admin', 'dept_admin', 'super_admin'].contains(role);
    final content = msg['content'] as String? ?? '';
    final avatarUrl = profile['avatar_url'] as String?;
    final time = msg['created_at'] != null ? DateTime.tryParse(msg['created_at']) : null;

    // A non-uniform Border (single left side, for the faculty accent
    // stripe) combined with borderRadius throws "A borderRadius can only
    // be given on borders with uniform colors" — this crashed every
    // faculty message bubble's render (confirmed the same root cause as
    // the notification-panel crash fixed earlier). The stripe is now a
    // separate Container instead of a Border side; IntrinsicHeight gives
    // it a real height to match the text, since the Row's own height is
    // otherwise unbounded inside a ListView item.
    final bubble = GestureDetector(
      onLongPress: isMe && onDelete != null ? onDelete : null,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
            gradient: isMe ? AppColors.blueGradient : null,
            color: isMe ? null : AppColors.surfaceOf(context),
            // A bubble's tail corner is real information — it says who spoke —
            // so the asymmetry stays. Both values are now rungs of the scale
            // (control 14 for the round corners, cut 8 for the tail) rather
            // than the free-hand 16/4.
            borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(LiquidGlass.radiusControl),
                topRight: const Radius.circular(LiquidGlass.radiusControl),
                bottomLeft: Radius.circular(isMe ? LiquidGlass.radiusControl : LiquidGlass.radiusCut),
                bottomRight: Radius.circular(isMe ? LiquidGlass.radiusCut : LiquidGlass.radiusControl))),
        child: IntrinsicHeight(child: Row(children: [
          if (isFaculty && !isMe) Container(width: 2, color: AppColors.gold),
          Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Text(content, style: TextStyle(color: isMe ? Colors.white : AppColors.textPrimaryOf(context), fontSize: 14)))),
        ])),
      ),
    );

    final bubbleColumn = Column(crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
      if (showAvatar && !isMe) Padding(padding: const EdgeInsets.only(bottom: 4, left: 4),
          child: GestureDetector(
            onTap: () => showUserDetailsSheet(context, profile),
            child: Row(children: [
              Flexible(child: Text(anonymizedChatName(profile), maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(context)))),
              if (isFaculty) Container(margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: AppColors.gold.withValues(alpha:0.15), borderRadius: AppDepth.radius(0)),
                  child: const Text('Faculty', style: TextStyle(color: AppColors.gold, fontSize: 9, fontWeight: FontWeight.w700))),
            ]),
          )),
      bubble,
      if (time != null) Padding(padding: const EdgeInsets.only(top: 3, left: 4, right: 4),
          child: Text(AppFormatters.time(time), style: AppTextStyles.labelSmall.copyWith(fontSize: 10, color: AppColors.textMutedOf(context)))),
    ]);

    if (isMe) {
      return Padding(padding: const EdgeInsets.only(bottom: 6, left: 60), child: bubbleColumn);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6, right: 60),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        if (showAvatar) Padding(padding: const EdgeInsets.only(right: 8, bottom: 20),
            child: GestureDetector(
              onTap: () => showUserDetailsSheet(context, profile),
              child: CircleAvatar(radius: 14, backgroundColor: AppColors.blue.withValues(alpha:0.15),
                backgroundImage: avatarUrl != null ? CachedNetworkImageProvider(avatarUrl) : null,
                child: avatarUrl == null
                    ? Text(((profile['full_name'] as String?)?.isNotEmpty == true
                            ? (profile['full_name'] as String)[0] : '?').toUpperCase(),
                        style: const TextStyle(color: AppColors.blue, fontSize: 11, fontWeight: FontWeight.w700))
                    : null),
              ),
            )
        else const SizedBox(width: 36),
        Expanded(child: bubbleColumn),
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
      padding: EdgeInsets.fromLTRB(12, 8, 12, 16 + NavInsets.of(context)),
      child: Row(children: [
        Expanded(child: TextField(
            controller: ctrl,
            style: TextStyle(color: AppColors.textPrimaryOf(context), fontSize: 14),
            decoration: InputDecoration(
                hintText: 'Message...', contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(LiquidGlass.radiusPill),
                    borderSide: BorderSide(color: AppColors.borderOf(context), width: 0.5)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(LiquidGlass.radiusPill),
                    borderSide: BorderSide(color: AppColors.borderOf(context), width: 0.5)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(LiquidGlass.radiusPill),
                    borderSide: const BorderSide(color: AppColors.blue, width: 1.5)),
                filled: true, fillColor: AppColors.surfaceOf(context)),
            onSubmitted: (_) => onSend(),
        )),
        const SizedBox(width: 8),
        _SendButton(onSend: onSend),
      ]),
    );
  }
}

class _SendButton extends StatefulWidget {
  final VoidCallback onSend;
  const _SendButton({required this.onSend});
  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        // The haptic is in _send, on the optimistic append, not here.
        onTap: widget.onSend,
        child: AnimatedScale(
          scale: _pressed ? AppMotion.pressScale : 1.0,
          duration: AppMotion.durationOf(context, AppMotion.pressDuration),
          curve: AppMotion.standard,
          // Was 44x44, under the 48dp touch floor.
          child: Container(
              width: AppSpace.minTouchTarget, height: AppSpace.minTouchTarget,
              decoration: const BoxDecoration(gradient: AppColors.blueGradient, shape: BoxShape.circle),
              child: const Icon(Icons.send_rounded, color: Colors.white, size: 20)),
        ),
      );
}
