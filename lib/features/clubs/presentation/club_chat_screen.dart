import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/utils/chat_naming.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/user_model.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../../shared/widgets/user_details_sheet.dart';

/// One implicit chat room per club (no sub-channels, since a club has a
/// single membership list, not department-style sub-audiences) — same
/// 24h-expiry + anonymized-name pattern as dept_chat (see
/// `expire-club-messages` cron job and `anonymizedChatName`).
class ClubChatScreen extends StatefulWidget {
  final String clubId, clubName;
  final UserModel user;
  const ClubChatScreen({super.key, required this.clubId, required this.clubName, required this.user});
  @override State<ClubChatScreen> createState() => _ClubChatState();
}

class _ClubChatState extends State<ClubChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  Map<String, String> _designationByMember = {};
  bool _loading = true;
  RealtimeChannel? _realtimeChannel;

  @override
  void initState() { super.initState(); _loadMembers(); _loadMessages(); _subscribeRealtime(); }

  @override
  void dispose() { _msgCtrl.dispose(); _scrollCtrl.dispose(); _realtimeChannel?.unsubscribe(); super.dispose(); }

  Future<void> _loadMembers() async {
    try {
      final res = await SupabaseConfig.client.from('club_members')
          .select('member_id, role').eq('club_id', widget.clubId) as List;
      if (mounted) setState(() => _designationByMember = {
        for (final r in res.cast<Map<String, dynamic>>())
          r['member_id'] as String: r['role'] as String? ?? 'member',
      });
    } catch (_) {}
  }

  Future<void> _loadMessages() async {
    try {
      final res = await SupabaseConfig.client.from('club_messages')
          .select('*, profiles(full_name,avatar_url,role,university_id,department,is_verified,students(batch_label,section))')
          .eq('club_id', widget.clubId).order('created_at') as List;
      if (mounted) setState(() { _messages = res.cast(); _loading = false; });
      _scrollToBottom();
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _subscribeRealtime() {
    _realtimeChannel = SupabaseConfig.client.channel('club_chat_${widget.clubId}')
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public',
            table: 'club_messages', callback: (_) => _loadMessages())
        .subscribe();
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    _msgCtrl.clear();

    final tempId = 'temp-${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = {
      'id': tempId, 'club_id': widget.clubId, 'sender_id': SupabaseConfig.uid,
      'content': text, 'created_at': DateTime.now().toIso8601String(),
      'profiles': {
        'full_name': widget.user.fullName, 'avatar_url': widget.user.avatarUrl,
        'role': widget.user.role, 'university_id': widget.user.studentId,
        'department': widget.user.department,
        // See dept_chat_screen.dart's identical comment -- already passed
        // the app-wide is_verified gate if this account can send at all.
        'is_verified': true,
        'students': widget.user.batch != null || widget.user.section != null
            ? {'batch_label': widget.user.batch, 'section': widget.user.section} : null,
      },
    };
    setState(() => _messages = [..._messages, optimistic]);
    _scrollToBottom();

    try {
      final row = await SupabaseConfig.client.from('club_messages').insert({
        'club_id': widget.clubId, 'sender_id': SupabaseConfig.uid, 'content': text,
      }).select('*, profiles(full_name,avatar_url,role,university_id,department,students(batch_label,section))').single();
      if (mounted) setState(() {
        final idx = _messages.indexWhere((m) => m['id'] == tempId);
        if (idx != -1) _messages[idx] = row;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _messages.removeWhere((m) => m['id'] == tempId));
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceOf(context),
        title: Text(widget.clubName, style: AppTextStyles.headlineMed.copyWith(color: AppColors.textPrimaryOf(context))),
        iconTheme: IconThemeData(color: AppColors.textPrimaryOf(context)),
        bottom: PreferredSize(preferredSize: const Size.fromHeight(0.5),
            child: Divider(height: 0.5, color: AppColors.borderOf(context))),
      ),
      body: Column(children: [
        Container(width: double.infinity, color: AppColors.pink.withValues(alpha: 0.06),
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text('Messages disappear automatically after 24 hours',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondaryOf(context), fontSize: 11))),
        Expanded(child: _loading
            ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList(count: 6))
            : _messages.isEmpty
                ? Center(child: Text('No messages yet. Say hello! 👋',
                    style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context))))
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (ctx, i) {
                      final m = _messages[i];
                      final senderId = m['sender_id'] as String?;
                      return _ClubMsgBubble(
                          msg: m, isMe: senderId == SupabaseConfig.uid,
                          designation: _designationByMember[senderId],
                          showAvatar: i == 0 || _messages[i]['sender_id'] != _messages[i - 1]['sender_id'],
                          onDelete: senderId == SupabaseConfig.uid ? () => _delete(m['id'] as String) : null);
                    })),
        _ClubInputBar(ctrl: _msgCtrl, onSend: _send),
      ]),
    );
  }

  Future<void> _delete(String id) async {
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
    await SupabaseConfig.client.from('club_messages').delete().eq('id', id);
    _loadMessages();
  }
}

class _ClubMsgBubble extends StatelessWidget {
  final Map<String, dynamic> msg; final bool isMe, showAvatar;
  final String? designation; final VoidCallback? onDelete;
  const _ClubMsgBubble({required this.msg, required this.isMe, required this.showAvatar, this.designation, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final profile = msg['profiles'] as Map<String, dynamic>? ?? {};
    final content = msg['content'] as String? ?? '';
    final avatarUrl = profile['avatar_url'] as String?;
    final time = msg['created_at'] != null ? DateTime.tryParse(msg['created_at']) : null;
    final name = anonymizedChatName(profile, designation: designation);
    final isOfficer = designation != null && designation != 'member';

    // Same fix as dept_chat_screen.dart: a non-uniform Border (single left
    // side, for the officer accent stripe) combined with borderRadius
    // throws "A borderRadius can only be given on borders with uniform
    // colors" — moved the stripe out of Border into its own Container.
    final bubble = GestureDetector(
      onLongPress: isMe && onDelete != null ? onDelete : null,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
            gradient: isMe ? LinearGradient(colors: [AppColors.pink, AppColors.pink.withValues(alpha: 0.7)]) : null,
            color: isMe ? null : AppColors.surfaceOf(context),
            borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16), topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isMe ? 16 : 4), bottomRight: Radius.circular(isMe ? 4 : 16))),
        child: IntrinsicHeight(child: Row(children: [
          if (isOfficer && !isMe) Container(width: 2, color: AppColors.gold),
          Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Text(content, style: TextStyle(color: isMe ? Colors.white : AppColors.textPrimaryOf(context), fontSize: 14)))),
        ])),
      ),
    );

    final bubbleColumn = Column(crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
      if (showAvatar && !isMe) Padding(padding: const EdgeInsets.only(bottom: 4, left: 4),
          child: GestureDetector(
            onTap: () => showUserDetailsSheet(context, profile, designation: designation),
            child: Text(name, style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(context))),
          )),
      bubble,
      if (time != null) Padding(padding: const EdgeInsets.only(top: 3, left: 4, right: 4),
          child: Text(AppFormatters.time(time), style: AppTextStyles.labelSmall.copyWith(fontSize: 10, color: AppColors.textMutedOf(context)))),
    ]);

    if (isMe) return Padding(padding: const EdgeInsets.only(bottom: 6, left: 60), child: bubbleColumn);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6, right: 60),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        if (showAvatar) Padding(padding: const EdgeInsets.only(right: 8, bottom: 20),
            child: GestureDetector(
              onTap: () => showUserDetailsSheet(context, profile, designation: designation),
              child: CircleAvatar(radius: 14, backgroundColor: AppColors.pink.withValues(alpha: 0.15),
                backgroundImage: avatarUrl != null ? CachedNetworkImageProvider(avatarUrl) : null,
                child: avatarUrl == null ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(color: AppColors.pink, fontSize: 11, fontWeight: FontWeight.w700)) : null),
            ))
        else const SizedBox(width: 36),
        Expanded(child: bubbleColumn),
      ]),
    );
  }
}

class _ClubInputBar extends StatelessWidget {
  final TextEditingController ctrl; final VoidCallback onSend;
  const _ClubInputBar({required this.ctrl, required this.onSend});

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
                    borderSide: const BorderSide(color: AppColors.pink, width: 1.5)),
                filled: true, fillColor: AppColors.surfaceOf(context)),
            onSubmitted: (_) => onSend())),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onSend,
          child: Container(width: 44, height: 44,
              decoration: const BoxDecoration(color: AppColors.pink, shape: BoxShape.circle),
              child: const Icon(Icons.send_rounded, color: Colors.white, size: 20)),
        ),
      ]),
    );
  }
}
