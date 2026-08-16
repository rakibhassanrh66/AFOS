import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/depth.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../shared/widgets/afos_button.dart';

/// Completing a Lost & Found handover by scanning the claimant's VR-ID.
///
/// WHY A SCAN AND NOT A BUTTON. Before this, the poster tapped "Mark Found" on
/// their own and the item was recorded as returned — no counterparty, no
/// evidence, and no record of WHO received it. An item could be closed with no
/// claimant at all. That is what made the whole flow feel unverified: it was.
///
/// The VR-ID is a server-signed rotating token that already exists for campus
/// identity, so this reuses it rather than inventing a second QR. The
/// verification is not done here — `complete_lost_found_handover` re-checks the
/// HMAC and the expiry **in the database**, confirms the scanned person is the
/// one whose claim was accepted, and only then marks the item returned. A
/// client cannot talk its way past any of that.
///
/// The scan is also written to `vr_access_log` by the same RPC, so the handover
/// leaves the same trail as every other campus ID scan.
///
/// WHO SCANS WHOM. The receiver scans the giver — whoever ends up holding the
/// item is the one who has to prove who handed it over. On a `lost` post that
/// is the poster scanning the finder; on a `found` post it is the claimant
/// scanning the poster. This screen used to assume the first case in its copy
/// ("scanning confirms THEY collected it"), which was exactly backwards for
/// half of all handovers.
class HandoverScanScreen extends StatefulWidget {
  final String postId;
  final String itemTitle;

  /// The person being scanned: the one handing the item over.
  final String giverName;

  /// 'lost' or 'found' — only used to word the confirmation honestly.
  final String postType;

  const HandoverScanScreen({
    super.key,
    required this.postId,
    required this.itemTitle,
    required this.giverName,
    required this.postType,
  });

  @override
  State<HandoverScanScreen> createState() => _HandoverScanScreenState();
}

class _HandoverScanScreenState extends State<HandoverScanScreen> {
  final _ctrl = MobileScannerController();
  bool _scanning = true;
  bool _done = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (!_scanning) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;
    setState(() { _scanning = false; _error = null; });

    try {
      final decoded = jsonDecode(utf8.decode(base64Decode(raw)));
      final uid = decoded['uid'] as String?;
      final vrid = decoded['vrid'] as String?;
      final exp = decoded['exp'] as int? ?? 0;
      if (uid == null || vrid == null) {
        setState(() { _error = 'That QR code is not an AFOS ID.'; });
        return;
      }

      // Everything that matters is decided server-side. The expiry is checked
      // there too — checking it here as well would only change the wording of
      // the failure, and a client clock is not evidence of anything.
      await SupabaseConfig.client.rpc('complete_lost_found_handover', params: {
        'p_post_id': widget.postId,
        'p_uid': uid,
        'p_vrid': vrid,
        'p_exp': exp,
      });

      if (!mounted) return;
      AppHaptics.success();
      setState(() => _done = true);
    } catch (e) {
      if (!mounted) return;
      // The RPC's messages are already written for the person holding the
      // phone — "That ID belongs to someone else. Scan the person whose claim
      // you accepted." — so they are shown as-is rather than replaced with a
      // generic failure.
      AppHaptics.warning();
      setState(() => _error = friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return _handedOver(context);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('Confirm handover'),
      ),
      body: Stack(children: [
        MobileScanner(controller: _ctrl, onDetect: _onDetect),

        // What to do, over the camera. A scanner with no instruction is a
        // black rectangle that the user has to guess at.
        Positioned(
          left: 20, right: 20, top: 12,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: AppDepth.radius(2),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(children: [
                Text('Scan ${widget.giverName}\'s VR-ID',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.titleMedium
                        .copyWith(color: Colors.white)),
                const SizedBox(height: 4),
                Text(
                  'Ask them to open AFOS → My VR-ID. Scanning confirms that '
                  'YOU received "${widget.itemTitle}" from them.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.labelSmall
                      .copyWith(color: Colors.white70),
                ),
              ]),
            ),
          ),
        ),

        if (_error != null)
          Positioned(
            left: 20, right: 20, bottom: 28,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.red.withValues(alpha: 0.92),
                borderRadius: AppDepth.radius(2),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(children: [
                  Text(_error!,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: Colors.white)),
                  const SizedBox(height: 10),
                  AfosButton(
                    label: 'Scan again',
                    outlined: true,
                    onTap: () => setState(() {
                      _error = null;
                      _scanning = true;
                    }),
                  ),
                ]),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _handedOver(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 88, height: 88,
                decoration: BoxDecoration(
                  color: AppColors.green.withValues(alpha: 0.12),
                  borderRadius: AppDepth.radius(2),
                  border: Border.all(color: AppColors.green.withValues(alpha: 0.3)),
                ),
                child: const Icon(Icons.verified_rounded,
                    color: AppColors.green, size: 40),
              ),
              const SizedBox(height: 20),
              Text('Handover confirmed',
                  style: AppTextStyles.headlineLarge
                      .copyWith(color: AppColors.textPrimaryOf(context))),
              const SizedBox(height: 8),
              Text(
                widget.postType == 'lost'
                    ? '"${widget.itemTitle}" is recorded as returned to you by '
                      '${widget.giverName}, verified by their campus ID.'
                    : '"${widget.itemTitle}" is recorded as collected by you '
                      'from ${widget.giverName}, verified by their campus ID.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textSecondaryOf(context)),
              ),
              const SizedBox(height: 24),
              AfosButton(
                label: 'Done',
                onTap: () => Navigator.of(context).pop(true),
              ),
            ]),
          ),
        ),
      );
}
