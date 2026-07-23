import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/auth/role_session.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/afos_text_field.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/feature_header.dart';
import '../../../shared/widgets/glass_sheet.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../shell/presentation/top_app_bar.dart';

import '../../../shared/widgets/glass_bottom_nav.dart';
import '../../../core/services/realtime_channel.dart';
/// Faculties/Departments registry — read is open to any authenticated user
/// (public_read_* policies), but only super_admin has an RLS path to write
/// (super_admin_all), so the add/edit/delete affordances are hidden for
/// admin/dept_admin even though they can reach this route to view the list.
class RegistryListScreen extends StatefulWidget {
  final String tableName;
  final String title;
  final List<String> displayFields;

  const RegistryListScreen({
    super.key,
    required this.tableName,
    required this.title,
    this.displayFields = const ['name'],
  });

  @override
  State<RegistryListScreen> createState() => _RegistryListScreenState();
}

class _RegistryListScreenState extends State<RegistryListScreen> {
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _faculties = []; // for department's faculty_id picker
  bool _loading = true;
  String? _error;
  RealtimeChannel? _sub;
  final _refresh = RealtimeRefresh();

  bool get _canWrite => RoleSession.role == 'super_admin';
  bool get _isDepartments => widget.tableName == 'departments';

  @override
  void initState() {
    super.initState();
    _load();
    _sub = Supabase.instance.client.channel(screenChannel('registry_${widget.tableName}', this))
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public',
        // Debounced: every event reloads the whole registry table.
            table: widget.tableName, callback: (_) => _refresh.schedule(_load))
        .subscribe();
  }

  @override
  void dispose() {
    _sub?.unsubscribe();
    // Cancel any queued refetch, or it fires against an unmounted widget.
    _refresh.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await Supabase.instance.client.from(widget.tableName).select('*').order('name') as List;
      List<Map<String, dynamic>> faculties = _faculties;
      if (_isDepartments) {
        faculties = (await Supabase.instance.client.from('faculties').select('id,name').order('name') as List).cast();
      }
      if (mounted) {
        setState(() {
        _items = res.cast();
        _faculties = faculties;
        _loading = false;
        _error = null;
      });
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = friendlyError(e); });
    }
  }

  String _facultyName(String? id) {
    if (id == null) return '';
    final f = _faculties.where((x) => x['id'] == id).toList();
    return f.isEmpty ? '' : (f.first['name'] as String? ?? '');
  }

  Future<void> _openForm({Map<String, dynamic>? existing}) async {
    final nameCtrl = TextEditingController(text: existing?['name'] as String? ?? '');
    final codeCtrl = TextEditingController(text: existing?['code'] as String? ?? '');
    String? facultyId = existing?['faculty_id'] as String?;
    bool saving = false;

    await showGlassModal(context,
      builder: (sheetCtx) => StatefulBuilder(builder: (sheetCtx, setSheetState) {
        final textPrimary = AppColors.textPrimaryOf(sheetCtx);
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(sheetCtx).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(existing == null ? 'Add ${_isDepartments ? 'Department' : 'Faculty'}' : 'Edit ${_isDepartments ? 'Department' : 'Faculty'}',
                style: AppTextStyles.headlineLarge.copyWith(color: textPrimary)),
            const SizedBox(height: 20),
            AfosTextField(hint: 'Name', controller: nameCtrl),
            const SizedBox(height: 12),
            AfosTextField(hint: 'Code', controller: codeCtrl),
            if (_isDepartments) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: facultyId,
                decoration: const InputDecoration(labelText: 'Faculty'),
                items: _faculties.map((f) => DropdownMenuItem(value: f['id'] as String, child: Text(f['name'] as String? ?? ''))).toList(),
                onChanged: (v) => setSheetState(() => facultyId = v),
              ),
            ],
            const SizedBox(height: 24),
            AfosButton(
              label: existing == null ? 'Create' : 'Save',
              loading: saving,
              onTap: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                setSheetState(() => saving = true);
                try {
                  final payload = {
                    'name': nameCtrl.text.trim(),
                    'code': codeCtrl.text.trim(),
                    if (_isDepartments) 'faculty_id': facultyId,
                  };
                  if (existing == null) {
                    await Supabase.instance.client.from(widget.tableName).insert(payload);
                  } else {
                    await Supabase.instance.client.from(widget.tableName).update(payload).eq('id', existing['id']);
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
          ]),
        );
      }),
    );
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: AppColors.surfaceOf(dCtx),
        title: Text('Delete ${item['name']}?', style: TextStyle(color: AppColors.textPrimaryOf(dCtx))),
        content: Text('This cannot be undone.', style: TextStyle(color: AppColors.textSecondaryOf(dCtx))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dCtx, true), child: const Text('Delete', style: TextStyle(color: AppColors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await Supabase.instance.client.from(widget.tableName).delete().eq('id', item['id']);
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
      appBar: AfosAppBar(title: widget.title),
      body: Column(children: [
        FeatureHeader(
          title: widget.title,
          subtitle: _loading ? 'Loading…' : '${_items.length} ${widget.title.toLowerCase()}',
          icon: _isDepartments ? Icons.school_rounded : Icons.account_balance_rounded,
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [AppColors.indigo, AppColors.blue]),
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        ),
        Expanded(child: _loading
          ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24),
                  child: Text('Error loading ${widget.title.toLowerCase()}: $_error',
                      textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondaryOf(context)))))
              : _items.isEmpty
                  ? EmptyState(icon: Icons.account_balance_outlined, title: 'No ${widget.title.toLowerCase()} yet',
                      subtitle: _canWrite ? 'Tap + to add one' : 'Nothing has been added yet')
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8 + GlassBottomNav.navContentClearance),
                      itemCount: _items.length,
                      itemBuilder: (context, i) {
                        final item = _items[i];
                        final subtitle = _isDepartments
                            ? [item['code'], _facultyName(item['faculty_id'] as String?)].where((s) => (s ?? '').toString().isNotEmpty).join(' · ')
                            : (item['code'] as String? ?? '');
                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                              color: AppColors.surfaceOf(context),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.borderOf(context), width: 0.5)),
                          child: ListTile(
                            leading: Container(width: 40, height: 40,
                                decoration: BoxDecoration(
                                    gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                                        colors: [AppColors.indigo, AppColors.blue]),
                                    borderRadius: BorderRadius.circular(10)),
                                child: Icon(_isDepartments ? Icons.school_rounded : Icons.account_balance_rounded, color: Colors.white, size: 20)),
                            title: Text(item['name'] as String? ?? 'No Name',
                                style: AppTextStyles.titleMedium.copyWith(color: textPrimary),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: subtitle.isEmpty ? null : Text(subtitle,
                                style: AppTextStyles.bodyMedium.copyWith(color: textSecondary),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: _canWrite
                                ? Row(mainAxisSize: MainAxisSize.min, children: [
                                    IconButton(icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => _openForm(existing: item)),
                                    IconButton(icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.red), onPressed: () => _delete(item)),
                                  ])
                                : null,
                          ),
                        );
                      },
                    )),
      ]),
      floatingActionButton: _canWrite
          ? FloatingActionButton(
              backgroundColor: AppColors.blue,
              onPressed: () => _openForm(),
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
    );
  }
}
