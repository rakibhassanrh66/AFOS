import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/supabase_config.dart';

/// Uploads images to Supabase Storage under {bucket}/{auth.uid()}/{filename},
/// matching the storage RLS policies which restrict writes to the caller's
/// own folder. Returns the public URL to store as profile/post metadata.
class StorageUploadService {
  StorageUploadService._();

  static Future<String> uploadImage({
    required String bucket,
    required XFile image,
  }) async {
    final uid = SupabaseConfig.uid;
    if (uid == null) throw Exception('Not signed in.');
    final ext = image.name.contains('.') ? image.name.split('.').last : 'jpg';
    final path = '$uid/${DateTime.now().millisecondsSinceEpoch}.$ext';
    final bytes = await image.readAsBytes();
    await SupabaseConfig.client.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: 'image/${ext == 'jpg' ? 'jpeg' : ext}'),
        );
    return SupabaseConfig.client.storage.from(bucket).getPublicUrl(path);
  }
}
