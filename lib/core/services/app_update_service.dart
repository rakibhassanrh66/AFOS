import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/app_config.dart';
import '../../config/supabase_config.dart';

/// One available update, resolved from `app_releases` (see
/// `releases_screen.dart`, which reads the same table for "What's New").
class AppUpdateInfo {
  final String version;
  final String title;
  final List<String> highlights;
  final String downloadUrl;

  /// The universal APK, tried only if [downloadUrl] (the small per-ABI slice)
  /// turns out not to exist for this release. Null when they are the same URL.
  final String? fallbackUrl;

  const AppUpdateInfo({
    required this.version,
    required this.title,
    required this.highlights,
    required this.downloadUrl,
    this.fallbackUrl,
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

  /// The update currently on offer, or null when this build is the newest.
  ///
  /// Published rather than returned so a release that goes live WHILE the app
  /// is open still reaches the user: [start] keeps this in sync off a realtime
  /// subscription. Before, the only thing that ever ran a check was opening the
  /// Settings screen, so "an update is available" was something the user had to
  /// go looking for.
  static final ValueNotifier<AppUpdateInfo?> available =
      ValueNotifier<AppUpdateInfo?>(null);

  static RealtimeChannel? _sub;

  /// Checks once now, then re-checks whenever a row lands in `app_releases`.
  ///
  /// Called from bootstrap alongside [BadgeService.start] and torn down on
  /// sign-out the same way. `app_releases` is world-readable (it is the What's
  /// New source), so this needs no role handling.
  static Future<void> start() async {
    available.value = await checkForUpdate();
    await _sub?.unsubscribe();
    _sub = SupabaseConfig.client
        .channel('app_release_watch')
        .onPostgresChanges(
          // INSERT only: the trigger that announces a release fires on insert
          // too, and re-checking on every title correction would be noise.
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'app_releases',
          callback: (_) async => available.value = await checkForUpdate(),
        )
        .subscribe();
  }

  static Future<void> stop() async {
    await _sub?.unsubscribe();
    _sub = null;
    available.value = null;
  }

  /// The release part of a version, with any `+build` suffix removed.
  ///
  /// `app_releases.version` has repeatedly been written WITH the build number
  /// (`2.3.2+21`, `2.1.0+17`, and four more rows like it are in the table right
  /// now), and every one of those is a broken update:
  ///
  ///   * the download URL became `.../v2.3.2+21/AFOS-v2.3.2+21.apk`, which is a
  ///     404 — the git tag and the asset are named `v2.3.2` / `AFOS-v2.3.2.apk`.
  ///   * [_isNewer] split it on '.', so the last segment was the string
  ///     `'2+21'`, `int.tryParse` returned null, and it counted as 0 — i.e.
  ///     `2.3.2+21` compared as **2.3.0**, older than the release it describes.
  ///
  /// There is a CHECK constraint on the column now, but normalising here as
  /// well is what makes the six rows already in the table work.
  static String releasePart(String version) => version.split('+').first.trim();

  /// The build number after `+`, or null when the version does not carry one.
  static int? buildPart(String version) {
    final i = version.indexOf('+');
    if (i < 0) return null;
    return int.tryParse(version.substring(i + 1).trim());
  }

  /// The Android ABI slice this device can install, or null when unknown.
  ///
  /// WHY THIS EXISTS. CI publishes four assets per release: three per-ABI
  /// slices and one universal APK carrying all of them. This method asked for
  /// the universal one every time — **96 MB**, against 35 MB for the arm64
  /// slice the overwhelming majority of phones actually need.
  ///
  /// That is what the reported failure was. Dio surfaced it as
  /// `HttpConnection closed while receiving data`, which reads like a server
  /// fault and is not one: a 96 MB transfer over campus mobile data simply does
  /// not survive, and because the download has no resume, every retry started
  /// the whole 96 MB again from zero.
  ///
  /// Read out of `Platform.version` — which ends with `on "android_arm64"` —
  /// rather than by adding device_info_plus. A new native dependency would
  /// need a real Android build to verify and would buy exactly one string that
  /// the process already knows.
  static String? androidAbiSlice() {
    if (kIsWeb || !Platform.isAndroid) return null;
    return abiSliceFrom(Platform.version);
  }

  /// The pure half of [androidAbiSlice], split out so it can be tested.
  ///
  /// `Platform.version` is a process-wide value a widget test cannot set, so
  /// leaving the string matching inside the platform check would have made the
  /// ordering rule below unpinnable — and the ordering rule is the entire
  /// subtlety here.
  @visibleForTesting
  static String? abiSliceFrom(String platformVersion) {
    // arm64 IS TESTED FIRST, and must be: 'android_arm64' CONTAINS
    // 'android_arm', so the narrower test has to lose the race. Reversed, every
    // 64-bit phone in the university would be handed the 32-bit slice, which
    // installs and then behaves like a different app.
    if (platformVersion.contains('android_arm64')) return 'arm64-v8a';
    if (platformVersion.contains('android_x64')) return 'x86_64';
    if (platformVersion.contains('android_arm')) return 'armeabi-v7a';
    return null; // ia32 and anything unrecognised fall back to universal
  }

  static String _assetUrl(String v, String file) =>
      'https://github.com/$_owner/$_repo/releases/download/v$v/$file';

  /// The asset to try FIRST — the small one, when the ABI is known.
  static String _apkUrlFor(String version) {
    final v = releasePart(version);
    final abi = androidAbiSlice();
    return _assetUrl(v, abi == null ? 'AFOS-v$v.apk' : 'AFOS-v$v-$abi.apk');
  }

  /// The universal APK. Every device can install it, so it is the fallback
  /// when the per-ABI asset is missing — a release published before CI started
  /// splitting per ABI has only this one.
  static String universalApkUrlFor(String version) =>
      _assetUrl(releasePart(version), 'AFOS-v${releasePart(version)}.apk');

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
      if (latest == null || !isNewer(latest, AppConfig.appVersion)) return null;
      return AppUpdateInfo(
        version: latest,
        title: row?['title'] as String? ?? 'AFOS $latest',
        highlights: (row?['highlights'] as List?)?.cast<String>() ?? const [],
        downloadUrl: _apkUrlFor(latest),
        fallbackUrl: _apkUrlFor(latest) == universalApkUrlFor(latest)
            ? null
            : universalApkUrlFor(latest),
      );
    } catch (_) {
      return null;
    }
  }

  /// Numeric, per-segment comparison ("2.3.9" < "2.3.10") — a plain string
  /// compare would get this backwards on the last segment once either
  /// version reaches double digits there.
  ///
  /// Both sides are normalised through [releasePart] first, so a stored
  /// `2.3.2+21` is compared as `2.3.2` rather than silently degrading to
  /// `2.3.0`. When the release parts are equal the build numbers decide, which
  /// is what lets a rebuild of the same version (2.7.5+61 → 2.7.5+62) be
  /// offered at all; without it the two are indistinguishable.
  static bool isNewer(String remote, String local) {
    final r = releasePart(remote).split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final l = releasePart(local).split('.').map((p) => int.tryParse(p) ?? 0).toList();
    for (var i = 0; i < 3; i++) {
      final rv = i < r.length ? r[i] : 0;
      final lv = i < l.length ? l[i] : 0;
      if (rv != lv) return rv > lv;
    }
    final rb = buildPart(remote), lb = buildPart(local);
    if (rb != null && lb != null) return rb > lb;
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

  /// Smallest thing that could plausibly be this app.
  ///
  /// A 404 page, a captive-portal login, or a proxy error page is a few KB and
  /// arrives with HTTP 200 from the client's point of view. Handing one to the
  /// package installer named `.apk` is exactly what produces "There was a
  /// problem parsing the package" — the installer is telling the truth, it just
  /// is not an APK. The real artifact is ~95-200 MB.
  static const _minPlausibleApkBytes = 2 * 1024 * 1024;

  /// Every APK is a ZIP, and every ZIP starts with these four bytes.
  static const _zipMagic = [0x50, 0x4B, 0x03, 0x04]; // "PK\x03\x04"

  /// Reads the first four bytes and confirms they are a ZIP local-file header.
  static Future<bool> _looksLikeApk(File f) async {
    final raf = await f.open();
    try {
      final head = await raf.read(4);
      if (head.length < 4) return false;
      for (var i = 0; i < 4; i++) {
        if (head[i] != _zipMagic[i]) return false;
      }
      return true;
    } finally {
      await raf.close();
    }
  }

  /// Downloads the APK for [update] with progress (0.0–1.0 via [onProgress])
  /// and opens Android's package installer on it. Throws with a message meant
  /// for the user on any failure — a silent one here reads as "tap Update,
  /// nothing happens", which is how this looked for a long time.
  ///
  /// WHAT WAS WRONG. The file was streamed straight to its final name and
  /// opened without a single check, so anything that was not the APK still
  /// reached the installer:
  ///
  ///   * a short read (connection dropped, device slept) left a TRUNCATED file
  ///     that stayed on disk under the name the next attempt reuses;
  ///   * a 200 response that is not the artifact (proxy/captive portal) was
  ///     written verbatim;
  ///   * `OpenFile.open`'s result was discarded, so when Android refused —
  ///     "Install unknown apps" not granted for AFOS is the usual reason —
  ///     absolutely nothing was reported.
  ///
  /// Now it downloads to `.part`, proves the bytes are an APK, and only then
  /// renames into place, so the installer never sees a half-written file and a
  /// failed attempt cannot poison the next one.
  static Future<void> downloadAndInstall(
    AppUpdateInfo update, {
    void Function(double progress)? onProgress,
  }) async {
    await _cleanupOldDownloads(keep: update.version);
    final path = await _apkPath(update.version);
    final part = File('$path.part');

    try {
      // Only the scratch file is cleared up front. The final path is never
      // touched until there is a verified replacement to rename over it: the
      // user may have tapped Update, been handed to the installer, come back
      // and tapped again, and deleting the file the installer is still reading
      // would break the install that was already working.
      if (await part.exists()) await part.delete();

      // The small per-ABI slice first, the universal APK second.
      //
      // A 404 on the first is entirely expected for any release published
      // before CI began splitting per ABI, and must not reach the user as a
      // failed update. The part file is cleared between attempts so a partial
      // first download cannot be mistaken for the second one's bytes.
      //
      // The response type is deliberately never named: dio and
      // supabase_flutter both export `Headers`, and the same collision risk
      // applies to `Response`. Only the one header value is lifted out.
      final candidates = <String>[
        update.downloadUrl,
        if (update.fallbackUrl != null) update.fallbackUrl!,
      ];

      int? expected;
      var fetched = false;
      Object? lastError;
      for (final url in candidates) {
        try {
          final r = await Dio().download(
            url,
            part.path,
            onReceiveProgress: (received, total) {
              if (total > 0 && onProgress != null) onProgress(received / total);
            },
          );
          // Dio lower-cases response header names.
          expected = int.tryParse(r.headers.value('content-length') ?? '');
          fetched = true;
          break;
        } catch (e) {
          lastError = e;
          if (await part.exists()) await part.delete();
        }
      }
      if (!fetched) {
        throw Exception(
            'The update could not be downloaded. Check your connection and '
            'try again. ($lastError)');
      }

      // Length next: this is the check that catches a truncated transfer,
      // which is otherwise indistinguishable from success.
      final actual = await part.length();
      if (expected != null && expected > 0 && actual != expected) {
        throw Exception(
            'The download stopped early (${actual ~/ 1024} KB of '
            '${expected ~/ 1024} KB). Check your connection and try again.');
      }
      if (actual < _minPlausibleApkBytes || !await _looksLikeApk(part)) {
        throw Exception(
            'That download was not a valid app file. The release for '
            'v${releasePart(update.version)} may not have finished publishing '
            'yet — try again in a few minutes.');
      }

      await part.rename(path);

      final result = await OpenFile.open(
        path,
        // Named explicitly rather than inferred from the extension, so the
        // package installer is the resolved target and not a file manager.
        type: 'application/vnd.android.package-archive',
      );
      if (result.type != ResultType.done) {
        throw Exception(_installerMessage(result));
      }
    } catch (_) {
      // Never leave the partial behind: it is the input to the next attempt,
      // and a bad one there fails identically for a reason the user cannot
      // see. `target` is deliberately NOT deleted — nothing reaches that path
      // except through the verified rename above, so whatever is there is a
      // good APK, possibly one an installer is reading right now.
      try { if (await part.exists()) await part.delete(); } catch (_) {}
      rethrow;
    }
  }

  /// Turns an installer refusal into something the user can act on.
  ///
  /// [ResultType.permissionDenied] is by far the most common and the least
  /// self-explanatory: Android requires "Install unknown apps" to be granted to
  /// AFOS specifically before it will let the app hand it a package, and the
  /// refusal is silent from the app's side.
  static String _installerMessage(OpenResult result) => switch (result.type) {
        ResultType.permissionDenied =>
          'Android blocked the install. Allow AFOS to install apps: Settings → '
              'Apps → AFOS → Install unknown apps → turn it on, then tap Update '
              'again.',
        ResultType.noAppToOpen =>
          'No package installer is available on this device to complete the '
              'update.',
        ResultType.fileNotFound =>
          'The downloaded update went missing before it could be installed — '
              'please try again.',
        _ => 'The update could not be installed: ${result.message}',
      };
}
