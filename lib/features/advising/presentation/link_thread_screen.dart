import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/depth.dart';
import '../../../config/theme/spacing.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/services/realtime_channel.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../shared/widgets/afos_text_field.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../shell/presentation/top_app_bar.dart';
import '../data/repositories/advising_repository.dart';

/// The conversation between a student and their advisor or supervisor.
///
/// One thread for both kinds — the row-level policy on
/// `teacher_link_messages` only admits the two parties of an ACTIVE link, so
/// a pending request has no thread and neither does an ended one. That rule is
/// enforced in the database; nothing here re-checks it, because a second copy
/// of a rule is a second place for it to be wrong.
class LinkThreadScreen extends StatefulWidget {
  final String linkId;
  final String title;

  const LinkThreadScreen({super.key, required this.linkId, required this.title});

  @override
  State<LinkThreadScreen> createState() => _LinkThreadScreenState();
}

class _LinkThreadScreenState extends State<LinkThreadScreen> {
  final _repo = AdvisingRepository();
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();

  List<Map<String, dynamic>> _messages = const [];
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
        .channel(screenChannel('link_thread_${widget.linkId}', this))
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'teacher_link_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'link_id',
            value: widget.linkId,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            if (!mounted) return;
            // Skip our own echo: the optimistic append below already put it on
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
      final rows = await _repo.messages(widget.linkId);
      if (!mounted) return;
      setState(() {
        _messages = rows;
        _loading = false;
        _error = null;
      });
      _jumpToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyError(e);
      });
    }
  }

  Future<void> _send() async {
    final body = _ctrl.text.trim();
    final uid = _uid;
    if (body.isEmpty || uid == null || _sending) return;

    setState(() => _sending = true);
    // Optimistic: the message appears immediately and the realtime echo for
    // our own id is skipped above, so it never doubles.
    final optimistic = <String, dynamic>{
      'sender_id': uid,
      'body': body,
      'created_at': DateTime.now().toIso8601String(),
    };
    setState(() => _messages = [..._messages, optimistic]);
    _ctrl.clear();
    _jumpToEnd();

    try {
      await _repo.send(widget.linkId, uid, body);
      AppHaptics.success();
    } catch (e) {
      if (!mounted) return;
      // Put the text back rather than losing it, and take the failed bubble
      // away — a message that looks sent and never arrived is worse than one
      // that plainly failed.
      setState(() {
        _messages = _messages.where((m) => !identical(m, optimistic)).toList();
        _ctrl.text = body;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AfosAppBar(title: widget.title),
      body: Column(children: [
        Expanded(child: _body()),
        SafeArea(
          top: false,
          child: Padding(
            padding: AppSpace.allMd,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: AfosTextField(
                  hint: 'Write a message',
                  controller: _ctrl,
                  maxLines: 4,
                  onSubmitted: (_) => _send(),
                ),
              ),
              AppSpace.gapSm,
              // A fixed 48px target, which is the constitution's minimum and
              // the reason this is not an IconButton with default padding.
              SizedBox(
                width: AppSpace.minTouchTarget,
                height: AppSpace.minTouchTarget,
                child: Material(
                  color: AppColors.accentOf(context),
                  borderRadius: AppDepth.radius(1),
                  child: InkWell(
                    borderRadius: AppDepth.radius(1),
                    onTap: _sending ? null : _send,
                    child: const Icon(Icons.send_rounded,
                        size: 20, color: Colors.white),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Padding(padding: EdgeInsets.all(16), child: ShimmerList());
    }
    if (_error != null) {
      return ErrorView(message: _error!, onRetry: _load);
    }
    if (_messages.isEmpty) {
      return const EmptyState(
        icon: Icons.forum_outlined,
        title: 'No messages yet',
        subtitle: 'Say hello. Whatever you write here is between the two of you.',
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: AppSpace.allMd,
      itemCount: _messages.length,
      itemBuilder: (ctx, i) {
        final m = _messages[i];
        final mine = m['sender_id'] == _uid;
        return Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            // Capped so a long message wraps inside its bubble instead of
            // stretching the bubble to the full width of a tablet.
            constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.78),
            margin: const EdgeInsets.only(bottom: AppSpace.sm),
            padding: AppSpace.allMd,
            decoration: BoxDecoration(
              color: mine
                  ? AppColors.accentOf(context)
                  : AppColors.glassFill(context),
              borderRadius: AppDepth.radius(1),
            ),
            child: Text(
              (m['body'] as String?) ?? '',
              style: AppTextStyles.bodyLarge.copyWith(
                  color: mine
                      ? Colors.white
                      : AppColors.textPrimaryOf(context)),
            ),
          ),
        );
      },
    );
  }
}
