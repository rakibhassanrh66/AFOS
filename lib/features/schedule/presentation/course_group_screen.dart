import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/liquid_glass_tokens.dart';
import '../../../core/services/realtime_channel.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/pill_badge.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../data/repositories/course_offering_repository.dart';
import '../../../core/layout/nav_insets.dart';

/// The group for ONE section of a course — keyed on the offering, so a
/// teacher running four sections gets four separate rooms rather than one
/// ~140-student channel where section-specific announcements get lost.
///
/// Membership is not a separate concept here: `can_access_course_group`
/// (see the 20260725140000 migration) grants access to the offering's
/// teacher and to any student with an approved enrollment, which is exactly
/// the same predicate the RLS policies use. Unlike dept/club chat, names are
/// NOT anonymised — a class group is a room where the teacher and students
/// already know each other, and an anonymous handle would make it useless
/// for a teacher trying to reach a specific student.
class CourseGroupScreen extends StatefulWidget {
  final Map<String, dynamic> offering;
  const CourseGroupScreen({super.key, required this.offering});
  @override
  State<CourseGroupScreen> createState() => _CourseGroupScreenState();
}

class _CourseGroupScreenState extends State<CourseGroupScreen> {
  final _repo = CourseOfferingRepository();
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _refresh = RealtimeRefresh();

  List<Map<String, dynamic>> _messages = [];
  Map<String, dynamic>? _cr;
  bool _loading = true;
  RealtimeChannel? _channel;

  String get _offeringId => widget.offering['id'] as String;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _loadCr();
    _subscribe();
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _refresh.dispose();
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadCr() async {
    final cr = await _repo.findOfferingCr(widget.offering);
    if (mounted) setState(() => _cr = cr);
  }

  Future<void> _loadMessages() async {
    try {
      final msgs = await _repo.fetchCourseMessages(_offeringId);
      if (mounted) setState(() { _messages = msgs; _loading = false; });
      _scrollToBottom();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// `screenChannel` because this screen lives under the ShellRoute, which
  /// keeps pushed-under State alive — two mounted instances sharing one topic
  /// means the first dispose() tears realtime down for the survivor.
  ///
  /// The filter matters too: club_chat subscribes with no filter at all, so
  /// every club's insert triggers a full reload there. Scoping to this
  /// offering keeps the reload to messages that actually belong here.
  void _subscribe() {
    _channel = SupabaseConfig.client
        .channel(screenChannel('course_group_$_offeringId', this))
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'course_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'offering_id',
            value: _offeringId,
          ),
          callback: (_) => _refresh.schedule(_loadMessages),
        )
        .subscribe();
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    _msgCtrl.clear();

    // Optimistic append so the bubble appears instantly; rolled back if the
    // insert fails (same approach as dept/club chat).
    final tempId = 'temp-${DateTime.now().microsecondsSinceEpoch}';
    setState(() => _messages = [
          ..._messages,
          {
            'id': tempId,
            'offering_id': _offeringId,
            'sender_id': SupabaseConfig.uid,
            'content': text,
            'created_at': DateTime.now().toIso8601String(),
            'profiles': const {'full_name': 'You'},
          }
        ]);
    _scrollToBottom();

    try {
      await _repo.sendCourseMessage(_offeringId, text);
      await _loadMessages();
    } catch (e) {
      if (mounted) {
        setState(() => _messages.removeWhere((m) => m['id'] == tempId));
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
  }

  Future<void> _delete(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Delete message?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await _repo.deleteCourseMessage(id);
    await _loadMessages();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
            duration: LiquidGlass.motionStandard, curve: LiquidGlass.motionCurve);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final course = widget.offering['courses'] as Map<String, dynamic>? ?? const {};
    final title = '${course['code'] ?? 'Course'} · Sec ${widget.offering['section'] ?? '—'}';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceOf(context),
        iconTheme: IconThemeData(color: AppColors.textPrimaryOf(context)),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: AppTextStyles.titleLarge.copyWith(color: AppColors.textPrimaryOf(context))),
          Text('Batch ${widget.offering['batch'] ?? '—'}',
              style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(context))),
        ]),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Divider(height: 0.5, color: AppColors.borderOf(context)),
        ),
      ),
      body: Column(children: [
        Container(
          width: double.infinity,
          color: AppColors.blue.withValues(alpha: 0.06),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Flexible(
              child: Text(
                _cr == null
                    ? 'Messages disappear automatically after 24 hours'
                    : 'CR: ${_cr!['full_name']} · messages clear after 24h',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondaryOf(context), fontSize: 11),
              ),
            ),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList(count: 6))
              : _messages.isEmpty
                  ? Center(
                      child: Text('No messages yet. Say hello! 👋',
                          style: AppTextStyles.bodyMedium
                              .copyWith(color: AppColors.textSecondaryOf(context))))
                  : ListView.builder(
                      controller: _scrollCtrl,
                      padding: NavInsets.content(context),
                      itemCount: _messages.length,
                      itemBuilder: (ctx, i) {
                        final m = _messages[i];
                        final senderId = m['sender_id'] as String?;
                        return _CourseMsgBubble(
                          msg: m,
                          isMe: senderId == SupabaseConfig.uid,
                          isTeacher: senderId == widget.offering['teacher_id'],
                          isCr: _cr != null && senderId == _cr!['id'],
                          showName: i == 0 || _messages[i - 1]['sender_id'] != senderId,
                          onDelete: senderId == SupabaseConfig.uid
                              ? () => _delete(m['id'] as String)
                              : null,
                        );
                      }),
        ),
        _InputBar(ctrl: _msgCtrl, onSend: _send),
      ]),
    );
  }
}

class _CourseMsgBubble extends StatelessWidget {
  final Map<String, dynamic> msg;
  final bool isMe, isTeacher, isCr, showName;
  final VoidCallback? onDelete;
  const _CourseMsgBubble({
    required this.msg,
    required this.isMe,
    required this.isTeacher,
    required this.isCr,
    required this.showName,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final profile = msg['profiles'] as Map<String, dynamic>? ?? const {};
    final name = profile['full_name'] as String? ?? 'Someone';
    final avatarUrl = profile['avatar_url'] as String?;
    final content = msg['content'] as String? ?? '';
    final time = msg['created_at'] != null ? DateTime.tryParse(msg['created_at']) : null;

    final bubble = GestureDetector(
      onLongPress: onDelete,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: isMe ? AppColors.blue : AppColors.surfaceOf(context),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(content,
              style: TextStyle(
                  color: isMe ? Colors.white : AppColors.textPrimaryOf(context), fontSize: 14)),
        ),
      ),
    );

    final column = Column(
      crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (showName && !isMe)
          Padding(
            padding: const EdgeInsets.only(bottom: 4, left: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(name,
                  style: AppTextStyles.labelSmall
                      .copyWith(color: AppColors.textSecondaryOf(context))),
              if (isTeacher) ...[
                const SizedBox(width: 6),
                const PillBadge(label: 'TEACHER', color: AppColors.green),
              ] else if (isCr) ...[
                const SizedBox(width: 6),
                const PillBadge(label: 'CR', color: AppColors.amber),
              ],
            ]),
          ),
        bubble,
        if (time != null)
          Padding(
            padding: const EdgeInsets.only(top: 3, left: 4, right: 4),
            child: Text(AppFormatters.time(time),
                style: AppTextStyles.labelSmall
                    .copyWith(fontSize: 10, color: AppColors.textMutedOf(context))),
          ),
      ],
    );

    if (isMe) {
      return Padding(padding: const EdgeInsets.only(bottom: 6, left: 60), child: column);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, right: 60),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        if (showName)
          Padding(
            padding: const EdgeInsets.only(right: 8, bottom: 20),
            child: CircleAvatar(
              radius: 14,
              backgroundColor: AppColors.blue.withValues(alpha: 0.15),
              backgroundImage: avatarUrl != null ? CachedNetworkImageProvider(avatarUrl) : null,
              child: avatarUrl == null
                  ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(
                          color: AppColors.blue, fontSize: 11, fontWeight: FontWeight.w700))
                  : null,
            ),
          )
        else
          const SizedBox(width: 36),
        Expanded(child: column),
      ]),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController ctrl;
  final VoidCallback onSend;
  const _InputBar({required this.ctrl, required this.onSend});

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color c, double w) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: c, width: w));

    return Container(
      color: AppColors.surfaceOf(context),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: ctrl,
            maxLength: 2000,
            style: TextStyle(color: AppColors.textPrimaryOf(context), fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Message your class…',
              counterText: '',
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: border(AppColors.borderOf(context), 0.5),
              enabledBorder: border(AppColors.borderOf(context), 0.5),
              focusedBorder: border(AppColors.blue, 1.5),
              filled: true,
              fillColor: AppColors.surfaceOf(context),
            ),
            onSubmitted: (_) => onSend(),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onSend,
          child: Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(color: AppColors.blue, shape: BoxShape.circle),
            child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
          ),
        ),
      ]),
    );
  }
}
