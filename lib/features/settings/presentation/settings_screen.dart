import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../core/services/app_update_service.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../bloc/theme_bloc.dart';
import '../../../config/app_config.dart';
import '../../../config/supabase_config.dart';
import '../../../core/auth/biometric_lock.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_icons.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/depth.dart';
import '../../../config/theme/spacing.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/services/outbox_service.dart';
import '../../../core/services/sos_location_service.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/models/user_model.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/afos_text_field.dart';
import '../../../shared/widgets/glass_sheet.dart';
import '../../../shared/widgets/logout_tile.dart';
import '../../../shared/widgets/radial_logout_menu.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../shell/presentation/top_app_bar.dart';
import 'update_sheet.dart';

import '../../../core/layout/nav_insets.dart';
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
  bool _locationSharing = true;
  // Preview player for the notification-sound chips below — separate from
  // any other AudioPlayer in the app (e.g. SOS voice notes) so tapping a
  // chip here can never fight over playback state with an unrelated screen.
  final _soundPreviewPlayer = AudioPlayer();
  bool _biometricSupported = false;
  bool _biometricEnabled = false;

  AppUpdateInfo? _availableUpdate;
  bool _checkingUpdate = false;

  // Was its own independent, fully-saturated set (not even the same hex
  // values as AppColors' now-recalibrated palette) -- referencing the
  // actual muted constants keeps the accent picker's own swatches from
  // being the one place in Settings still offering "funky" neon options.
  static const _accentSwatches = [
    AppColors.blue, AppColors.purple, AppColors.teal, AppColors.green,
    AppColors.amber, AppColors.red, AppColors.pink,
  ];

  // Was a private copy of the same four hex values that dept_chat_screen.dart
  // also held. Both now read the one definition in AppColors, so a swatch here
  // cannot disagree with the canvas the chat actually paints.
  static const _chatBackgrounds = AppColors.chatBackgrounds;

  @override
  void initState() { super.initState(); _load(); _loadBiometric(); _checkForUpdate(); }

  /// Best-effort, silent on entry — a failed check should never show an error
  /// on a screen the user didn't even ask to check anything on. The visible
  /// "Check for Updates" tile below re-runs this on demand and DOES report a
  /// failure, since that's an explicit user action.
  ///
  /// Seeds from [AppUpdateService.available] first so the answer the app-wide
  /// watcher already has is shown on the first frame instead of after another
  /// round trip, then follows it — a release published while this screen is
  /// open updates the banner without the user doing anything.
  Future<void> _checkForUpdate() async {
    if (mounted) setState(() => _availableUpdate = AppUpdateService.available.value);
    AppUpdateService.available.addListener(_onAvailableUpdateChanged);
    final update = await AppUpdateService.checkForUpdate();
    if (mounted) setState(() => _availableUpdate = update);
  }

  void _onAvailableUpdateChanged() {
    if (mounted) setState(() => _availableUpdate = AppUpdateService.available.value);
  }

  Future<void> _checkForUpdateManually() async {
    setState(() => _checkingUpdate = true);
    final update = await AppUpdateService.checkForUpdate();
    if (!mounted) return;
    setState(() { _availableUpdate = update; _checkingUpdate = false; });
    if (update == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("You're on the latest version"), backgroundColor: AppColors.green));
      return;
    }
    // Found one — open the sheet straight away rather than making the user
    // hunt for the banner that just appeared further up the page. They asked
    // the question; this is the answer.
    await _openUpdateSheet();
  }

  /// Opens the update sheet.
  ///
  /// The download used to run from this screen with a percentage on the tile,
  /// and then Android's installer appeared with no explanation. Sideloading
  /// already asks a lot of trust — an unknown-sources prompt, a Play Protect
  /// warning, a permission screen — and the app going quiet in the middle of
  /// that is what makes people abandon the install. The sheet narrates it:
  /// what version, what changed, verified, and that Android is about to ask.
  Future<void> _openUpdateSheet() async {
    final update = _availableUpdate;
    if (update == null) return;
    AppHaptics.selection();
    await showUpdateSheet(context, update);
  }


  Future<void> _loadBiometric() async {
    final supported = await BiometricAuth.canUse();
    final uid = SupabaseConfig.uid;
    final enabled = uid != null && await BiometricTokenStore.isEnabledFor(uid);
    if (mounted) setState(() { _biometricSupported = supported; _biometricEnabled = enabled; });
  }

  Future<void> _toggleBiometric(bool on) async {
    final messenger = ScaffoldMessenger.of(context);
    final uid = SupabaseConfig.uid;
    if (uid == null) return;
    if (on) {
      final ok = await BiometricAuth.authenticate('Enable fingerprint / Face ID login');
      if (!ok) return;
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) return;
      await BiometricTokenStore.remember(
        userId: uid,
        email: session.user.email ?? '',
        sessionJson: jsonEncode(session.toJson()),
        fullName: _user?.fullName,
        avatarUrl: _user?.avatarUrl,
      );
      if (mounted) setState(() => _biometricEnabled = true);
      AppHaptics.success();
      messenger.showSnackBar(const SnackBar(
          content: Text('Biometric login enabled'), backgroundColor: AppColors.green));
    } else {
      // Only this account — other remembered accounts on this device (if
      // any) keep their own quick-login untouched.
      await BiometricTokenStore.forget(uid);
      if (mounted) setState(() => _biometricEnabled = false);
      messenger.showSnackBar(const SnackBar(content: Text('Biometric login disabled')));
    }
  }

  @override
  void dispose() {
    // AppUpdateService.available outlives this screen (it is app-wide), so a
    // listener left attached here would keep calling setState on a disposed
    // State every time a release lands.
    AppUpdateService.available.removeListener(_onAvailableUpdateChanged);
    _batchCtrl.dispose(); _sectionCtrl.dispose(); _teacherInitialCtrl.dispose(); _soundPreviewPlayer.dispose(); super.dispose();
  }

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
      await _loadLocationSharing(uid);
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _loadUserSettings(String uid) async {
    try {
      final row = await SupabaseConfig.client.from('user_settings')
          .select('notification_sound, chat_background').eq('profile_id', uid).maybeSingle();
      if (mounted) {
        setState(() {
        _notificationSound = row?['notification_sound'] as String? ?? 'default';
        _chatBackground = row?['chat_background'] as String? ?? 'default';
      });
      }
    } catch (_) {}
  }

  Future<void> _updateSound(String sound) async {
    setState(() => _notificationSound = sound);
    _previewSound(sound);
    try {
      await SupabaseConfig.client.from('user_settings').upsert({
        'profile_id': SupabaseConfig.uid, 'notification_sound': sound,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  /// Plays `assets/sounds/<sound>.mp3` as an immediate preview when a
  /// notification-sound chip is tapped — this was previously a silent
  /// preference save with no audible feedback at all. 'none' never plays
  /// anything, by design. A file that doesn't exist yet (the admin hasn't
  /// dropped one into assets/sounds/ — see the README there) fails silently
  /// here rather than showing an error: a missing preview sound is a normal,
  /// expected state, not a bug to surface to the user.
  Future<void> _previewSound(String sound) async {
    if (sound == 'none') return;
    try {
      await _soundPreviewPlayer.stop();
      await _soundPreviewPlayer.play(AssetSource('sounds/$sound.mp3'));
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

  Future<void> _loadLocationSharing(String uid) async {
    try {
      final row = await SupabaseConfig.client.from('user_locations')
          .select('sharing_enabled').eq('user_id', uid).maybeSingle();
      if (mounted) setState(() => _locationSharing = row == null ? true : (row['sharing_enabled'] as bool? ?? true));
    } catch (_) {}
  }

  Future<void> _updateLocationSharing(bool enabled) async {
    setState(() => _locationSharing = enabled);
    try {
      await SupabaseConfig.client.from('user_locations').upsert({
        'user_id': SupabaseConfig.uid, 'sharing_enabled': enabled,
        'updated_at': DateTime.now().toIso8601String(),
      });
      if (enabled) {
        await SosLocationService.start();
      } else {
        await SosLocationService.stop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
  }

  Future<void> _loadCrStatus(String uid) async {
    try {
      final student = await SupabaseConfig.client.from('students')
          .select('department_id, batch_label, section, is_cr').eq('profile_id', uid).maybeSingle();
      final requests = await SupabaseConfig.client.from('cr_requests')
          .select().eq('student_id', uid).order('created_at', ascending: false).limit(1) as List;
      if (mounted) {
        setState(() {
        _studentRow = student;
        _latestCrRequest = requests.isNotEmpty ? requests.first as Map<String, dynamic> : null;
      });
      }
    } catch (_) {}
  }

  Future<void> _applyForCr() async {
    final student = _studentRow;
    if (student == null || student['batch_label'] == null || student['section'] == null) return;
    setState(() => _crBusy = true);
    try {
      final queued = await OutboxService.instance.submitOrQueue('cr_request', {
        'student_id': SupabaseConfig.uid,
        'department_id': student['department_id'],
        'batch_label': student['batch_label'],
        'section': student['section'],
      });
      await _loadCrStatus(SupabaseConfig.uid!);
      if (mounted) {
        AppHaptics.success();
        ScaffoldMessenger.of(context).showSnackBar(queued
          ? const SnackBar(content: Text("Saved — will send when you're back online"), backgroundColor: AppColors.amber)
          : const SnackBar(content: Text('CR request submitted'), backgroundColor: AppColors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
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
    // Checked before the write, not just after it: these fields are covered by
    // DB CHECK constraints, so an unvalidated save comes back as a rejected
    // write with nothing pointing at the field that caused it. Each is
    // optional here — a user may legitimately clear one — so only a non-empty
    // value is format-checked.
    final formatError = _isFacultyRole
        ? AppValidators.teacherInitial(_teacherInitialCtrl.text, req: false)
        : AppValidators.batch(_batchCtrl.text, req: false) ??
            AppValidators.section(_sectionCtrl.text, req: false);
    if (formatError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(formatError), backgroundColor: AppColors.red));
      return;
    }
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
      if (mounted) {
        AppHaptics.success();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Routine info saved'), backgroundColor: AppColors.green));
      }
    } catch (e) {
      // The teacher-initial uniqueness case used to be special-cased here by
      // string-matching the constraint name; friendlyError now owns that
      // mapping (along with the format constraints) so every screen that
      // writes these fields gets the same wording.
      final msg = friendlyError(e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: AppColors.red));
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  /// [tileCtx] is the Logout row's own context — the radial leave menu bursts
  /// out of that row's render box. Shares `applyLogoutChoice` with the slide
  /// menu so both entry points behave identically.
  Future<void> _logout(BuildContext tileCtx) async {
    final choice = await showRadialLogoutMenu(tileCtx);
    if (!tileCtx.mounted) return;
    await applyLogoutChoice(tileCtx, choice);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const AfosAppBar(title: 'Settings'),
      body: _loading
          ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList(count: 5))
          : ListView(padding: EdgeInsetsDirectional.fromSTEB(16, 16, 16, 16 + NavInsets.of(context)), children: [

              // Profile identity now lives on its own /profile screen (bottom
              // nav) so it isn't shown in two places — Settings keeps only
              // settings.

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
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Theme', style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimaryOf(context))),
                    const SizedBox(height: 12),
                    BlocBuilder<ThemeBloc, ThemeState>(
                      builder: (ctx, state) => Row(children: [
                        Expanded(child: _ThemeChip(
                            label: 'Light', icon: Icons.light_mode_rounded,
                            selected: state.mode == ThemeMode.light,
                            onTap: () => ctx.read<ThemeBloc>().add(ToggleLight()))),
                        const SizedBox(width: 8),
                        Expanded(child: _ThemeChip(
                            label: 'Dark', icon: Icons.dark_mode_rounded,
                            selected: state.mode == ThemeMode.dark,
                            onTap: () => ctx.read<ThemeBloc>().add(ToggleDark()))),
                        const SizedBox(width: 8),
                        Expanded(child: _ThemeChip(
                            label: 'Auto', icon: Icons.brightness_auto_rounded,
                            selected: state.mode == ThemeMode.system,
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
                          onTap: () { AppHaptics.selection(); ctx.read<ThemeBloc>().add(SetAccentColor(c)); },
                          // The swatch reads as 36px but was also only 36px to
                          // hit. The SizedBox gives it the 48dp floor without
                          // changing how big the circle looks.
                          child: SizedBox(
                            width: AppSpace.minTouchTarget, height: AppSpace.minTouchTarget,
                            child: Center(child: Container(width: 36, height: 36,
                              decoration: BoxDecoration(color: c, shape: BoxShape.circle,
                                  // A fixed white ring disappeared against the
                                  // light theme's white settings card --
                                  // theme-aware primary text color instead,
                                  // which is dark-on-light and light-on-dark,
                                  // so the selected swatch stays visible in
                                  // both modes.
                                  border: Border.all(color: selected ? AppColors.textPrimaryOf(context) : Colors.transparent, width: 2),
                                  boxShadow: selected ? [BoxShadow(color: c.withValues(alpha: 0.6), blurRadius: 8)] : null))),
                          ),
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
                    onTap: () { AppHaptics.selection(); _updateChatBackground(entry.key); },
                    child: Container(width: 48, height: 48,
                        decoration: BoxDecoration(color: entry.value, borderRadius: AppDepth.radius(1),
                            border: Border.all(color: selected ? AppColors.blue : AppColors.borderOf(context), width: selected ? 2 : 0.5)),
                        child: entry.key == 'default' ? const Icon(Icons.chat_bubble_outline, size: 18) : null),
                  );
                }).toList())),
              ]),

              const SizedBox(height: 16),

              // ── Campus Safety ─────────────────────────────────────────────
              _Section(title: 'Campus Safety', children: [
                Padding(padding: const EdgeInsets.all(12), child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Location Sharing', style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimaryOf(context))),
                    const SizedBox(height: 4),
                    Text('Lets nearby users and staff be alerted if you ever need emergency help. You can still send your own SOS with this off.',
                        style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(context))),
                  ])),
                  Switch(value: _locationSharing, activeThumbColor: AppColors.blue,
                      onChanged: _updateLocationSharing),
                ])),
              ]),

              const SizedBox(height: 16),

              // ── Feedback ─────────────────────────────────────────────────
              // The doctrine requires every haptic to sit behind a user
              // setting. `AppHaptics.enabled` has existed since Phase 1 and
              // nothing could change it — 92 call sites answering to a switch
              // that was not on any screen. This is that switch.
              _Section(title: 'Feedback', children: [
                Padding(padding: const EdgeInsets.all(12), child: Row(children: [
                  const Icon(Icons.vibration_rounded, color: AppColors.holoTeal, size: 22),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Haptic feedback', style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimaryOf(context))),
                    const SizedBox(height: 4),
                    Text('A short vibration when an action commits — a choice landing, something saved, something refused.',
                        style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(context))),
                  ])),
                  ValueListenableBuilder<bool>(
                    valueListenable: AppHaptics.enabled,
                    builder: (_, on, __) => Switch(
                      value: on,
                      activeThumbColor: AppColors.holoTeal,
                      onChanged: (v) {
                        AppHaptics.setEnabled(v);
                        // Fire one AFTER enabling, so turning it on
                        // demonstrates what it does. Turning it off is
                        // deliberately silent — a buzz confirming "no more
                        // buzzing" is the joke nobody wants.
                        if (v) AppHaptics.selection();
                      },
                    ),
                  ),
                ])),
              ]),

              if (_biometricSupported) ...[
                const SizedBox(height: 16),
                // ── Security ────────────────────────────────────────────────
                _Section(title: 'Security', children: [
                  Padding(padding: const EdgeInsets.all(12), child: Row(children: [
                    const Icon(Icons.fingerprint_rounded, color: AppColors.holoBlue, size: 22),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Fingerprint / Face ID login', style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimaryOf(context))),
                      const SizedBox(height: 4),
                      Text('Unlock AFOS with biometrics next time instead of typing your password. Your session stays only on this device.',
                          style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(context))),
                    ])),
                    Switch(value: _biometricEnabled, activeThumbColor: AppColors.holoBlue,
                        onChanged: _toggleBiometric),
                  ])),
                ]),
              ],

              const SizedBox(height: 16),

              // ── Account ──────────────────────────────────────────────────
              // Switch Account deliberately lives only on the Unlock screen
              // ("Use a different account"), not duplicated here too.
              _Section(title: 'Account', children: [
                _ActionTile('Change Password', Icons.lock_outline_rounded, AppColors.blue,
                    () => _showChangePassword()),
                _ActionTile('Send Feedback', Icons.feedback_outlined, AppColors.green,
                    () => _showFeedback()),
                // 'Fix Push Notifications' removed: it re-registered the
                // OneSignal identity, which is maintenance plumbing, not
                // something an end user should ever have to know about or run.
                // Every user was being shown a button for an internal repair.
              ]),

              const SizedBox(height: 16),

              // ── App Info ─────────────────────────────────────────────────
              if (_availableUpdate != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _UpdateBanner(
                    update: _availableUpdate!,
                    onInstall: _openUpdateSheet,
                  ),
                ),
              _Section(title: 'App Info', children: [
                _InfoTile('Version', 'AFOS v${AppConfig.appVersion}', Icons.info_outline_rounded),
                _ActionTile('What\'s New', Icons.new_releases_outlined, AppColors.holoBlue,
                    () => context.push('/releases')),
                _ActionTile(
                    _checkingUpdate ? 'Checking…' : 'Check for Updates',
                    Icons.system_update_rounded, AppColors.teal,
                    _checkingUpdate ? () {} : _checkForUpdateManually),
                const _InfoTile('University', AppConfig.university, AppIcons.schoolOutline),
              ]),

              const SizedBox(height: 24),

              // ── Logout ───────────────────────────────────────────────────
              // Builder so the tile has its OWN context for the burst origin.
              Builder(builder: (tileCtx) => LogoutTile(onTap: () => _logout(tileCtx))),
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
    showGlassModal(context,
        builder: (sheetCtx) => SingleChildScrollView(
            padding: EdgeInsetsDirectional.fromSTEB(24, 24, 24, MediaQuery.of(sheetCtx).viewInsets.bottom + 24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Change Password', style: AppTextStyles.headlineLarge.copyWith(color: AppColors.textPrimaryOf(sheetCtx))),
              const SizedBox(height: 20),
              AfosTextField(hint: 'Current password', controller: oldCtrl, obscure: true),
              const SizedBox(height: 12),
              AfosTextField(hint: 'New password (min 8 chars)', controller: newCtrl, obscure: true),
              const SizedBox(height: 20),
              AfosButton(label: 'Update Password', onTap: () async {
                if (newCtrl.text.length < 8) return;
                // Capture the root messenger before popping the sheet + the
                // await, so we never touch a defunct sheet BuildContext after
                // the async gap.
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(context);
                try {
                  await Supabase.instance.client.auth.updateUser(UserAttributes(password: newCtrl.text));
                  AppHaptics.success();
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Password updated'), backgroundColor: AppColors.green));
                } catch (e) {
                  messenger.showSnackBar(
                    SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
                }
              }),
            ])));
  }

  void _showFeedback() {
    final titleCtrl = TextEditingController();
    final ctrl = TextEditingController();
    PlatformFile? attachment;
    bool saving = false;
    showGlassModal(context,
        builder: (sheetCtx) => StatefulBuilder(builder: (sheetCtx, setSheetState) => SingleChildScrollView(
            padding: EdgeInsetsDirectional.fromSTEB(24, 24, 24, MediaQuery.of(sheetCtx).viewInsets.bottom + 24),
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
                  // File upload only happens here (immediate path) when
                  // already online -- if offline, the attachment bytes are
                  // queued instead and the actual upload happens at flush
                  // time in outbox_handlers.dart's feedback_submit handler.
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
                    AppHaptics.success();
                    ScaffoldMessenger.of(context).showSnackBar(queued
                      ? const SnackBar(content: Text("Saved — will send when you're back online"), backgroundColor: AppColors.amber)
                      : const SnackBar(content: Text('Feedback sent'), backgroundColor: AppColors.green));
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
}

class _Section extends StatelessWidget {
  final String title; final List<Widget> children;
  const _Section({required this.title, required this.children});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Padding(padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
        child: Text(title.toUpperCase(),
            style: AppTextStyles.labelSmall.copyWith(letterSpacing: 1.5, color: AppColors.textSecondaryOf(context)))),
    Container(decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: AppDepth.radius(1),
        border: Border.all(color: AppColors.borderOf(context), width: 0.5)),
        child: Column(children: children)),
  ]);
}

class _InfoTile extends StatelessWidget {
  final String label, value; final IconData icon;
  const _InfoTile(this.label, this.value, this.icon);
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    leading: Icon(icon, color: AppColors.textSecondaryOf(context), size: 20),
    title: Text(label, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context))),
    // Was maxWidth:160 + maxLines:1 — fine for "AFOS v2.3.x" but truncated
    // "Daffodil International University" (34 chars) down to "Daffodil
    // Internat…", cutting off the university's actual name. Widened and
    // allowed to wrap to a second line instead of ellipsizing.
    trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 200),
        child: Text(value, style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimaryOf(context)),
            maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.end)),
  );
}

class _ActionTile extends StatelessWidget {
  final String label; final IconData icon; final Color color; final VoidCallback onTap;
  const _ActionTile(this.label, this.icon, this.color, this.onTap);
  @override
  // Was `dense: true` with a 36px leading icon and no contentPadding override
  // -- dense mode shrinks ListTile's already-modest default vertical padding
  // right when the enclosing _Section box has zero padding of its own to
  // compensate, so the icon and label sat almost flush against the section
  // box's top/bottom edges. Explicit contentPadding gives real breathing
  // room regardless of density.
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    leading: Container(width: 36, height: 36, alignment: Alignment.center,
        decoration: BoxDecoration(color: color.withValues(alpha:0.12), borderRadius: AppDepth.radius(1)),
        child: Icon(icon, color: color, size: 18)),
    title: Text(label, style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimaryOf(context))),
    trailing: Icon(Icons.chevron_right_rounded, color: AppColors.textSecondaryOf(context), size: 18),
    onTap: onTap,
  );
}

/// A newer AFOS build is available — download + install without leaving the
/// app or a browser. Downloads to a temp file and hands it to Android's own
/// package installer (see AppUpdateService for why the file itself is left
/// for opportunistic cleanup rather than deleted immediately after).
class _UpdateBanner extends StatelessWidget {
  final AppUpdateInfo update;
  final VoidCallback onInstall;
  const _UpdateBanner({required this.update, required this.onInstall});

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.teal.withValues(alpha: 0.1),
        borderRadius: AppDepth.radius(1),
        border: Border.all(color: AppColors.teal.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.system_update_rounded, color: AppColors.teal, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(update.title,
              style: AppTextStyles.titleMedium.copyWith(color: textPrimary, fontWeight: FontWeight.w700))),
        ]),
        if (update.highlights.isNotEmpty) ...[
          const SizedBox(height: 6),
          // Capped at 3 — this is a compact settings-screen banner, not the
          // full What's New page (that's one tap away above).
          for (final h in update.highlights.take(3))
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('•  $h', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelSmall.copyWith(color: textSecondary)),
            ),
        ],
        const SizedBox(height: 12),
        // No progress bar here any more. The download reports its stages in
        // the update sheet, which can explain them; a bar on a banner behind a
        // sheet would be the same fact in two places, drifting.
        SizedBox(width: double.infinity, child: AfosButton(
            label: 'Download & Install', icon: Icons.download_rounded,
            color: AppColors.teal, onTap: onInstall)),
      ]),
    );
  }
}

/// Theme mode picker.
///
/// The labels were `'☀️ Light'`, `'🌙 Dark'` and `'⚙️ Auto'` — a picture glued
/// to the front of a string. Emoji renders differently on every platform, is
/// read out literally by a screen reader ("sun behind cloud Light"), and cannot
/// take the chip's own selected/unselected colour, so the glyph stayed full
/// colour while the text went blue. These are real icons now.
class _ThemeChip extends StatelessWidget {
  final String label; final IconData icon; final bool selected; final VoidCallback onTap;
  const _ThemeChip({required this.label, required this.icon, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.blue : AppColors.textSecondaryOf(context);
    return GestureDetector(
      onTap: () { AppHaptics.selection(); onTap(); },
      child: Container(
          // Vertical padding was 14, leaving the chip ~45dp tall.
          padding: const EdgeInsets.symmetric(vertical: AppSpace.lg, horizontal: AppSpace.sm),
          decoration: BoxDecoration(
              color: selected ? AppColors.blue.withValues(alpha:0.12) : AppColors.surfaceOf(context),
              borderRadius: AppDepth.radius(1),
              border: Border.all(color: selected ? AppColors.blue : AppColors.borderOf(context))),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 15, color: fg),
            const SizedBox(width: 5),
            Flexible(child: Text(label, textAlign: TextAlign.center,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: fg,
                    fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.normal))),
          ])),
    );
  }
}
