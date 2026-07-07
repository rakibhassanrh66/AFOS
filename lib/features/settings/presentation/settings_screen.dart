import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../bloc/theme_bloc.dart';
import '../../../config/app_config.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_icons.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../shared/models/user_model.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/afos_text_field.dart';
import '../../../shared/widgets/avatar_picker.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../notifications/data/repositories/notification_service.dart';
import '../../shell/presentation/top_app_bar.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override State<SettingsScreen> createState() => _SettingsState();
}

class _SettingsState extends State<SettingsScreen> {
  UserModel? _user;
  bool _loading = true, _saving = false;
  final _batchCtrl = TextEditingController();
  final _sectionCtrl = TextEditingController();
  final _teacherInitialCtrl = TextEditingController();

  Map<String, dynamic>? _studentRow;
  Map<String, dynamic>? _latestCrRequest;
  bool _crBusy = false;

  String _notificationSound = 'default';
  String _chatBackground = 'default';

  static const _accentSwatches = [
    Color(0xFF1E6FFF), Color(0xFF8B5CF6), Color(0xFF06B6D4), Color(0xFF22C55E),
    Color(0xFFF59E0B), Color(0xFFEF4444), Color(0xFFEC4899),
  ];

  static const _chatBackgrounds = {
    'default': Colors.transparent,
    'midnight': Color(0xFF0B1220),
    'forest': Color(0xFF0E1F16),
    'plum': Color(0xFF1F0E1B),
  };

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() { _batchCtrl.dispose(); _sectionCtrl.dispose(); _teacherInitialCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) { setState(() => _loading = false); return; }
    try {
      final p = await SupabaseConfig.client.from('profiles')
          .select('*, teachers(*), staff(*)').eq('id', uid).single();
      _batchCtrl.text = p['batch'] as String? ?? '';
      _sectionCtrl.text = p['section'] as String? ?? '';
      _teacherInitialCtrl.text = p['teacher_initial'] as String? ?? '';
      if (mounted) setState(() { _user = UserModel.fromJson(p); _loading = false; });
      if (_isStudentRole) await _loadCrStatus(uid);
      await _loadUserSettings(uid);
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _loadUserSettings(String uid) async {
    try {
      final row = await SupabaseConfig.client.from('user_settings')
          .select('notification_sound, chat_background').eq('profile_id', uid).maybeSingle();
      if (mounted) setState(() {
        _notificationSound = row?['notification_sound'] as String? ?? 'default';
        _chatBackground = row?['chat_background'] as String? ?? 'default';
      });
    } catch (_) {}
  }

  Future<void> _updateSound(String sound) async {
    setState(() => _notificationSound = sound);
    try {
      await SupabaseConfig.client.from('user_settings').upsert({
        'profile_id': SupabaseConfig.uid, 'notification_sound': sound,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  Future<void> _updateChatBackground(String bg) async {
    setState(() => _chatBackground = bg);
    try {
      await SupabaseConfig.client.from('user_settings').upsert({
        'profile_id': SupabaseConfig.uid, 'chat_background': bg,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  Future<void> _loadCrStatus(String uid) async {
    try {
      final student = await SupabaseConfig.client.from('students')
          .select('department_id, batch_label, section, is_cr').eq('profile_id', uid).maybeSingle();
      final requests = await SupabaseConfig.client.from('cr_requests')
          .select().eq('student_id', uid).order('created_at', ascending: false).limit(1) as List;
      if (mounted) setState(() {
        _studentRow = student;
        _latestCrRequest = requests.isNotEmpty ? requests.first as Map<String, dynamic> : null;
      });
    } catch (_) {}
  }

  Future<void> _applyForCr() async {
    final student = _studentRow;
    if (student == null || student['batch_label'] == null || student['section'] == null) return;
    setState(() => _crBusy = true);
    try {
      await SupabaseConfig.client.from('cr_requests').insert({
        'student_id': SupabaseConfig.uid,
        'department_id': student['department_id'],
        'batch_label': student['batch_label'],
        'section': student['section'],
      });
      NotificationService.notifyRoles(
        roles: const ['super_admin'],
        title: 'New CR request',
        message: 'A student requested to become Class Representative.',
        category: 'general', deepLink: '/admin/users',
      );
      await _loadCrStatus(SupabaseConfig.uid!);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('CR request submitted ✓'), backgroundColor: AppColors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
    }
    if (mounted) setState(() => _crBusy = false);
  }

  // Routine Info (batch/section vs teacher initials) and CR only mean
  // anything for these two roles — schedule_screen.dart's own
  // _scheduleNotApplicable already treats every other role (admin/
  // dept_admin/super_admin/staff/exam_controller) as having no personal
  // routine at all, so Settings now matches that instead of asking those
  // roles to "set teacher initials" or "set batch and section" for a
  // schedule view they can never actually use.
  bool get _isFacultyRole => _user?.role == 'teacher';
  bool get _isStudentRole => _user?.role == 'student';
  bool get _routineApplicable => _isFacultyRole || _isStudentRole;

  Future<void> _saveRoutineInfo() async {
    setState(() => _saving = true);
    try {
      final batch = _batchCtrl.text.trim().isEmpty ? null : _batchCtrl.text.trim();
      final section = _sectionCtrl.text.trim().isEmpty ? null : _sectionCtrl.text.trim();
      await SupabaseConfig.client.from('profiles').update({
        'batch': batch,
        'section': section,
        'teacher_initial': _teacherInitialCtrl.text.trim().isEmpty ? null : _teacherInitialCtrl.text.trim(),
      }).eq('id', SupabaseConfig.uid!);
      if (_isStudentRole) {
        // The Class Representative section below reads students.batch_label/
        // section — a different table than the write above — so without
        // mirroring it here, a student who just saved this would still be
        // told "set your batch and section above first" right underneath.
        await SupabaseConfig.client.from('students').update({
          'batch_label': batch, 'section': section,
        }).eq('profile_id', SupabaseConfig.uid!);
        await _loadCrStatus(SupabaseConfig.uid!);
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Routine info saved ✓'), backgroundColor: AppColors.green));
    } catch (e) {
      final msg = e.toString().contains('profiles_teacher_initial_unique')
          ? 'That initial is already taken by another teacher — try a longer one (e.g. "MR" → "MAR").'
          : friendlyError(e);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: AppColors.red));
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.surfaceOf(dialogCtx),
        title: Text('Log out?', style: TextStyle(color: AppColors.textPrimaryOf(dialogCtx))),
        content: Text('Are you sure you want to sign out of AFOS?',
            style: TextStyle(color: AppColors.textSecondaryOf(dialogCtx))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('Log out', style: TextStyle(color: AppColors.red))),
        ],
      ),
    );
    if (confirm == true) {
      await Supabase.instance.client.auth.signOut();
      if (mounted) context.go('/auth/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AfosAppBar(title: 'Settings'),
      body: _loading
          ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList(count: 5))
          : ListView(padding: const EdgeInsets.all(16), children: [

              // ── Profile Section ─────────────────────────────────────────
              RepaintBoundary(
                child: GlassCard(
                  glowColor: AppColors.blue,
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                Center(child: AvatarPicker(
                    avatarUrl: _user?.avatarUrl,
                    initials: _user?.initials ?? '?',
                    onChanged: (url) => _load())),
                const SizedBox(height: 16),
                _InfoTile('Name', _user?.fullName ?? '', Icons.person_outline_rounded),
                _InfoTile('Student ID', _user?.studentId ?? '', Icons.badge_outlined),
                _InfoTile('Email', _user?.email ?? '', AppIcons.emailOutline),
                _InfoTile('Department', _user?.department ?? '', AppIcons.schoolOutline),
                if (_user?.isStudent == true)
                  _InfoTile('Semester', 'Semester ${_user?.semester ?? 1}', Icons.calendar_today_outlined)
                else if (_user?.designation != null)
                  _InfoTile('Designation', _user!.designation!, Icons.work_outline_rounded),
                _InfoTile('Role', _user?.role ?? '', Icons.admin_panel_settings_outlined),
                const SizedBox(height: 12),
                SizedBox(width: double.infinity, child: OutlinedButton.icon(
                    onPressed: () async { await context.push('/complete-profile'); _load(); },
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit Profile'))),
                  ]),
                ),
              ),

              const SizedBox(height: 16),

              // ── Class / Exam Routine Info ─────────────────────────────────
              if (_routineApplicable) ...[
                _Section(title: 'Routine Info', children: [
                  Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_isFacultyRole
                        ? 'Set your teacher initials (as used in the class routine PDF) to see only your own classes.'
                        : 'Set your batch and section (as used in the class routine PDF) to see only your own classes.',
                        style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context))),
                    const SizedBox(height: 12),
                    if (_isFacultyRole)
                      AfosTextField(hint: 'Teacher initials e.g. AS, FNN', controller: _teacherInitialCtrl)
                    else Row(children: [
                      Expanded(child: AfosTextField(hint: 'Batch e.g. 66', controller: _batchCtrl)),
                      const SizedBox(width: 10),
                      Expanded(child: AfosTextField(hint: 'Section e.g. A', controller: _sectionCtrl)),
                    ]),
                    const SizedBox(height: 14),
                    AfosButton(label: 'Save Routine Info', loading: _saving, onTap: _saveRoutineInfo),
                  ])),
                ]),
              ],

              if (_isStudentRole) ...[
                const SizedBox(height: 16),
                _Section(title: 'Class Representative', children: [
                  Padding(padding: const EdgeInsets.all(12), child: _buildCrSection(context)),
                ]),
              ],

              const SizedBox(height: 16),

              // ── Appearance ──────────────────────────────────────────────
              _Section(title: 'Appearance', children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Theme', style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimaryOf(context))),
                    const SizedBox(height: 12),
                    BlocBuilder<ThemeBloc, ThemeState>(
                      builder: (ctx, state) => Row(children: [
                        Expanded(child: _ThemeChip(
                            label: '☀️ Light', selected: state.mode == ThemeMode.light,
                            onTap: () => ctx.read<ThemeBloc>().add(ToggleLight()))),
                        const SizedBox(width: 8),
                        Expanded(child: _ThemeChip(
                            label: '🌙 Dark', selected: state.mode == ThemeMode.dark,
                            onTap: () => ctx.read<ThemeBloc>().add(ToggleDark()))),
                        const SizedBox(width: 8),
                        Expanded(child: _ThemeChip(
                            label: '⚙️ Auto', selected: state.mode == ThemeMode.system,
                            onTap: () => ctx.read<ThemeBloc>().add(ToggleSystem()))),
                      ]),
                    ),
                    const SizedBox(height: 20),
                    Text('Accent Color', style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimaryOf(context))),
                    const SizedBox(height: 12),
                    BlocBuilder<ThemeBloc, ThemeState>(
                      builder: (ctx, state) => Wrap(spacing: 10, runSpacing: 10, children: _accentSwatches.map((c) {
                        final selected = state.accentColor.toARGB32() == c.toARGB32();
                        return GestureDetector(
                          onTap: () => ctx.read<ThemeBloc>().add(SetAccentColor(c)),
                          child: Container(width: 36, height: 36,
                              decoration: BoxDecoration(color: c, shape: BoxShape.circle,
                                  border: Border.all(color: selected ? Colors.white : Colors.transparent, width: 2),
                                  boxShadow: selected ? [BoxShadow(color: c.withValues(alpha: 0.6), blurRadius: 8)] : null)),
                        );
                      }).toList()),
                    ),
                  ]),
                ),
              ]),

              const SizedBox(height: 16),

              // ── Notification Sound ───────────────────────────────────────
              _Section(title: 'Notification Sound', children: [
                Padding(padding: const EdgeInsets.all(12), child: Wrap(spacing: 8, runSpacing: 8, children:
                    ['default', 'chime', 'bell', 'none'].map((s) {
                  final selected = _notificationSound == s;
                  return ChoiceChip(
                      label: Text(s[0].toUpperCase() + s.substring(1)),
                      selected: selected,
                      onSelected: (_) => _updateSound(s),
                      selectedColor: AppColors.blue.withValues(alpha: 0.2),
                      labelStyle: TextStyle(color: selected ? AppColors.blue : AppColors.textSecondaryOf(context)));
                }).toList())),
              ]),

              const SizedBox(height: 16),

              // ── Chat Background ──────────────────────────────────────────
              _Section(title: 'Chat Background', children: [
                Padding(padding: const EdgeInsets.all(12), child: Wrap(spacing: 10, runSpacing: 10,
                    children: _chatBackgrounds.entries.map((entry) {
                  final selected = _chatBackground == entry.key;
                  return GestureDetector(
                    onTap: () => _updateChatBackground(entry.key),
                    child: Container(width: 48, height: 48,
                        decoration: BoxDecoration(color: entry.value, borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: selected ? AppColors.blue : AppColors.borderOf(context), width: selected ? 2 : 0.5)),
                        child: entry.key == 'default' ? const Icon(Icons.chat_bubble_outline, size: 18) : null),
                  );
                }).toList())),
              ]),

              const SizedBox(height: 16),

              // ── Account ──────────────────────────────────────────────────
              _Section(title: 'Account', children: [
                _ActionTile('Change Password', Icons.lock_outline_rounded, AppColors.blue,
                    () => _showChangePassword()),
                _ActionTile('Send Feedback', Icons.feedback_outlined, AppColors.green,
                    () => _showFeedback()),
                _ActionTile('Fix Push Notifications', Icons.notifications_active_outlined, AppColors.amber,
                    () => _fixPushNotifications()),
              ]),

              const SizedBox(height: 16),

              // ── App Info ─────────────────────────────────────────────────
              _Section(title: 'App Info', children: [
                _InfoTile('Version', 'AFOS v${AppConfig.appVersion}', Icons.info_outline_rounded),
                _InfoTile('University', AppConfig.university, AppIcons.schoolOutline),
              ]),

              const SizedBox(height: 24),

              // ── Logout ───────────────────────────────────────────────────
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _logout,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: LinearGradient(colors: [AppColors.red.withOpacity(0.14), AppColors.red.withOpacity(0.05)]),
                        border: Border.all(color: AppColors.red.withOpacity(0.25))),
                    child: Row(children: [
                      Container(width: 38, height: 38,
                          decoration: BoxDecoration(color: AppColors.red.withOpacity(0.16), shape: BoxShape.circle),
                          child: const Icon(AppIcons.logout, color: AppColors.red, size: 19)),
                      const SizedBox(width: 14),
                      const Text('Log Out', style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w700, fontSize: 15)),
                      const Spacer(),
                      Icon(Icons.chevron_right_rounded, color: AppColors.red.withOpacity(0.6), size: 20),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ]),
    );
  }

  Widget _buildCrSection(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    final isCr = _studentRow?['is_cr'] as bool? ?? false;
    final hasBatchSection = _studentRow?['batch_label'] != null && _studentRow?['section'] != null;
    final requestStatus = _latestCrRequest?['status'] as String?;

    if (isCr) {
      return Row(children: [
        const Icon(Icons.verified_user_rounded, color: AppColors.gold, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text('You are the Class Representative for this section',
            style: AppTextStyles.bodyMedium.copyWith(color: textPrimary, fontWeight: FontWeight.w600))),
      ]);
    }
    if (!hasBatchSection) {
      return Text('Set your batch and section above first, then you can apply to be CR.',
          style: AppTextStyles.bodyMedium.copyWith(color: textSecondary));
    }
    if (requestStatus == 'pending') {
      return Row(children: [
        const Icon(Icons.hourglass_top_rounded, color: AppColors.amber, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text('Your CR request is awaiting super admin approval',
            style: AppTextStyles.bodyMedium.copyWith(color: textSecondary))),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (requestStatus == 'rejected')
        Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(
            'Your last request was declined${(_latestCrRequest?['rejection_reason'] as String?)?.isNotEmpty == true ? ': ${_latestCrRequest!['rejection_reason']}' : '.'}',
            style: const TextStyle(color: AppColors.red, fontSize: 12))),
      Text('Be the point of contact between your section and teachers.',
          style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
      const SizedBox(height: 12),
      AfosButton(label: 'Apply to be CR', loading: _crBusy, onTap: _applyForCr),
    ]);
  }

  void _showChangePassword() {
    final oldCtrl = TextEditingController(), newCtrl = TextEditingController();
    showModalBottomSheet(context: context, isScrollControlled: true,
        backgroundColor: AppColors.surfaceOf(context),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (sheetCtx) => SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(sheetCtx).viewInsets.bottom + 24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Change Password', style: AppTextStyles.headlineLarge.copyWith(color: AppColors.textPrimaryOf(sheetCtx))),
              const SizedBox(height: 20),
              AfosTextField(hint: 'Current password', controller: oldCtrl, obscure: true),
              const SizedBox(height: 12),
              AfosTextField(hint: 'New password (min 8 chars)', controller: newCtrl, obscure: true),
              const SizedBox(height: 20),
              AfosButton(label: 'Update Password', onTap: () async {
                if (newCtrl.text.length < 8) return;
                Navigator.pop(context);
                try {
                  await Supabase.instance.client.auth.updateUser(UserAttributes(password: newCtrl.text));
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Password updated ✓'), backgroundColor: AppColors.green));
                } catch (e) {
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
                }
              }),
            ])));
  }

  Future<void> _fixPushNotifications() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fixing notification subscription...')));
    try {
      await SupabaseConfig.client.functions.invoke('check-push-status',
          body: {'resetIdentity': true});
      await OneSignal.logout();
      await OneSignal.login(uid);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Done — try sending yourself a test notice.'), backgroundColor: AppColors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
    }
  }

  void _showFeedback() {
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
              Text('Feedback & Contribution Ideas', style: AppTextStyles.headlineLarge.copyWith(color: AppColors.textPrimaryOf(sheetCtx))),
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
                  final res = await FilePicker.platform.pickFiles(
                      type: FileType.custom, allowedExtensions: ['pdf', 'doc', 'docx', 'png', 'jpg', 'jpeg', 'zip', 'txt']);
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
                  String? fileUrl, fileName;
                  final file = attachment;
                  if (file != null && file.path != null) {
                    final uid = SupabaseConfig.uid;
                    final path = '$uid/${DateTime.now().millisecondsSinceEpoch}_${file.name}';
                    await SupabaseConfig.client.storage.from('feedback-attachments')
                        .uploadBinary(path, await File(file.path!).readAsBytes());
                    fileUrl = path; // private bucket — a signed URL is generated on demand when viewed, not stored.
                    fileName = file.name;
                  }
                  await SupabaseConfig.client.from('feedback').insert({
                    'user_id': SupabaseConfig.uid,
                    'title': titleCtrl.text.trim().isEmpty ? null : titleCtrl.text.trim(),
                    'message': ctrl.text.trim(),
                    'file_url': fileUrl, 'file_name': fileName,
                    'app_version': AppConfig.appVersion,
                  });
                  if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Thanks — sent ✓'), backgroundColor: AppColors.green));
                } catch (e) {
                  if (sheetCtx.mounted) ScaffoldMessenger.of(sheetCtx).showSnackBar(
                      SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
                  setSheetState(() => saving = false);
                }
              }),
            ]))));
  }
}

class _Section extends StatelessWidget {
  final String title; final List<Widget> children;
  const _Section({required this.title, required this.children});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Padding(padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(title.toUpperCase(),
            style: AppTextStyles.labelSmall.copyWith(letterSpacing: 1.5, color: AppColors.textSecondaryOf(context)))),
    Container(decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderOf(context), width: 0.5)),
        child: Column(children: children)),
  ]);
}

class _InfoTile extends StatelessWidget {
  final String label, value; final IconData icon;
  const _InfoTile(this.label, this.value, this.icon);
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: AppColors.textSecondaryOf(context), size: 20),
    title: Text(label, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context))),
    trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 160),
        child: Text(value, style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimaryOf(context)),
            maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.end)),
    dense: true,
  );
}

class _ActionTile extends StatelessWidget {
  final String label; final IconData icon; final Color color; final VoidCallback onTap;
  const _ActionTile(this.label, this.icon, this.color, this.onTap);
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Container(width: 36, height: 36,
        decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(9)),
        child: Icon(icon, color: color, size: 18)),
    title: Text(label, style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimaryOf(context))),
    trailing: Icon(Icons.chevron_right_rounded, color: AppColors.textSecondaryOf(context), size: 18),
    onTap: onTap, dense: true,
  );
}

class _ThemeChip extends StatelessWidget {
  final String label; final bool selected; final VoidCallback onTap;
  const _ThemeChip({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(onTap: onTap,
      child: Container(padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
              color: selected ? AppColors.blue.withOpacity(0.12) : AppColors.surfaceOf(context),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: selected ? AppColors.blue : AppColors.borderOf(context))),
          child: Center(child: Text(label,
              style: TextStyle(color: selected ? AppColors.blue : AppColors.textSecondaryOf(context),
                  fontSize: 12, fontWeight: selected ? FontWeight.w700 : FontWeight.normal)))));
}
