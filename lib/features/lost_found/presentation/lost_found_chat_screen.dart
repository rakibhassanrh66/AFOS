import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/depth.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/services/realtime_channel.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../shell/presentation/top_app_bar.dart';

/// The 24-hour thread between the two people in one handover.
///
/// WHY IT EXPIRES, AND HOW. "Where are you?" / "I'm at the library gate" is
/// useful for an afternoon and is a permanent record of two students' movements
/// forever after. The window closes 24 hours after the claim was accepted, and
/// it closes **in the RLS predicate** (`lost_found_thread_open`), not in a
/// cleanup job — so an expired thread is unreadable the moment it expires,
/// whether or not any row was ever deleted. "It disappears within 24 hours" is
/// a property of the database rather than a promise about a cron that may not
/// have run.
///
/// There is no UPDATE and no DELETE policy on the table, for anyone. An
/// agreement about where to meet is evidence, and evidence one side can edit
/// afterwards is worth less than none.
class LostFoundChatScreen extends StatefulWidget {
  final String postId;
  final String itemTitle;
  final String otherName;

  const LostFoundChatScreen({
    super.key,
    required this.postId,
    required this.itemTitle,
    required this.otherName,
  });

  @override
  State<LostFoundChatScreen> createState() => _LostFoundChatScreenState();
}

class _LostFoundChatScreenState extends State<LostFoundChatScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;
  RealtimeChannel? _sub;

  String? get _uid => SupabaseConfig.uid;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = SupabaseConfig.client
        .channel(screenChannel('lf_thread_${widget.postId}', this))
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'lost_found_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'post_id',
            value: widget.postId,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            if (!mounted) return;
            // Skip our own echo: the optimistic append already put it on
            // screen, and adding it again would show the message twice.
            if (row['sender_id'] == _uid) return;
            setState(() => _messages = [..._messages, row]);
            _jumpToEnd();
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _sub?.unsubscribe();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _jumpToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _load() async {
    try {
      final res = await SupabaseConfig.client
          .from('lost_found_messages')
          .select('id, sender_id, body, created_at')
          .eq('post_id', widget.postId)
          .order('created_at') as List;
      if (!mounted) return;
      setState(() {
        _messages = res.cast<Map<String, dynamic>>();
        _loading = false;
      });
      _jumpToEnd();
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  Future<void> _send() async {
    final body = _ctrl.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);

    // Optimistic append, the same pattern the club chat uses: the message is
    // on screen before the round trip, so a slow campus connection does not
    // read as a dropped message. If the insert fails it is removed again and
    // the text is handed back rather than silently lost.
    final pending = {
      'id': 'pending-${DateTime.now().microsecondsSinceEpoch}',
      'sender_id': _uid,
      'body': body,
      'created_at': DateTime.now().toIso8601String(),
    };
    setState(() => _messages = [..._messages, pending]);
    _ctrl.clear();
    _jumpToEnd();

    try {
      await SupabaseConfig.client.from('lost_found_messages').insert({
        'post_id': widget.postId,
        'sender_id': _uid,
        'body': body,
      });
      // On COMMIT — the server accepted it — not on the tap.
      AppHaptics.selection();
      if (mounted) setState(() => _sending = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages = _messages.where((m) => m['id'] != pending['id']).toList();
        _sending = false;
      });
      _ctrl.text = body;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(friendlyError(e)), backgroundColor: AppColors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AfosAppBar(title: widget.otherName),
      body: Column(children: [
        // The expiry is stated, not implied. A thread that vanishes with no
        // warning reads as a bug; one that says so reads as a decision.
        Container(
          width: double.infinity,
          margin: const EdgeInsetsDirectional.fromSTEB(16, 10, 16, 6),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.amber.withValues(alpha: 0.10),
            borderRadius: AppDepth.radius(1),
            border: Border.all(color: AppColors.amber.withValues(alpha: 0.28)),
          ),
          child: Text(
            'About "${widget.itemTitle}". This conversation is only open for '
            '24 hours after the claim was accepted, then it closes for both of '
            'you. Arrange where to meet — do not send anything you need to keep.',
            style: AppTextStyles.labelSmall
                .copyWith(color: AppColors.textSecondaryOf(context)),
          ),
        ),
        Expanded(
          child: _loading
              ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList())
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(_error!,
                            textAlign: TextAlign.center,
                            style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.textSecondaryOf(context))),
                      ),
                    )
                  : _messages.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              'Say hello and agree where to meet.',
                              textAlign: TextAlign.center,
                              style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.textSecondaryOf(context)),
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          itemCount: _messages.length,
                          itemBuilder: (ctx, i) {
                            final m = _messages[i];
                            return _Bubble(
                              body: m['body'] as String? ?? '',
                              mine: m['sender_id'] == _uid,
                              at: DateTime.tryParse(
                                  m['created_at'] as String? ?? ''),
                            );
                          },
                        ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 1000,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  style: TextStyle(color: AppColors.textPrimaryOf(context)),
                  decoration: InputDecoration(
                    hintText: 'Message',
                    counterText: '',
                    filled: true,
                    fillColor: AppColors.glassFill(context),
                    border: OutlineInputBorder(
                        borderRadius: AppDepth.radius(1),
                        borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _sending ? null : _send,
                style: IconButton.styleFrom(backgroundColor: AppColors.holoviolet),
                icon: const Icon(Icons.send_rounded, size: 20),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  final String body;
  final bool mine;
  final DateTime? at;
  const _Bubble({required this.body, required this.mine, this.at});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.75),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: mine
              ? AppColors.holoviolet.withValues(alpha: 0.18)
              : AppColors.surfaceOf(context),
          borderRadius: AppDepth.radius(1),
          border: Border.all(
              color: mine
                  ? AppColors.holoviolet.withValues(alpha: 0.32)
                  : AppColors.borderOf(context),
              width: 0.5),
        ),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(body,
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textPrimaryOf(context))),
            if (at != null) ...[
              const SizedBox(height: 3),
              Text(AppFormatters.relativeTime(at!),
                  style: TextStyle(
                      color: AppColors.textMutedOf(context), fontSize: 10)),
            ],
          ],
        ),
      ),
    );
  }
}
