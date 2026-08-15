import 'dart:async';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/depth.dart';
import '../../../config/theme/liquid_glass_tokens.dart';
import '../../../config/theme/motion.dart';
import '../../../shared/models/user_model.dart';
import '../../shell/presentation/top_app_bar.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/glass_tab_bar.dart';
import '../../../shared/widgets/supernova_loader.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../core/utils/formatters.dart';
import '../data/vr_id_pdf_generator.dart';

import '../../../core/layout/nav_insets.dart';
class VrIdScreen extends StatefulWidget {
  const VrIdScreen({super.key});
  @override State<VrIdScreen> createState() => _VrIdState();
}

class _VrIdState extends State<VrIdScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  UserModel? _user;
  String _token = '';
  int _countdown = 60;
  Timer? _timer;
  bool _loading = true;
  final _storage = const FlutterSecureStorage();

  @override
  void initState() { super.initState(); _tab = TabController(length: 3, vsync: this); _init(); }

  @override
  void dispose() { _tab.dispose(); _timer?.cancel(); super.dispose(); }

  Future<void> _init() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) { setState(() => _loading = false); return; }
    try {
      final p = await SupabaseConfig.client.from('profiles')
          .select('*, teachers(designation), staff(designation)').eq('id', uid).single();
      if (mounted) setState(() { _user = UserModel.fromJson(p); _loading = false; });
      await _generateToken();
      _startTimer();
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  /// The token is minted by the server (`issue_vr_id_token`), which signs
  /// `auth.uid()` with a secret this client never sees, so a caller can only
  /// ever obtain a badge for themselves.
  ///
  /// It used to be computed right here as
  /// `sha256('$uid:$minute:afos-salt')` — but that salt was a literal in a
  /// PUBLIC repo and in every shipped APK, and the only other input was the
  /// uid being claimed. Anyone could therefore mint a valid VR-ID for any
  /// user and have the verifier hand back their name, university id,
  /// department, batch/section and CGPA. See the migration
  /// 20260725131000_sec_vr_id_server_signed_tokens for the full write-up.
  Future<void> _generateToken() async {
    try {
      final rows = await SupabaseConfig.client.rpc('issue_vr_id_token') as List;
      final issued = rows.firstOrNull as Map<String, dynamic>?;
      if (issued == null) return;
      final payload = jsonEncode({
        'uid': issued['uid'], 'vrid': issued['vrid'], 'exp': issued['exp'],
      });
      final token = base64Encode(utf8.encode(payload));
      if (mounted) setState(() => _token = token);
      await _storage.write(key: 'last_vrid', value: token);
      await _storage.write(key: 'last_vrid_time', value: DateTime.now().toIso8601String());
    } catch (e) {
      // Keep whatever token is already on screen rather than blanking the
      // QR — the previous one stays valid for its remaining window.
      debugPrint('[VrId] token issue failed: $e');
    }
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _countdown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _countdown--);
      if (_countdown <= 0) { unawaited(_generateToken()); setState(() => _countdown = 60); }
    });
  }

  static const _tabLabels = ['My VR-ID', 'Scan', 'Access Log'];
  static const _tabIcons = [Icons.badge_rounded, Icons.qr_code_scanner_rounded, Icons.history_rounded];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const AfosAppBar(title: 'VR-ID'),
      body: Column(children: [
        const SizedBox(height: 12),
        AnimatedBuilder(
          animation: _tab,
          builder: (ctx, _) => GlassTabBar(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            currentIndex: _tab.index,
            onChanged: (i) => _tab.animateTo(i),
            tabs: [
              for (var i = 0; i < _tabLabels.length; i++)
                GlassTab(_tabLabels[i], icon: _tabIcons[i]),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(child: TabBarView(controller: _tab, children: [
          _MyVrIdTab(user: _user, token: _token, countdown: _countdown, loading: _loading),
          kIsWeb ? _WebScanPlaceholder() : _ScanTab(),
          _AccessLogTab(),
        ])),
      ]),
    );
  }
}

// Semester only applies to students — other roles show role-appropriate info
// instead of a leftover default semester value from their profile row.
String _secondaryLabel(UserModel user) {
  if (user.isStudent) return 'Sem ${user.semester}';
  if (user.isTeacher) return user.designation ?? 'Faculty';
  if (user.isStaff) return user.designation ?? 'Staff/Officer';
  switch (user.role) {
    case 'super_admin': return 'Super Admin';
    case 'dept_admin': return 'Dept Admin';
    case 'admin': return 'Admin';
    case 'exam_controller': return 'Exam Controller';
    default: return user.role;
  }
}

class _MyVrIdTab extends StatelessWidget {
  final UserModel? user; final String token; final int countdown; final bool loading;
  const _MyVrIdTab({this.user, required this.token, required this.countdown, required this.loading});

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: SupernovaLoader(size: 40, color: AppColors.blue));
    if (user == null) return Center(child: Text('Could not load profile', style: TextStyle(color: AppColors.textSecondaryOf(context))));
    final countdownColor = countdown > 30 ? AppColors.green : countdown > 10 ? AppColors.amber : AppColors.red;
    return SingleChildScrollView(padding: EdgeInsetsDirectional.fromSTEB(20, 20, 20, 20 + NavInsets.of(context)), child: Column(children: [
      RepaintBoundary(
        child: GlassCard(
          glowColor: AppColors.blue,
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.school_rounded, color: AppColors.blue, size: 18),
              const SizedBox(width: 8),
              Text('DIU · AFOS VR-ID', style: TextStyle(color: AppColors.textSecondaryOf(context), fontSize: 12, letterSpacing: 1)),
            ]),
            const SizedBox(height: 16),
            Container(width: 64, height: 64, decoration: BoxDecoration(
                shape: BoxShape.circle, color: AppColors.blue.withValues(alpha:0.1),
                border: Border.all(color: AppColors.blue.withValues(alpha:0.4), width: 2)),
                child: ClipOval(child: (user!.avatarUrl?.isNotEmpty ?? false)
                    ? CachedNetworkImage(imageUrl: user!.avatarUrl!, fit: BoxFit.cover, memCacheWidth: 200,
                        errorWidget: (_, __, ___) => const Icon(Icons.person_rounded, color: AppColors.blue, size: 36))
                    : const Icon(Icons.person_rounded, color: AppColors.blue, size: 36))),
            const SizedBox(height: 10),
            Text(user!.fullName, style: AppTextStyles.headlineLarge.copyWith(color: AppColors.textPrimaryOf(context))),
            Text(user!.department, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context))),
            const SizedBox(height: 16),
            token.isNotEmpty ? AnimatedSwitcher(
              duration: AppMotion.durationOf(context, AppMotion.base),
              child: QrImageView(key: ValueKey(token), data: token,
                  version: QrVersions.auto, size: 180,
                  backgroundColor: Colors.white, padding: const EdgeInsets.all(10)),
            ) : const SupernovaLoader(size: 40, color: AppColors.blue),
            const SizedBox(height: 12),
            Text(user!.studentId, style: AppTextStyles.monoMedium.copyWith(color: AppColors.textPrimaryOf(context))),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.refresh_rounded, size: 14, color: countdownColor),
              const SizedBox(width: 6),
              Text('Refreshes in ${countdown}s', style: TextStyle(color: countdownColor, fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Flexible(child: _Badge(user!.department, AppColors.blue)),
              const SizedBox(width: 8),
              Flexible(child: _Badge(_secondaryLabel(user!), AppColors.green)),
              const SizedBox(width: 8),
              Flexible(child: _Badge(user!.role, AppColors.gold)),
            ]),
          ]),
        ),
      ).animate().fadeIn(duration: AppMotion.durationOf(context, AppMotion.slow)),
    ]));
  }
}

class _Badge extends StatelessWidget {
  final String label; final Color color;
  const _Badge(this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: color.withValues(alpha:0.12), borderRadius: BorderRadius.circular(LiquidGlass.radiusPill),
        border: Border.all(color: color.withValues(alpha:0.3))),
    child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
        maxLines: 1, overflow: TextOverflow.ellipsis));
}

class _ScanTab extends StatefulWidget {
  @override State<_ScanTab> createState() => _ScanTabState();
}

class _ScanTabState extends State<_ScanTab> {
  final _ctrl = MobileScannerController();
  Map<String, dynamic>? _scannedUser;
  bool _verified = false, _expired = false, _scanning = true;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _onDetect(BarcodeCapture barcodes) async {
    if (!_scanning) return;
    final raw = barcodes.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;
    setState(() => _scanning = false);
    try {
      final decoded = jsonDecode(utf8.decode(base64Decode(raw)));
      final exp = decoded['exp'] as int? ?? 0;
      if (DateTime.now().millisecondsSinceEpoch > exp) {
        setState(() => _expired = true); return;
      }
      final uid = decoded['uid'] as String?;
      final vrid = decoded['vrid'] as String?;
      if (uid == null || vrid == null) return;
      // Server-side re-validation (HMAC + expiry) and the access-log insert
      // both happen inside this RPC — see verify_vr_id_scan migration.
      // A blanket "read any profile" RLS policy would be a real security
      // regression, so this narrow SECURITY DEFINER function is the only
      // path that can resolve a scanned user's profile.
      final rows = await SupabaseConfig.client.rpc('verify_vr_id_scan',
          params: {'p_uid': uid, 'p_vrid': vrid, 'p_exp': exp}) as List;
      final p = rows.firstOrNull as Map<String, dynamic>?;
      if (p == null) { if (mounted) setState(() => _verified = false); return; }
      if (mounted) setState(() { _scannedUser = p; _verified = true; });
    } catch (e) {
      debugPrint('[VrIdScan] verify failed: $e');
      if (mounted) setState(() => _verified = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_scannedUser != null) {
      return _VerifiedView(user: UserModel.fromJson(_scannedUser!), rawUser: _scannedUser!,
          verified: _verified, expired: _expired,
          onReset: () => setState(() { _scannedUser = null; _verified = false; _expired = false; _scanning = true; }));
    }
    return Stack(children: [
      MobileScanner(controller: _ctrl, onDetect: _onDetect),
      Center(child: Container(width: 220, height: 220,
          decoration: BoxDecoration(border: Border.all(color: AppColors.blue, width: 2), borderRadius: AppDepth.radius(2)))),
      Positioned(bottom: 40, left: 0, right: 0, child: Center(
          child: Text('Point camera at a VR-ID QR code', style: AppTextStyles.bodyMedium.copyWith(color: Colors.white)))),
    ]);
  }
}

class _VerifiedView extends StatelessWidget {
  final UserModel user; final Map<String, dynamic> rawUser;
  final bool verified, expired; final VoidCallback onReset;
  const _VerifiedView({required this.user, required this.rawUser, required this.verified, required this.expired, required this.onReset});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Icon(expired ? Icons.timer_off_rounded : verified ? Icons.verified_rounded : Icons.cancel_rounded,
        color: expired ? AppColors.amber : verified ? AppColors.green : AppColors.red, size: 72)
        // The overshoot is back, and now it is a token: AppMotion.emphasis
        // exists precisely because this stamp and the splash both wanted it.
        .animate().scale(
            duration: AppMotion.durationOf(context, AppMotion.slow),
            curve: AppMotion.emphasis),
    const SizedBox(height: 20),
    Text(expired ? 'QR Expired' : verified ? 'VERIFIED' : 'INVALID',
        style: AppTextStyles.displayMedium.copyWith(
            color: expired ? AppColors.amber : verified ? AppColors.green : AppColors.red)),
    if (verified) ...[
      const SizedBox(height: 20),
      Container(width: 84, height: 84, decoration: BoxDecoration(
          shape: BoxShape.circle, color: AppColors.green.withValues(alpha:0.1),
          border: Border.all(color: AppColors.green.withValues(alpha:0.4), width: 2)),
          child: ClipOval(child: (user.avatarUrl?.isNotEmpty ?? false)
              ? CachedNetworkImage(imageUrl: user.avatarUrl!, fit: BoxFit.cover, memCacheWidth: 200,
                  errorWidget: (_, __, ___) => const Icon(Icons.person_rounded, color: AppColors.green, size: 44))
              : const Icon(Icons.person_rounded, color: AppColors.green, size: 44))),
      const SizedBox(height: 16),
      Text(user.fullName, style: AppTextStyles.headlineLarge.copyWith(color: AppColors.textPrimaryOf(context))),
      Text(user.studentId, style: AppTextStyles.monoMedium.copyWith(color: AppColors.textSecondaryOf(context))),
      Text('${user.department} · ${_secondaryLabel(user)}', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context))),
      const SizedBox(height: 16),
      AfosButton(label: 'Open Verification PDF', icon: Icons.picture_as_pdf_rounded,
          onTap: () => VrIdPdfGenerator.generateAndOpen(rawUser)),
    ],
    const SizedBox(height: 16),
    AfosButton(label: 'Scan Again', icon: Icons.qr_code_scanner_rounded, onTap: onReset),
  ]));
}

class _WebScanPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(Icons.smartphone_rounded, color: AppColors.textMutedOf(context), size: 56),
    const SizedBox(height: 16),
    Text('Scanning is supported on mobile only', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context)), textAlign: TextAlign.center),
  ]));
}

class _AccessLogTab extends StatefulWidget {
  @override State<_AccessLogTab> createState() => _AccessLogTabState();
}

class _AccessLogTabState extends State<_AccessLogTab> {
  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) { setState(() => _loading = false); return; }
    setState(() => _error = null);
    try {
      final res = await SupabaseConfig.client.from('vr_access_log')
          .select('*, scanned_by:profiles!scanned_by_id(full_name)')
          .eq('scanned_user_id', uid).order('scanned_at', ascending: false) as List;
      if (mounted) setState(() => _logs = res.cast());
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Padding(padding: EdgeInsets.all(16), child: ShimmerList());
    if (_error != null) {
      return ErrorView(message: _error!, onRetry: _load);
    }
    if (_logs.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.history_rounded, color: AppColors.textMutedOf(context), size: 52),
      const SizedBox(height: 16),
      Text('No scans yet', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context))),
    ]));
    }
    return ListView.builder(padding: EdgeInsetsDirectional.fromSTEB(16, 16, 16, 16 + NavInsets.of(context)), itemCount: _logs.length,
        // Guarded by the `if (_logs.isEmpty) return Center(...)`
        // early-return above, so .first is safe.
        prototypeItem: _buildLogRow(context, _logs.first),
        itemBuilder: (ctx, i) => _buildLogRow(ctx, _logs[i]));
  }

  Widget _buildLogRow(BuildContext ctx, Map<String, dynamic> log) {
    final scanner = (log['scanned_by'] as Map?)?['full_name'] ?? 'Unknown';
    final time = log['scanned_at'] != null ? DateTime.tryParse(log['scanned_at']) : null;
    return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.surfaceOf(ctx), borderRadius: AppDepth.radius(1),
            border: Border.all(color: AppColors.borderOf(ctx), width: 0.5)),
        child: Row(children: [
          Container(width: 36, height: 36, decoration: BoxDecoration(
              color: AppColors.green.withValues(alpha:0.1), borderRadius: AppDepth.radius(0)),
              child: const Icon(Icons.qr_code_scanner_rounded, color: AppColors.green, size: 18)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Scanned by $scanner', style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimaryOf(ctx))),
            Text(log['location_note'] ?? 'Campus', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(ctx))),
          ])),
          if (time != null) Text(AppFormatters.relativeTime(time),
              style: AppTextStyles.labelSmall.copyWith(color: AppColors.textMutedOf(ctx))),
        ]));
  }
}
