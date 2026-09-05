import 'package:image_picker/image_picker.dart';

/// How large a photo is allowed to be BEFORE it is uploaded.
///
/// ---------------------------------------------------------------------------
/// THE MEASUREMENT THAT PRODUCED THIS FILE
///
/// Every call site used `pickImage(imageQuality: 70)` and nothing else.
/// `imageQuality` is a JPEG QUALITY knob — it never touches DIMENSIONS. So a
/// modern phone camera's 4000x3000 frame was re-encoded at quality 70 and
/// uploaded at full resolution. Measured in the live `avatars` bucket:
///
///     12 objects, average 378 KB, largest 928 KB
///
/// Those images are drawn into a circle whose largest decode in the whole app
/// is `memCacheWidth: 256` (profile_identity_header.dart). An avatar at that
/// size needs roughly 15–40 KB. Every account was therefore paying 10–30x its
/// own weight, on every screen that lists people.
///
/// On a fast phone that is invisible. On an entry-level phone it is the whole
/// complaint: a directory of 30 faces pulled ~11 MB from the Seoul region and
/// JPEG-decoded 30 full camera frames on a slow CPU with little RAM. That is
/// "photos take too long to load", and it is why it only shows up on the old
/// device.
///
/// ---------------------------------------------------------------------------
/// WHY `pickImage`'s OWN maxWidth/maxHeight, AND NOT `flutter_image_compress`
///
/// `flutter_image_compress` is already in `pubspec.yaml` and imported by
/// nothing — it has been shipping as dead weight in every APK. It would work,
/// but it is the wrong tool here: `pickImage` already accepts `maxWidth` /
/// `maxHeight`, applies them on Android, iOS AND web, and does the downscale
/// inside the platform picker BEFORE the bytes ever reach Dart. Compressing
/// afterwards would mean decoding the full frame into memory first — the exact
/// allocation that hurts most on the device we are trying to help.
///
/// ---------------------------------------------------------------------------
/// THESE CAPS ARE NOT A SECURITY CONTROL, and must never be treated as one.
///
/// The `avatars` and `lost-found` buckets each carry a server-side
/// `file_size_limit` of 5 MB and a MIME allowlist (migration
/// 20260903164058). That is the limit. This file is a QUALITY-OF-SERVICE
/// policy: it stops honest uploads from being 20x bigger than any screen can
/// use. SECURITY.md's rule — a client-side check that is the only thing
/// preventing an action is a finding — is satisfied by the bucket limits, not
/// by anything here.
class ImagePickPolicy {
  ImagePickPolicy._();

  /// Profile photos.
  ///
  /// 512 is deliberate headroom, not a guess: the largest decode anywhere in
  /// the app is `memCacheWidth: 256`, in physical pixels, so 512 is 2x what
  /// the biggest consumer asks for and still looks right if a future screen
  /// draws the avatar larger. Quality 85 rather than 70 because at this
  /// resolution the file is small either way and 70 shows visible blocking on
  /// a face.
  static const int avatarMaxEdge = 512;
  static const int avatarQuality = 85;

  /// Lost & found evidence photos.
  ///
  /// Larger than an avatar on purpose — the whole point of the picture is that
  /// someone can recognise their own property in it, so detail is the feature.
  /// 1280 comfortably exceeds the 440px decode the card uses today while
  /// staying an order of magnitude under a raw camera frame.
  static const int itemPhotoMaxEdge = 1280;
  static const int itemPhotoQuality = 80;

  /// A profile photo, downscaled by the platform picker before it reaches Dart.
  static Future<XFile?> pickAvatar({ImageSource source = ImageSource.gallery}) =>
      ImagePicker().pickImage(
        source: source,
        maxWidth: avatarMaxEdge.toDouble(),
        maxHeight: avatarMaxEdge.toDouble(),
        imageQuality: avatarQuality,
      );

  /// A lost & found item photo, downscaled the same way.
  static Future<XFile?> pickItemPhoto({ImageSource source = ImageSource.gallery}) =>
      ImagePicker().pickImage(
        source: source,
        maxWidth: itemPhotoMaxEdge.toDouble(),
        maxHeight: itemPhotoMaxEdge.toDouble(),
        imageQuality: itemPhotoQuality,
      );
}
