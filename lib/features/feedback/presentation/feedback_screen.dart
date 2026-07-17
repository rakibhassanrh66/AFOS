import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../config/app_config.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/services/outbox_service.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/afos_text_field.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/feature_header.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../shell/presentation/top_app_bar.dart';

/// Open to every user (unlike ManageFeedbackScreen, which is the
/// super_admin-only moderation queue for the same `feedback` table) — a
/// place to share an idea or contribution plan and see the status of what
/// you've already sent, moderated by super_admin. The submission flow
/// itself already existed buried under Settings > Account > "Send
/// Feedback"; this makes it a first-class, discoverable destination and
/// adds the "what happened to what I sent" visibility that was missing.
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});
  @override State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  List<Map<String, dynamic>> _mine = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final uid = SupabaseConfig.uid;
    if (uid == null) { setState(() => _loading = false); return; }
    try {
      final res = await SupabaseConfig.client.from('feedback')
          .select().eq('user_id', uid).order('created_at', ascending: false) as List;
      if (mounted) setState(() { _mine = res.cast(); _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  void _showSubmitSheet() {
    final titleCtrl = TextEditingController();
    final ctrl = TextEditingController();
    PlatformFile? attachment;
    bool saving = false;
    showModalBottomSheet(context: context, isScrollControlled: true,
        backgroundColor: AppColors.surfaceOf(context),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (sheetCtx) => StatefulBuilder(builder: (sheetCtx, setSheetState) => SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(sheetCtx).viewInsets.bottom + 24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Share an idea', style: AppTextStyles.headlineLarge.copyWith(color: AppColors.textPrimaryOf(sheetCtx))),
              const SizedBox(height: 6),
              Text('Have an idea to make the app better, or a plan you want to contribute? Share it here — attach a document if you have one.',
                  style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(sheetCtx))),
              const SizedBox(height: 16),
              AfosTextField(hint: 'Title (optional)', controller: titleCtrl),
              const SizedBox(height: 12),
              AfosTextField(hint: 'Tell us what you think...', controller: ctrl, maxLines: 4),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  // withData: true -- on web, PlatformFile.path is always
                  // unavailable (merely accessing it throws); .bytes is the
                  // only cross-platform way to read what was picked.
                  final res = await FilePicker.platform.pickFiles(
                      type: FileType.custom, allowedExtensions: ['pdf', 'doc', 'docx', 'png', 'jpg', 'jpeg', 'zip', 'txt'],
                      withData: true);
                  if (res != null) setSheetState(() => attachment = res.files.first);
                },
                icon: const Icon(Icons.attach_file_rounded, size: 16),
                label: Text(attachment == null ? 'Attach a file (optional)' : attachment!.name,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(height: 20),
              AfosButton(label: 'Submit', loading: saving, onTap: () async {
                if (ctrl.text.trim().isEmpty) return;
                setSheetState(() => saving = true);
                try {
                  final file = attachment;
                  final payload = {
                    'user_id': SupabaseConfig.uid,
                    'title': titleCtrl.text.trim().isEmpty ? null : titleCtrl.text.trim(),
                    'message': ctrl.text.trim(),
                    'app_version': AppConfig.appVersion,
                    if (file != null && file.bytes != null) 'file_bytes_base64': base64Encode(file.bytes!),
                    if (file != null) 'file_name': file.name,
                  };
                  final queued = await OutboxService.instance.submitOrQueue('feedback_submit', payload);
                  if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(queued
                        ? const SnackBar(content: Text("Saved — will send when you're back online"), backgroundColor: AppColors.amber)
                        : const SnackBar(content: Text('Thanks — sent ✓'), backgroundColor: AppColors.green));
                    _load();
                  }
                } catch (e) {
                  if (sheetCtx.mounted) {
                    ScaffoldMessenger.of(sheetCtx).showSnackBar(
                      SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
                  }
                  setSheetState(() => saving = false);
                }
              }),
            ]))));
  }

  (Color, String) _statusStyle(String status) => switch (status) {
        'reviewed' => (AppColors.blue, 'REVIEWED'),
        'actioned' => (AppColors.green, 'ACTIONED'),
        _ => (AppColors.amber, 'NEW'),
      };

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const AfosAppBar(title: 'Feedback & Ideas'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showSubmitSheet,
        backgroundColor: AppColors.teal,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('Share an idea', style: TextStyle(color: Colors.white)),
      ),
      body: RefreshIndicator(onRefresh: _load, color: AppColors.teal,
        child: _loading
            ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList())
            : ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
                const FeatureHeader(
                  title: 'Feedback & Ideas',
                  subtitle: 'Anyone can share one — a super admin reviews every submission',
                  icon: Icons.lightbulb_rounded,
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [AppColors.teal, AppColors.indigo]),
                ),
                const SizedBox(height: 20),
                Text('Your submissions', style: AppTextStyles.titleMedium.copyWith(color: textPrimary, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                if (_error != null)
                  Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Column(children: [
                    Text('Couldn\'t load: $_error', textAlign: TextAlign.center, style: TextStyle(color: textSecondary)),
                    const SizedBox(height: 8),
                    TextButton(onPressed: _load, child: const Text('Retry')),
                  ]))
                else if (_mine.isEmpty)
                  const Padding(padding: EdgeInsets.symmetric(vertical: 24),
                      child: EmptyState(icon: Icons.feedback_outlined, title: 'Nothing shared yet',
                          subtitle: 'Tap "Share an idea" to send your first one')),
                ..._mine.map((item) {
                  final status = item['status'] as String? ?? 'new';
                  final (color, label) = _statusStyle(status);
                  final createdAt = item['created_at'] != null ? DateTime.tryParse(item['created_at']) : null;
                  return Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.borderOf(context), width: 0.5)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(item['title'] as String? ?? '(no title)',
                              style: AppTextStyles.titleMedium.copyWith(color: textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis)),
                          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                              child: Text(label, textHeightBehavior: const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
                                  style: TextStyle(color: color, fontSize: 10, height: 1.0, fontWeight: FontWeight.w700))),
                        ]),
                        const SizedBox(height: 6),
                        Text(item['message'] as String? ?? '', style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
                        if (createdAt != null) Padding(padding: const EdgeInsets.only(top: 8),
                            child: Text(AppFormatters.relativeTime(createdAt),
                                style: TextStyle(color: AppColors.textMutedOf(context), fontSize: 10))),
                      ]));
                }),
              ]),
      ),
    );
  }
}
