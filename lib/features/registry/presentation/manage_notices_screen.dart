import 'dart:async';
import 'package:flutter/material.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/utils/error_formatter.dart';
import '../../notifications/data/repositories/notification_service.dart';
import '../../shell/presentation/top_app_bar.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/afos_text_field.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/feature_header.dart';
import '../../../shared/widgets/shimmer_card.dart';

/// Super Admin / admin / teacher content management for notices, rules,
/// and announcements — creating one here immediately writes to Supabase
/// (the list below is a live stream, so every open dashboard/notifications
/// screen updates without a refresh) and optionally pushes a targeted
/// notification to the relevant audience.
class ManageNoticesScreen extends StatefulWidget {
  const ManageNoticesScreen({super.key});
  @override State<ManageNoticesScreen> createState() => _ManageNoticesScreenState();
}

class _ManageNoticesScreenState extends State<ManageNoticesScreen> {
  List<Map<String, dynamic>> _notices = [];
  StreamSubscription? _sub;
  bool _loading = true;

  // Matches the notices_category_check constraint exactly (uppercase) —
  // found live-testing that this table predates the rule builder and only
  // allowed GENERAL/EXAM/EVENT/URGENT; RULE/ANNOUNCEMENT were added
  // alongside this screen.
  static const _categories = ['GENERAL', 'RULE', 'ANNOUNCEMENT', 'URGENT', 'EXAM', 'EVENT'];

  @override
  void initState() {
    super.initState();
    _sub = SupabaseConfig.client.from('notices').stream(primaryKey: ['id'])
        .order('created_at', ascending: false).listen((rows) {
      if (mounted) setState(() { _notices = rows; _loading = false; });
    });
  }

  @override
  void dispose() { _sub?.cancel(); super.dispose(); }

  Color _categoryColor(String c) => switch (c) {
    'RULE' => AppColors.teal,
    'ANNOUNCEMENT' => AppColors.holoTeal,
    'URGENT' => AppColors.red,
    'EXAM' => AppColors.orange,
    'EVENT' => AppColors.pink,
    _ => AppColors.blue,
  };

  Future<void> _delete(String id) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dctx) => AlertDialog(
              title: const Text('Delete this entry?'),
              content: const Text('This removes it for everyone immediately.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Cancel')),
                TextButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('Delete')),
              ],
            ));
    if (confirmed == true) {
      await SupabaseConfig.client.from('notices').delete().eq('id', id);
    }
  }

  void _openForm({Map<String, dynamic>? existing}) {
    final titleCtrl = TextEditingController(text: existing?['title'] as String? ?? '');
    final bodyCtrl = TextEditingController(text: existing?['body'] as String? ?? '');
    String category = existing?['category'] as String? ?? 'GENERAL';
    String? notifyRole; // null = everyone
    bool saving = false;

    showModalBottomSheet(
        context: context, isScrollControlled: true,
        backgroundColor: AppColors.surfaceOf(context),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (sheetCtx) => StatefulBuilder(builder: (sheetCtx, setSheetState) {
          final textPrimary = AppColors.textPrimaryOf(sheetCtx);
          return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(sheetCtx).viewInsets.bottom + 24),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(existing == null ? 'New Notice / Rule' : 'Edit',
                    style: AppTextStyles.headlineLarge.copyWith(color: textPrimary)),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  decoration: InputDecoration(hintText: 'Category', filled: true,
                      fillColor: AppColors.glassFill(sheetCtx),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppColors.borderOf(sheetCtx)))),
                  dropdownColor: AppColors.surfaceOf(sheetCtx),
                  style: TextStyle(color: textPrimary),
                  items: _categories.map((c) => DropdownMenuItem(value: c,
                      child: Text(c[0] + c.substring(1).toLowerCase()))).toList(),
                  onChanged: (v) => setSheetState(() => category = v ?? category),
                ),
                const SizedBox(height: 16),
                AfosTextField(hint: 'Title', controller: titleCtrl),
                const SizedBox(height: 16),
                AfosTextField(hint: 'Details', controller: bodyCtrl, maxLines: 5),
                if (existing == null) ...[
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String?>(
                    initialValue: notifyRole,
                    decoration: InputDecoration(hintText: 'Notify', filled: true,
                        fillColor: AppColors.glassFill(sheetCtx),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: AppColors.borderOf(sheetCtx)))),
                    dropdownColor: AppColors.surfaceOf(sheetCtx),
                    style: TextStyle(color: textPrimary),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Everyone')),
                      DropdownMenuItem(value: 'student', child: Text('Students only')),
                      DropdownMenuItem(value: 'teacher', child: Text('Teachers only')),
                    ],
                    onChanged: (v) => setSheetState(() => notifyRole = v),
                  ),
                ],
                const SizedBox(height: 24),
                AfosButton(
                  label: existing == null ? 'Publish' : 'Save Changes',
                  loading: saving,
                  onTap: () async {
                    if (titleCtrl.text.trim().isEmpty || bodyCtrl.text.trim().isEmpty) return;
                    setSheetState(() => saving = true);
                    try {
                      if (existing == null) {
                        await SupabaseConfig.client.from('notices').insert({
                          'title': titleCtrl.text.trim(),
                          'body': bodyCtrl.text.trim(),
                          'category': category,
                        });
                        await NotificationService.broadcast(
                          roleFilter: notifyRole,
                          title: category == 'RULE' ? 'New rule published' : 'New notice',
                          message: titleCtrl.text.trim(),
                          deepLink: '/notifications',
                          category: category,
                        );
                      } else {
                        await SupabaseConfig.client.from('notices').update({
                          'title': titleCtrl.text.trim(),
                          'body': bodyCtrl.text.trim(),
                          'category': category,
                        }).eq('id', existing['id']);
                      }
                      if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                    } catch (e) {
                      if (sheetCtx.mounted) {
                        ScaffoldMessenger.of(sheetCtx).showSnackBar(
                          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
                      }
                      setSheetState(() => saving = false);
                    }
                  },
                ),
              ]));
        }));
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const AfosAppBar(title: 'Notices & Rules'),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _openForm(),
          backgroundColor: AppColors.blue,
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text('New', style: TextStyle(color: Colors.white))),
      body: Column(children: [
        FeatureHeader(
          title: 'Notices & Rules',
          subtitle: _loading ? 'Loading…' : '${_notices.length} published',
          icon: Icons.campaign_rounded,
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [AppColors.red, AppColors.coral]),
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        ),
        Expanded(child: _loading
          ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList())
          : _notices.isEmpty
              ? const EmptyState(icon: Icons.campaign_outlined, title: 'Nothing published yet',
                  subtitle: 'Create a notice, rule, or announcement')
              : ListView.builder(padding: const EdgeInsets.all(16), itemCount: _notices.length,
                  itemBuilder: (ctx, i) {
                    final n = _notices[i];
                    final category = n['category'] as String? ?? 'notice';
                    final color = _categoryColor(category);
                    return Container(margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.borderOf(context), width: 0.5)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                                child: Text(category.toUpperCase(), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700))),
                            const Spacer(),
                            IconButton(icon: const Icon(Icons.edit_outlined, size: 18),
                                onPressed: () => _openForm(existing: n)),
                            IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.red),
                                onPressed: () => _delete(n['id'])),
                          ]),
                          Text(n['title'] ?? '', style: AppTextStyles.titleMedium.copyWith(color: textPrimary)),
                          const SizedBox(height: 4),
                          Text(n['body'] ?? '', style: AppTextStyles.bodyMedium.copyWith(color: textSecondary),
                              maxLines: 3, overflow: TextOverflow.ellipsis),
                        ]));
                  })),
      ]),
    );
  }
}
