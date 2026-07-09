import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../core/utils/location_helper.dart';
import '../data/repositories/sos_repository.dart';

/// Persistent emergency-alert button, mounted once in AppShell's Stack so
/// it appears on every authenticated screen. Hold-to-arm (not a plain tap)
/// guards against pocket-taps given the real-world cost of a false mass
/// alert; a cancelable countdown follows before anything actually sends.
class SosFloatingButton extends StatefulWidget {
  const SosFloatingButton({super.key});
  @override State<SosFloatingButton> createState() => _SosFloatingButtonState();
}

class _SosFloatingButtonState extends State<SosFloatingButton> with SingleTickerProviderStateMixin {
  late final AnimationController _armController =
      AnimationController(vsync: this, duration: const Duration(seconds: 2));

  @override
  void dispose() { _armController.dispose(); super.dispose(); }

  void _onHoldStart() {
    HapticFeedback.mediumImpact();
    _armController.forward(from: 0);
    _armController.addStatusListener(_onArmStatus);
  }

  void _onHoldEnd() {
    if (_armController.value < 1) _armController.reverse();
  }

  void _onArmStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _armController.removeStatusListener(_onArmStatus);
      HapticFeedback.heavyImpact();
      _armController.value = 0;
      _showConfirmSheet();
    }
  }

  void _showConfirmSheet() {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: AppColors.surfaceOf(context),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => _SosConfirmSheet(onSend: () => _sendAlert(sheetCtx)),
    );
  }

  Future<void> _sendAlert(BuildContext sheetCtx, {String? voicePath}) async {
    final rootCtx = context;
    // Highest accuracy setting specifically for the actual SOS trigger --
    // this is the one location fix that genuinely matters most in the
    // whole app, worth the extra second or two of GPS settle time that
    // transport's one-shot "show me on map" doesn't need.
    final pos = await LocationHelper.getCurrentPosition(
      accuracy: LocationAccuracy.best,
      onError: (msg) {
        if (rootCtx.mounted) ScaffoldMessenger.of(rootCtx).showSnackBar(
            SnackBar(content: Text(msg), backgroundColor: AppColors.red));
      },
    );
    if (pos == null) return;

    String? voiceStoragePath;
    if (voicePath != null) {
      try {
        final uid = SupabaseConfig.uid;
        final ext = voicePath.split('.').last;
        voiceStoragePath = '$uid/${DateTime.now().millisecondsSinceEpoch}.$ext';
        await SupabaseConfig.client.storage.from('sos-voice')
            .uploadBinary(voiceStoragePath, await File(voicePath).readAsBytes());
      } catch (_) {
        // Best-effort -- a failed voice upload shouldn't block the alert
        // itself from going out.
        voiceStoragePath = null;
      }
    }

    try {
      final result = await SosRepository.triggerAlert(
        latitude: pos.latitude, longitude: pos.longitude, voicePath: voiceStoragePath,
      );
      if (rootCtx.mounted) ScaffoldMessenger.of(rootCtx).showSnackBar(SnackBar(
          content: Text('Alert sent to ${result['recipientCount'] ?? 0} people nearby'),
          backgroundColor: AppColors.green));
    } catch (e) {
      if (rootCtx.mounted) ScaffoldMessenger.of(rootCtx).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16, bottom: 88,
      child: GestureDetector(
        onLongPressStart: (_) => _onHoldStart(),
        onLongPressEnd: (_) => _onHoldEnd(),
        onLongPressCancel: _onHoldEnd,
        child: AnimatedBuilder(
          animation: _armController,
          builder: (ctx, child) => SizedBox(
            width: 64, height: 64,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox(width: 64, height: 64, child: CircularProgressIndicator(
                  value: _armController.value, strokeWidth: 3,
                  backgroundColor: Colors.transparent,
                  valueColor: const AlwaysStoppedAnimation(Colors.white))),
              child!,
            ]),
          ),
          child: Container(
            width: 54, height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.red,
              boxShadow: [BoxShadow(color: AppColors.red.withValues(alpha: 0.5), blurRadius: 12, spreadRadius: 1)],
            ),
            child: const Icon(Icons.sos_rounded, color: Colors.white, size: 28),
          ).animate(onPlay: (c) => c.repeat(reverse: true)).scaleXY(end: 1.06, duration: 900.ms),
        ),
      ),
    );
  }
}

class _SosConfirmSheet extends StatefulWidget {
  final Future<void> Function() onSend;
  const _SosConfirmSheet({required this.onSend});
  @override State<_SosConfirmSheet> createState() => _SosConfirmSheetState();
}

class _SosConfirmSheetState extends State<_SosConfirmSheet> {
  static const _countdownSeconds = 5;
  static const _maxRecordSeconds = 20;

  int _remaining = _countdownSeconds;
  Timer? _timer;
  bool _cancelled = false;
  bool _sent = false;

  final _recorder = AudioRecorder();
  bool _recording = false;
  String? _recordedPath;
  int _recordSeconds = 0;
  Timer? _recordTimer;

  @override
  void initState() { super.initState(); _startCountdown(); }

  void _startCountdown() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_cancelled || _recording) return;
      setState(() => _remaining--);
      if (_remaining <= 0) { t.cancel(); _dispatch(); }
    });
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      final path = await _recorder.stop();
      _recordTimer?.cancel();
      setState(() { _recording = false; _recordedPath = path; });
      return;
    }
    if (!await _recorder.hasPermission()) return;
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/sos_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(), path: path);
    setState(() { _recording = true; _recordSeconds = 0; _recordedPath = null; });
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() => _recordSeconds++);
      if (_recordSeconds >= _maxRecordSeconds) _toggleRecording();
    });
  }

  Future<void> _dispatch() async {
    if (_sent) return;
    _sent = true;
    if (_recording) await _toggleRecording();
    if (mounted) Navigator.pop(context);
    await widget.onSend();
  }

  void _cancel() {
    _cancelled = true;
    _timer?.cancel();
    _recordTimer?.cancel();
    if (_recording) _recorder.stop();
    Navigator.pop(context);
  }

  @override
  void dispose() { _timer?.cancel(); _recordTimer?.cancel(); _recorder.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.sos_rounded, color: AppColors.red, size: 40),
          const SizedBox(height: 12),
          Text('Sending SOS in $_remaining s', style: AppTextStyles.headlineMed.copyWith(color: textPrimary)),
          const SizedBox(height: 6),
          Text('Your location will be shared with nearby people and staff.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: _toggleRecording,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                  color: (_recording ? AppColors.red : AppColors.blue).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(24)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(_recording ? Icons.stop_circle_rounded : Icons.mic_rounded,
                    color: _recording ? AppColors.red : AppColors.blue, size: 20),
                const SizedBox(width: 8),
                Text(_recording ? 'Recording… ${_recordSeconds}s (tap to stop)'
                        : _recordedPath != null ? 'Voice note added ✓' : 'Add a voice note (optional)',
                    style: TextStyle(color: _recording ? AppColors.red : AppColors.blue, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, child: OutlinedButton(
              onPressed: _cancel,
              style: OutlinedButton.styleFrom(foregroundColor: textSecondary, minimumSize: const Size(0, 48)),
              child: const Text('Cancel'))),
        ]),
      ),
    );
  }
}
