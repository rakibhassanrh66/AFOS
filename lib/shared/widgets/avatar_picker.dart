import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../config/supabase_config.dart';
import '../../config/theme/app_colors.dart';
import '../../config/theme/app_text_styles.dart';
import '../../core/haptics/app_haptics.dart';
import '../../core/network/storage_upload_service.dart';
import '../../core/utils/error_formatter.dart';
import 'glass_sheet.dart';
import 'pill_badge.dart';
import 'supernova_loader.dart';

/// Shared avatar upload/display widget — pulled out of Settings so the
/// Edit Profile screen can offer the same photo change flow instead of
/// forcing users back to Settings just to change their picture.
class AvatarPicker extends StatefulWidget {
  final String? avatarUrl;
  final String initials;
  final ValueChanged<String?> onChanged;

  /// A submitted photo awaiting admin review, if any — `profiles.avatar_pending_url`.
  final String? pendingUrl;

  /// `profiles.avatar_review_status`: 'none' | 'pending' | 'approved' | 'rejected'.
  final String? reviewStatus;

  /// Why a photo was rejected — `profiles.avatar_review_reason`.
  final String? reviewReason;

  const AvatarPicker({
    super.key, required this.avatarUrl, required this.initials, required this.onChanged,
    this.pendingUrl, this.reviewStatus, this.reviewReason,
  });

  @override State<AvatarPicker> createState() => _AvatarPickerState();
}

class _AvatarPickerState extends State<AvatarPicker> {
  bool _saving = false;

  Future<void> _pickAndUpload() async {
    final img = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (img == null) return;
    // BUG_REGISTER P1-01: setState after an awaited platform round-trip with no
    // mounted guard. The gallery picker is exactly the kind of await a user can
    // navigate away from.
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      final url = await StorageUploadService.uploadImage(bucket: 'avatars', image: img);
      // NOT a direct write to avatar_url. Every photo goes through admin
      // review before it becomes the live picture shown elsewhere in the
      // app — this RPC only stages it as pending.
      debugPrint('[avatar] uploaded to storage, submitting for review: $url');
      await SupabaseConfig.client.rpc('my_submit_avatar', params: {'p_url': url});
      debugPrint('[avatar] my_submit_avatar OK');
      widget.onChanged(url);
      if (mounted) {
        AppHaptics.success();
        // Never "updated" or "approved" here — no check has happened yet.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo submitted for review'), backgroundColor: AppColors.green));
      }
    } catch (e) {
      // The raw error, not just the friendly one. This failed live on a real
      // account with "Not authorized to change avatar review state" and was
      // undiagnosable afterwards, because the only trace of it was a SnackBar
      // that had already gone: nothing reached logcat, so there was no way to
      // tell WHICH of the two steps above threw, or what PostgREST actually
      // said. `friendlyError` deliberately throws detail away for the user —
      // that detail is exactly what a bug report needs.
      debugPrint('[avatar] SUBMIT FAILED: ${e.runtimeType} -> $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _remove() async {
    setState(() => _saving = true);
    try {
      await SupabaseConfig.client.from('profiles')
          .update({'avatar_url': null}).eq('id', SupabaseConfig.uid!);
      widget.onChanged(null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo removed'), backgroundColor: AppColors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  void _showOptions() {
    showGlassSheet(context, child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: const Icon(Icons.photo_library_outlined),
          title: const Text('Choose new photo'),
          onTap: () { Navigator.pop(context); _pickAndUpload(); }),
      if (widget.avatarUrl != null) ListTile(
          leading: const Icon(Icons.delete_outline_rounded, color: AppColors.red),
          title: const Text('Remove photo', style: TextStyle(color: AppColors.red)),
          onTap: () { Navigator.pop(context); _remove(); }),
    ]));
  }

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Stack(children: [
        GestureDetector(
          onTap: _showOptions,
          child: Container(
            width: 88, height: 88,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.blue.withValues(alpha: 0.4), width: 2),
                color: AppColors.surfaceOf(context)),
            child: ClipOval(child: widget.avatarUrl != null
                ? CachedNetworkImage(imageUrl: widget.avatarUrl!, fit: BoxFit.cover, memCacheWidth: 200,
                    errorWidget: (_, __, ___) => _initials(context))
                : _initials(context)),
          ),
        ),
        Positioned(bottom: 0, right: 0,
            child: Container(width: 28, height: 28,
                decoration: const BoxDecoration(color: AppColors.blue, shape: BoxShape.circle),
                child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 15))),
      ]),
      if (_saving) const Padding(padding: EdgeInsets.only(top: 8),
          child: SupernovaLoader(size: 28, color: AppColors.blue)),
      if (!_saving && widget.reviewStatus == 'pending')
        const Padding(padding: EdgeInsets.only(top: 8),
            child: PillBadge(label: 'PENDING REVIEW', color: AppColors.amber)),
      if (!_saving && widget.reviewStatus == 'rejected') ...[
        const SizedBox(height: 8),
        GestureDetector(onTap: _showOptions,
            child: const PillBadge(label: 'REJECTED — TAP TO RETRY', color: AppColors.red)),
        if ((widget.reviewReason ?? '').trim().isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 4),
              child: Text(widget.reviewReason!, textAlign: TextAlign.center,
                  style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(context)))),
      ],
    ]);
  }

  Widget _initials(BuildContext context) => Container(color: AppColors.surfaceOf(context),
      child: Center(child: Text(widget.initials,
          style: const TextStyle(color: AppColors.blue, fontSize: 28, fontWeight: FontWeight.bold))));
}
