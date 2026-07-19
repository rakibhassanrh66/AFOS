import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/feature_header.dart';
import '../../../shared/widgets/glass_chip.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../shell/presentation/top_app_bar.dart';

import '../../../shared/widgets/glass_bottom_nav.dart';
/// super_admin-only review queue for the feedback/contribution box — the
/// underlying `feedback` table previously had zero SELECT policy at all,
/// so every submission anyone ever sent was write-only and unreadable by
/// anyone, including admins. Attachments live in the private
/// `feedback-attachments` bucket, so a signed URL is generated per-file on
/// demand (public URLs don't work on a non-public bucket) rather than
/// stored — a stored URL would eventually expire anyway.
class ManageFeedbackScreen extends StatefulWidget {
  const ManageFeedbackScreen({super.key});
  @override State<ManageFeedbackScreen> createState() => _ManageFeedbackState();
}

class _ManageFeedbackState extends State<ManageFeedbackScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  String _filter = 'new';
  static const _filters = ['new', 'reviewed', 'actioned', 'all'];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await SupabaseConfig.client.from('feedback')
          .select('*, profiles!user_id(full_name,email,role)')
          .order('created_at', ascending: false) as List;
      if (mounted) setState(() { _items = res.cast(); _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  List<Map<String, dynamic>> get _visible =>
      _filter == 'all' ? _items : _items.where((i) => (i['status'] ?? 'new') == _filter).toList();

  Future<void> _setStatus(Map<String, dynamic> item, String status) async {
    try {
      await SupabaseConfig.client.from('feedback').update({
        'status': status, 'reviewed_by': SupabaseConfig.uid,
        'reviewed_at': DateTime.now().toIso8601String(),
      }).eq('id', item['id']);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
  }

  Future<void> _openAttachment(Map<String, dynamic> item) async {
    final path = item['file_url'] as String?;
    if (path == null) return;
    try {
      final signedUrl = await SupabaseConfig.client.storage
          .from('feedback-attachments').createSignedUrl(path, 300);
      await launchUrl(Uri.parse(signedUrl), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final confirm = await showDialog<bool>(
        context: context,
        builder: (dCtx) => AlertDialog(
              backgroundColor: AppColors.surfaceOf(dCtx),
              title: Text('Delete this submission?', style: TextStyle(color: AppColors.textPrimaryOf(dCtx))),
              content: Text('Removes it and its attached file permanently — this frees up storage.',
                  style: TextStyle(color: AppColors.textSecondaryOf(dCtx))),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Cancel')),
                TextButton(onPressed: () => Navigator.pop(dCtx, true), child: const Text('Delete', style: TextStyle(color: AppColors.red))),
              ],
            ));
    if (confirm != true) return;
    try {
      final path = item['file_url'] as String?;
      if (path != null) {
        await SupabaseConfig.client.storage.from('feedback-attachments').remove([path]);
      }
      await SupabaseConfig.client.from('feedback').delete().eq('id', item['id']);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const AfosAppBar(title: 'Feedback & Contributions'),
      body: Column(children: [
        FeatureHeader(
          title: 'Feedback & Contributions',
          subtitle: _loading ? 'Loading…' : '${_items.length} submissions total',
          icon: Icons.feedback_rounded,
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [AppColors.holoviolet, AppColors.indigo]),
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        ),
        SizedBox(height: 48, child: ListView(scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: _filters.map((f) {
              final sel = f == _filter;
              return Padding(padding: const EdgeInsets.only(right: 8),
                child: Center(child: GlassChip(
                  label: f[0].toUpperCase() + f.substring(1),
                  selected: sel,
                  color: AppColors.holoviolet,
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
                    ? ListView(children: [EmptyState(icon: Icons.feedback_outlined, title: 'Nothing here', subtitle: 'Nothing in "$_filter" right now')])
                    : RefreshIndicator(onRefresh: _load, color: AppColors.holoviolet,
                        child: ListView.builder(padding: const EdgeInsets.fromLTRB(16, 16, 16, 16 + GlassBottomNav.navContentClearance), itemCount: _visible.length,
                        itemBuilder: (ctx, i) {
                          final item = _visible[i];
                          final profile = item['profiles'] as Map<String, dynamic>? ?? {};
                          final status = item['status'] as String? ?? 'new';
                          final createdAt = item['created_at'] != null ? DateTime.tryParse(item['created_at']) : null;
                          return Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppColors.borderOf(context), width: 0.5)),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Expanded(child: Text(item['title'] as String? ?? '(no title)',
                                      style: AppTextStyles.titleMedium.copyWith(color: textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(color: AppColors.holoviolet.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                                      child: Text(status.toUpperCase(), textHeightBehavior: const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
                                          style: const TextStyle(color: AppColors.holoviolet, fontSize: 10, height: 1.0, fontWeight: FontWeight.w700))),
                                  IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.red), onPressed: () => _delete(item)),
                                ]),
                                Row(children: [
                                  Expanded(child: Text('${profile['full_name'] ?? 'Unknown'} · ${profile['email'] ?? ''}',
                                      style: AppTextStyles.labelSmall.copyWith(color: textSecondary),
                                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                                  if (createdAt != null) Text(AppFormatters.relativeTime(createdAt),
                                      style: AppTextStyles.labelSmall.copyWith(color: AppColors.textMutedOf(context), fontSize: 10)),
                                ]),
                                const SizedBox(height: 6),
                                Text(item['message'] ?? '', style: AppTextStyles.bodyMedium.copyWith(color: textPrimary)),
                                if (item['file_url'] != null) Padding(padding: const EdgeInsets.only(top: 8),
                                    child: OutlinedButton.icon(
                                        onPressed: () => _openAttachment(item),
                                        icon: const Icon(Icons.attach_file_rounded, size: 14),
                                        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 32), padding: const EdgeInsets.symmetric(horizontal: 10)),
                                        label: Text(item['file_name'] as String? ?? 'Attachment', style: const TextStyle(fontSize: 12)))),
                                if (status != 'all') Padding(padding: const EdgeInsets.only(top: 10),
                                    child: Row(children: [
                                      if (status == 'new')
                                        TextButton(onPressed: () => _setStatus(item, 'reviewed'), child: const Text('Mark Reviewed')),
                                      const Spacer(),
                                      if (status != 'actioned')
                                        OutlinedButton(onPressed: () => _setStatus(item, 'actioned'),
                                            style: OutlinedButton.styleFrom(foregroundColor: AppColors.green, side: const BorderSide(color: AppColors.green), minimumSize: const Size(64, 36)),
                                            child: const Text('Mark Actioned')),
                                    ])),
                              ]));
                        }),
                      ),
        ),
      ]),
    );
  }
}
