import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../bloc/theme_bloc.dart';
import '../../../config/app_config.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../shared/models/user_model.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/afos_text_field.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../shell/presentation/top_app_bar.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override State<SettingsScreen> createState() => _SettingsState();
}

class _SettingsState extends State<SettingsScreen> {
  UserModel? _user;
  bool _loading = true, _saving = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) { setState(() => _loading = false); return; }
    try {
      final p = await SupabaseConfig.client.from('profiles').select().eq('id', uid).single();
      if (mounted) setState(() { _user = UserModel.fromJson(p); _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _pickAndUploadAvatar() async {
    final img = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (img == null) return;
    setState(() => _saving = true);
    try {
      final bytes = await img.readAsBytes();
      final b64 = base64Encode(bytes);
      final res = await Dio().post(AppConfig.imgBBUrl,
          data: FormData.fromMap({'key': AppConfig.imgBBApiKey, 'image': b64}));
      final url = res.data['data']['url'] as String;
      await SupabaseConfig.client.from('profiles')
          .update({'avatar_url': url}).eq('id', SupabaseConfig.uid!);
      _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo updated ✓'), backgroundColor: AppColors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppColors.red));
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
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true),
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
                Center(child: Stack(children: [
                  GestureDetector(
                    onTap: _pickAndUploadAvatar,
                    child: Container(
                      width: 88, height: 88,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.blue.withOpacity(0.4), width: 2),
                          color: AppColors.surfaceOf(context)),
                      child: ClipOval(child: _user?.avatarUrl != null
                          ? Image.network(_user!.avatarUrl!, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _InitialsWidget(_user!.initials))
                          : _InitialsWidget(_user?.initials ?? '?')),
                    ),
                  ),
                  Positioned(bottom: 0, right: 0,
                      child: Container(width: 28, height: 28,
                          decoration: const BoxDecoration(color: AppColors.blue, shape: BoxShape.circle),
                          child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 15))),
                ])),
                if (_saving) const Padding(padding: EdgeInsets.only(top: 8),
                    child: Center(child: LinearProgressIndicator(color: AppColors.blue))),
                const SizedBox(height: 16),
                _InfoTile('Name', _user?.fullName ?? '', Icons.person_outline_rounded),
                _InfoTile('Student ID', _user?.studentId ?? '', Icons.badge_outlined),
                _InfoTile('Email', _user?.email ?? '', Icons.email_outlined),
                _InfoTile('Department', _user?.department ?? '', Icons.school_outlined),
                _InfoTile('Semester', 'Semester ${_user?.semester ?? 1}', Icons.calendar_today_outlined),
                _InfoTile('Role', _user?.role ?? '', Icons.admin_panel_settings_outlined),
                  ]),
                ),
              ),

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
                  ]),
                ),
              ]),

              const SizedBox(height: 16),

              // ── Account ──────────────────────────────────────────────────
              _Section(title: 'Account', children: [
                _ActionTile('Change Password', Icons.lock_outline_rounded, AppColors.blue,
                    () => _showChangePassword()),
                _ActionTile('Send Feedback', Icons.feedback_outlined, AppColors.green,
                    () => _showFeedback()),
              ]),

              const SizedBox(height: 16),

              // ── App Info ─────────────────────────────────────────────────
              _Section(title: 'App Info', children: [
                _InfoTile('Version', 'AFOS v${AppConfig.appVersion}', Icons.info_outline_rounded),
                _InfoTile('University', AppConfig.university, Icons.school_outlined),
              ]),

              const SizedBox(height: 24),

              // ── Logout ───────────────────────────────────────────────────
              Container(
                decoration: BoxDecoration(
                    color: AppColors.red.withOpacity(0.08), borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.red.withOpacity(0.25))),
                child: ListTile(
                  leading: const Icon(Icons.logout_rounded, color: AppColors.red),
                  title: const Text('Log Out', style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w600)),
                  onTap: _logout,
                ),
              ),
              const SizedBox(height: 40),
            ]),
    );
  }

  void _showChangePassword() {
    final oldCtrl = TextEditingController(), newCtrl = TextEditingController();
    showModalBottomSheet(context: context, isScrollControlled: true,
        backgroundColor: AppColors.surfaceOf(context),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (sheetCtx) => Padding(
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
                      SnackBar(content: Text(e.toString()), backgroundColor: AppColors.red));
                }
              }),
            ])));
  }

  void _showFeedback() {
    final ctrl = TextEditingController();
    showModalBottomSheet(context: context, isScrollControlled: true,
        backgroundColor: AppColors.surfaceOf(context),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (sheetCtx) => Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(sheetCtx).viewInsets.bottom + 24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Send Feedback', style: AppTextStyles.headlineLarge.copyWith(color: AppColors.textPrimaryOf(sheetCtx))),
              const SizedBox(height: 20),
              AfosTextField(hint: 'Tell us what you think...', controller: ctrl, maxLines: 4),
              const SizedBox(height: 20),
              AfosButton(label: 'Submit Feedback', onTap: () async {
                if (ctrl.text.trim().isEmpty) return;
                Navigator.pop(context);
                try {
                  await SupabaseConfig.client.from('feedback').insert({
                    'user_id': SupabaseConfig.uid, 'message': ctrl.text.trim(),
                    'app_version': AppConfig.appVersion,
                  });
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Feedback sent ✓'), backgroundColor: AppColors.green));
                } catch (_) {}
              }),
            ])));
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
    trailing: Text(value, style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimaryOf(context))),
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

class _InitialsWidget extends StatelessWidget {
  final String initials;
  const _InitialsWidget(this.initials);
  @override
  Widget build(BuildContext context) => Container(color: AppColors.surfaceOf(context),
      child: Center(child: Text(initials,
          style: const TextStyle(color: AppColors.blue, fontSize: 28, fontWeight: FontWeight.bold))));
}
