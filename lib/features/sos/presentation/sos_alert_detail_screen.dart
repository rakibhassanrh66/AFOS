import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/auth/role_session.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../notifications/data/repositories/notification_service.dart';
import '../../shell/presentation/top_app_bar.dart';
import '../data/repositories/sos_repository.dart';

import '../../../shared/widgets/glass_bottom_nav.dart';
/// Reached from the SOS push notification's deep link ('/sos/:id') or from
/// manage_sos_screen.dart's oversight list. Shows the sender's live
/// position (flutter_map/OSM -- no Google Maps key needed, same as
/// transport_screen.dart) plus a voice note if one was recorded.
class SosAlertDetailScreen extends StatefulWidget {
  final String alertId;
  const SosAlertDetailScreen({super.key, required this.alertId});
  @override State<SosAlertDetailScreen> createState() => _SosAlertDetailScreenState();
}

class _SosAlertDetailScreenState extends State<SosAlertDetailScreen> {
  Map<String, dynamic>? _alert;
  bool _loading = true;
  String? _error;
  final _player = AudioPlayer();
  bool _playingVoice = false;
  bool _resolving = false;

  StreamSubscription? _responsesSub;
  List<Map<String, dynamic>> _responses = [];
  final Map<String, Map<String, dynamic>> _responderProfiles = {};
  bool _responding = false;

  @override
  void initState() {
    super.initState();
    _load();
    _responsesSub = SosRepository.watchResponses(widget.alertId).listen((rows) {
      if (!mounted) return;
      setState(() => _responses = rows);
      _loadResponderProfiles(rows);
    });
  }

  @override
  void dispose() { _player.dispose(); _responsesSub?.cancel(); super.dispose(); }

  Future<void> _loadResponderProfiles(List<Map<String, dynamic>> rows) async {
    // .stream() can't embed a join, so responder names/avatars are resolved
    // separately -- only for ids not already cached, since this re-runs on
    // every realtime tick.
    final missing = rows.map((r) => r['responder_id'] as String)
        .where((id) => !_responderProfiles.containsKey(id)).toSet().toList();
    if (missing.isEmpty) return;
    try {
      final res = await SupabaseConfig.client.from('profiles')
          .select('id, full_name, avatar_url').inFilter('id', missing) as List;
      if (!mounted) return;
      setState(() {
        for (final p in res) { _responderProfiles[p['id'] as String] = p as Map<String, dynamic>; }
      });
    } catch (_) {
      // Best-effort -- the responder count/button state doesn't depend on this.
    }
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final a = await SosRepository.fetchById(widget.alertId);
      if (mounted) setState(() { _alert = a; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  bool get _isOwner => _alert != null && _alert!['user_id'] == SupabaseConfig.uid;
  bool get _hasResponded =>
      _responses.any((r) => r['responder_id'] == SupabaseConfig.uid);

  Future<void> _toggleRespond() async {
    setState(() => _responding = true);
    try {
      if (_hasResponded) {
        await SosRepository.withdrawResponse(widget.alertId);
      } else {
        await SosRepository.respond(widget.alertId);
        final me = await SupabaseConfig.client.from('profiles')
            .select('full_name').eq('id', SupabaseConfig.uid as String).maybeSingle();
        final myName = me?['full_name'] as String? ?? 'Someone';
        final ownerId = _alert!['user_id'] as String;
        // Best-effort -- a notify failure shouldn't undo the response itself.
        unawaited(NotificationService.sendToUsers(
          userIds: [ownerId],
          title: '🏃 Help is on the way',
          message: '$myName is responding to your SOS alert.',
          deepLink: '/sos/${widget.alertId}',
          category: 'sos',
        ));
        unawaited(NotificationService.notifyRoles(
          roles: ['admin', 'super_admin', 'staff'],
          title: 'SOS responder',
          message: '$myName is responding to an active SOS alert.',
          deepLink: '/sos/${widget.alertId}',
          category: 'sos',
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
    if (mounted) setState(() => _responding = false);
  }

  Future<void> _playVoice(String path) async {
    try {
      final url = await SupabaseConfig.client.storage.from('sos-voice').createSignedUrl(path, 300);
      setState(() => _playingVoice = true);
      await _player.play(UrlSource(url));
      _player.onPlayerComplete.first.then((_) { if (mounted) setState(() => _playingVoice = false); });
    } catch (e) {
      if (mounted) {
        setState(() => _playingVoice = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
  }

  Future<void> _openDirections(double lat, double lng) async {
    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _call(String phone) async {
    await launchUrl(Uri.parse('tel:$phone'));
  }

  Future<void> _resolve(String status) async {
    setState(() => _resolving = true);
    try {
      await SosRepository.resolve(widget.alertId, status: status);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
    if (mounted) setState(() => _resolving = false);
  }

  bool get _canResolve => const ['admin', 'super_admin', 'staff', 'dept_admin'].contains(RoleSession.role);

  // The sender's home address as registered on their profile -- separate
  // from the live GPS pin on the map below, since a recipient reading this
  // quickly (an upazila/district name) is faster than interpreting a map
  // when deciding whether they're actually close enough to help.
  static String _roleLabel(String? role) => switch (role) {
    'teacher' => 'Teacher', 'staff' => 'Staff', 'admin' => 'Admin',
    'dept_admin' => 'Dept Admin', 'super_admin' => 'Super Admin',
    'exam_controller' => 'Exam Controller', 'student' => 'Student',
    _ => 'Student',
  };

  String? _registeredAddress(Map<String, dynamic> sender) {
    final parts = [sender['permanent_upazila'], sender['permanent_district'], sender['permanent_division']]
        .whereType<String>().where((s) => s.trim().isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const AfosAppBar(title: 'SOS Alert'),
      body: _loading
          ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList(count: 4))
          : _error != null || _alert == null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.error_outline_rounded, color: AppColors.red, size: 40),
                  const SizedBox(height: 12),
                  Text(_error ?? 'Alert not found', textAlign: TextAlign.center, style: TextStyle(color: textSecondary)),
                  const SizedBox(height: 12),
                  TextButton(onPressed: _load, child: const Text('Retry')),
                ])))
              : _buildContent(context, textPrimary, textSecondary),
    );
  }

  Widget _buildContent(BuildContext context, Color textPrimary, Color textSecondary) {
    final a = _alert!;
    final sender = a['profiles'] as Map<String, dynamic>? ?? {};
    final lat = (a['latitude'] as num).toDouble();
    final lng = (a['longitude'] as num).toDouble();
    final status = a['status'] as String? ?? 'active';
    final voicePath = a['voice_path'] as String?;
    final point = LatLng(lat, lng);

    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 16 + GlassBottomNav.navContentClearance), children: [
      Row(children: [
        CircleAvatar(radius: 24, backgroundColor: AppColors.red.withValues(alpha: 0.15),
            backgroundImage: sender['avatar_url'] != null ? CachedNetworkImageProvider(sender['avatar_url']) : null,
            child: sender['avatar_url'] == null ? const Icon(Icons.person, color: AppColors.red) : null),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(child: Text(sender['full_name'] ?? 'Unknown', style: AppTextStyles.titleLarge.copyWith(color: textPrimary),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (sender['is_verified'] == true) const Padding(padding: EdgeInsets.only(left: 5),
                child: Icon(Icons.verified_rounded, color: AppColors.blue, size: 16)),
          ]),
          Text(_roleLabel(sender['role'] as String?),
              style: AppTextStyles.labelSmall.copyWith(color: textSecondary, fontWeight: FontWeight.w600)),
          Text(a['zone_type'] == 'campus' ? 'On/near campus' : 'Elsewhere in Bangladesh',
              style: AppTextStyles.labelSmall.copyWith(color: textSecondary)),
          if (_registeredAddress(sender) != null)
            Text('Registered address: ${_registeredAddress(sender)}',
                style: AppTextStyles.labelSmall.copyWith(color: textSecondary),
                maxLines: 1, overflow: TextOverflow.ellipsis),
        ])),
        Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: (status == 'active' ? AppColors.red : AppColors.green).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12)),
            child: Text(status.toUpperCase(),
                style: TextStyle(color: status == 'active' ? AppColors.red : AppColors.green, fontWeight: FontWeight.w700, fontSize: 11))),
      ]),
      if (a['message'] != null) ...[
        const SizedBox(height: 12),
        Text(a['message'], style: AppTextStyles.bodyMedium.copyWith(color: textPrimary)),
      ],
      const SizedBox(height: 16),
      ClipRRect(borderRadius: BorderRadius.circular(16), child: SizedBox(height: 220,
          child: FlutterMap(
            options: MapOptions(initialCenter: point, initialZoom: 16),
            children: [
              TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.example.afos_v7'),
              MarkerLayer(markers: [
                Marker(point: point, width: 40, height: 40,
                    child: const Icon(Icons.location_on, color: AppColors.red, size: 40)),
              ]),
            ],
          ))),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: OutlinedButton.icon(
            onPressed: () => _openDirections(lat, lng),
            icon: const Icon(Icons.directions_rounded, size: 18),
            label: const Text('Directions'))),
        if (sender['phone'] != null) ...[
          const SizedBox(width: 12),
          Expanded(child: OutlinedButton.icon(
              onPressed: () => _call(sender['phone']),
              icon: const Icon(Icons.call_rounded, size: 18),
              label: const Text('Call'))),
        ],
      ]),
      if (voicePath != null) ...[
        const SizedBox(height: 12),
        OutlinedButton.icon(
            onPressed: _playingVoice ? null : () => _playVoice(voicePath),
            icon: Icon(_playingVoice ? Icons.graphic_eq_rounded : Icons.play_arrow_rounded, size: 18),
            label: Text(_playingVoice ? 'Playing voice note…' : 'Play voice note')),
      ],
      if (!_isOwner && status == 'active') ...[
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: _hasResponded
            ? OutlinedButton.icon(
                onPressed: _responding ? null : _toggleRespond,
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('Cancel — not going anymore'))
            : ElevatedButton.icon(
                onPressed: _responding ? null : _toggleRespond,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.holoTeal, minimumSize: const Size(0, 44)),
                icon: const Icon(Icons.directions_run_rounded, size: 18),
                label: const Text("I'm on my way"))),
      ],
      if (_responses.isNotEmpty) ...[
        const SizedBox(height: 20),
        Text('${_responses.length} ${_responses.length == 1 ? 'person is' : 'people are'} on the way',
            style: AppTextStyles.labelSmall.copyWith(color: textSecondary, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        ..._responses.map((r) {
          final p = _responderProfiles[r['responder_id']];
          return Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [
            CircleAvatar(radius: 14, backgroundColor: AppColors.holoTeal.withValues(alpha: 0.15),
                backgroundImage: p?['avatar_url'] != null ? CachedNetworkImageProvider(p!['avatar_url']) : null,
                child: p?['avatar_url'] == null ? const Icon(Icons.person, color: AppColors.holoTeal, size: 14) : null),
            const SizedBox(width: 10),
            Text(p?['full_name'] as String? ?? 'Someone', style: AppTextStyles.bodyMedium.copyWith(color: textPrimary)),
          ]));
        }),
      ],
      if (_canResolve && status == 'active') ...[
        const SizedBox(height: 24),
        Row(children: [
          Expanded(child: ElevatedButton(
              onPressed: _resolving ? null : () => _resolve('resolved'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.green, minimumSize: const Size(0, 44)),
              child: const Text('Mark Resolved'))),
          const SizedBox(width: 12),
          Expanded(child: OutlinedButton(
              onPressed: _resolving ? null : () => _resolve('false_alarm'),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.textSecondaryOf(context), minimumSize: const Size(0, 44)),
              child: const Text('False Alarm'))),
        ]),
      ],
    ]);
  }
}
