import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../config/supabase_config.dart';
import '../../config/theme/app_colors.dart';
import '../../core/network/storage_upload_service.dart';
import '../../core/utils/error_formatter.dart';
import 'supernova_loader.dart';

/// Shared avatar upload/display widget — pulled out of Settings so the
/// Edit Profile screen can offer the same photo change flow instead of
/// forcing users back to Settings just to change their picture.
class AvatarPicker extends StatefulWidget {
  final String? avatarUrl;
  final String initials;
  final ValueChanged<String?> onChanged;
  const AvatarPicker({super.key, required this.avatarUrl, required this.initials, required this.onChanged});

  @override State<AvatarPicker> createState() => _AvatarPickerState();
}

class _AvatarPickerState extends State<AvatarPicker> {
  bool _saving = false;

  Future<void> _pickAndUpload() async {
    final img = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (img == null) return;
    setState(() => _saving = true);
    try {
      final url = await StorageUploadService.uploadImage(bucket: 'avatars', image: img);
      await SupabaseConfig.client.from('profiles')
          .update({'avatar_url': url}).eq('id', SupabaseConfig.uid!);
      widget.onChanged(url);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo updated ✓'), backgroundColor: AppColors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _remove() async {
    setState(() => _saving = true);
    try {
      await SupabaseConfig.client.from('profiles')
          .update({'avatar_url': null}).eq('id', SupabaseConfig.uid!);
      widget.onChanged(null);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo removed'), backgroundColor: AppColors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
    }
    if (mounted) setState(() => _saving = false);
  }

  void _showOptions() {
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: AppColors.surfaceOf(context),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (sheetCtx) => SafeArea(child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose new photo'),
              onTap: () { Navigator.pop(sheetCtx); _pickAndUpload(); }),
          if (widget.avatarUrl != null) ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: AppColors.red),
              title: const Text('Remove photo', style: TextStyle(color: AppColors.red)),
              onTap: () { Navigator.pop(sheetCtx); _remove(); }),
          const SizedBox(height: 8),
        ]))));
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
                ? CachedNetworkImage(imageUrl: widget.avatarUrl!, fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => _initials(context))
                : _initials(context)),
          ),
        ),
        Positioned(bottom: 0, right: 0,
            child: Container(width: 28, height: 28,
                decoration: const BoxDecoration(color: AppColors.blue, shape: BoxShape.circle),
                child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 15))),
      ]),
      if (_saving) Padding(padding: const EdgeInsets.only(top: 8),
          child: const SupernovaLoader(size: 28, color: AppColors.blue)),
    ]);
  }

  Widget _initials(BuildContext context) => Container(color: AppColors.surfaceOf(context),
      child: Center(child: Text(widget.initials,
          style: const TextStyle(color: AppColors.blue, fontSize: 28, fontWeight: FontWeight.bold))));
}
