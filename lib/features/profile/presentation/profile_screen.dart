import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_icons.dart';
import '../../../shared/models/user_model.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/avatar_picker.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/label_value_row.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../shell/presentation/top_app_bar.dart';

/// The identity destination for the bottom nav — the profile card that used to
/// live inside Settings, now its own in-shell screen (avatar + identity fields
/// + an entry point into the full editor at /complete-profile).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserModel? _user;
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) { if (mounted) setState(() => _loading = false); return; }
    try {
      final p = await SupabaseConfig.client.from('profiles')
          .select('*, teachers(*), staff(*)').eq('id', uid).single();
      if (mounted) setState(() { _user = UserModel.fromJson(p); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const AfosAppBar(title: 'Profile'),
      body: _loading
          ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList(count: 4))
          : ListView(padding: const EdgeInsets.all(16), children: [
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
                    LabelValueRow(label: 'Name', value: _user?.fullName ?? '', icon: Icons.person_outline_rounded),
                    LabelValueRow(label: 'Student ID', value: _user?.studentId ?? '', icon: Icons.badge_outlined),
                    LabelValueRow(label: 'Email', value: _user?.email ?? '', icon: AppIcons.emailOutline),
                    LabelValueRow(label: 'Department', value: _user?.department ?? '', icon: AppIcons.schoolOutline),
                    if (_user?.isStudent == true)
                      LabelValueRow(label: 'Semester', value: 'Semester ${_user?.semester ?? 1}', icon: Icons.calendar_today_outlined)
                    else if (_user?.designation != null)
                      LabelValueRow(label: 'Designation', value: _user!.designation!, icon: Icons.work_outline_rounded),
                    LabelValueRow(label: 'Role', value: _user?.role ?? '', icon: Icons.admin_panel_settings_outlined),
                    const SizedBox(height: 14),
                    AfosButton(
                      label: 'Edit Profile',
                      icon: Icons.edit_outlined,
                      outlined: true,
                      color: AppColors.blue,
                      onTap: () async { await context.push('/complete-profile'); _load(); },
                    ),
                  ]),
                ),
              ),
            ]),
    );
  }
}
