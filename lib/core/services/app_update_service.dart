import 'dart:io';
import 'package:dio/dio.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import '../../config/app_config.dart';
import '../../config/supabase_config.dart';

/// One available update, resolved from `app_releases` (see
/// `releases_screen.dart`, which reads the same table for "What's New").
class AppUpdateInfo {
  final String version;
  final String title;
  final List<String> highlights;
  final String downloadUrl;
  const AppUpdateInfo({
    required this.version,
    required this.title,
    required this.highlights,
    required this.downloadUrl,
  });
}

/// Checks for, downloads, and launches the installer for a newer AFOS build —
/// so a user can update from inside the app instead of finding the GitHub
/// release page and downloading the APK in a browser themselves.
///
/// The APK itself is NOT stored anywhere in Supabase — `app_releases` only
/// carries the version/highlights metadata the in-app "What's New" screen
/// already reads. The actual file lives as a GitHub Release asset, uploaded
/// by `.github/workflows/main.yml`'s release job
/// (`dist/AFOS-${GITHUB_REF_NAME}.apk` via softprops/action-gh-release), so
/// the download URL is built from that same well-known naming pattern rather
/// than needing an extra GitHub API call.
class AppUpdateService {
  AppUpdateService._();

  static const _owner = 'rakibhassanrh66';
  static const _repo = 'AFOS';

  static String _apkUrlFor(String version) =>
      'https://github.com/$_owner/$_repo/releases/download/v$version/AFOS-v$version.apk';

  /// Returns the newest available update, or null if the installed version is
  /// already current (or the check failed — best-effort, never blocks
  /// anything the caller is doing).
  static Future<AppUpdateInfo?> checkForUpdate() async {
    try {
      final row = await SupabaseConfig.client
          .from('app_releases')
          .select('version, title, highlights')
          .order('release_date', ascending: false)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      final latest = row?['version'] as String?;
      if (latest == null || !_isNewer(latest, AppConfig.appVersion)) return null;
      return AppUpdateInfo(
        version: latest,
        title: row?['title'] as String? ?? 'AFOS $latest',
        highlights: (row?['highlights'] as List?)?.cast<String>() ?? const [],
        downloadUrl: _apkUrlFor(latest),
      );
    } catch (_) {
      return null;
    }
  }

  /// Numeric, per-segment comparison ("2.3.9" < "2.3.10") — a plain string
  /// compare would get this backwards on the last segment once either
  /// version reaches double digits there.
  static bool _isNewer(String remote, String local) {
    final r = remote.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final l = local.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    for (var i = 0; i < 3; i++) {
      final rv = i < r.length ? r[i] : 0;
      final lv = i < l.length ? l[i] : 0;
      if (rv != lv) return rv > lv;
    }
    return false;
  }

  static Future<String> _apkPath(String version) async {
    final dir = await getTemporaryDirectory();
    return '${dir.path}/afos_update_$version.apk';
  }

  /// Deletes any update APK left over from a PRIOR check — not the one being
  /// downloaded right now. Deliberately never touches the current download:
  /// `OpenFile.open()` below only launches Android's package installer
  /// Intent and returns immediately, it does not wait for the user to
  /// actually finish the install — deleting the file right after that call
  /// would race the installer still reading it. By the time the user comes
  /// back to check for an update again, any previous install has long since
  /// finished, so cleaning up old files THEN is safe. Downloading to
  /// getTemporaryDirectory() in the first place (not a persistent/visible
  /// Documents folder) already keeps this out of the user's own storage view
  /// and eligible for the OS's own cache reclamation in the meantime.
  static Future<void> _cleanupOldDownloads({String? keep}) async {
    try {
      final dir = await getTemporaryDirectory();
      final entries = await dir.list().toList();
      for (final e in entries) {
        if (e is! File) continue;
        final name = e.uri.pathSegments.last;
        if (!name.startsWith('afos_update_') || !name.endsWith('.apk')) continue;
        if (keep != null && name == 'afos_update_$keep.apk') continue;
        try { await e.delete(); } catch (_) {}
      }
    } catch (_) {}
  }

  /// Downloads the APK for [update] with progress (0.0–1.0 via [onProgress])
  /// and opens Android's package installer on it. Throws on a genuine
  /// download failure — the caller is expected to show that to the user,
  /// since a silent failure here would look like "tap Update, nothing
  /// happens".
  static Future<void> downloadAndInstall(
    AppUpdateInfo update, {
    void Function(double progress)? onProgress,
  }) async {
    await _cleanupOldDownloads(keep: update.version);
    final path = await _apkPath(update.version);
    await Dio().download(
      update.downloadUrl,
      path,
      onReceiveProgress: (received, total) {
        if (total > 0 && onProgress != null) onProgress(received / total);
      },
    );
    await OpenFile.open(path);
  }
}
