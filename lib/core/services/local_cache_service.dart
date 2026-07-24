import 'package:hive_flutter/hive_flutter.dart';

/// Generic read-cache: last-fetched JSON for a given screen/query, keyed by
/// a caller-chosen string (e.g. `schedule_slots_CSE`). Supabase rows are
/// already plain JSON-compatible Map/List, so Hive stores them natively with
/// no TypeAdapter. One box shared by every repository that opts in, rather
/// than a bespoke cache per feature.
class LocalCacheService {
  LocalCacheService._();
  static final LocalCacheService instance = LocalCacheService._();

  static const boxName = 'offline_cache';
  Box get _box => Hive.box(boxName);

  Future<void> putList(String key, List<Map<String, dynamic>> data) => _box.put(key, {
    'data': data,
    'cachedAt': DateTime.now().toIso8601String(),
  });

  ({List<Map<String, dynamic>> data, DateTime cachedAt})? getList(String key) {
    final raw = _box.get(key);
    if (raw == null) return null;
    final map = Map<String, dynamic>.from(raw as Map);
    final data = (map['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return (data: data, cachedAt: DateTime.parse(map['cachedAt'] as String));
  }

  Future<void> putMap(String key, Map<String, dynamic> data) => _box.put(key, {
    'data': data,
    'cachedAt': DateTime.now().toIso8601String(),
  });

  ({Map<String, dynamic> data, DateTime cachedAt})? getMap(String key) {
    final raw = _box.get(key);
    if (raw == null) return null;
    final map = Map<String, dynamic>.from(raw as Map);
    return (data: Map<String, dynamic>.from(map['data'] as Map), cachedAt: DateTime.parse(map['cachedAt'] as String));
  }

  static const _versionMarkerKey = '__app_version_marker__';

  /// Wipes this read-cache on the first launch after an app update — a
  /// version bump can change what shape of data a cached response is
  /// expected to have (new/renamed/removed fields), so a stale cached blob
  /// from before the update could otherwise fail to parse or silently show
  /// outdated data until it happens to refresh. Called once at bootstrap,
  /// right after this box opens.
  ///
  /// Deliberately scoped to ONLY this disposable, network-regenerable
  /// cache: never touches `OutboxService`'s box (a user's not-yet-synced
  /// offline writes would be lost) or `flutter_secure_storage` (login
  /// session / biometric quick-login) — an update must never force anyone
  /// to lose pending work or get signed out.
  Future<void> clearIfVersionChanged(String currentVersion) async {
    final lastVersion = _box.get(_versionMarkerKey) as String?;
    if (lastVersion != currentVersion) {
      final keys = _box.keys.where((k) => k != _versionMarkerKey).toList();
      await _box.deleteAll(keys);
      await _box.put(_versionMarkerKey, currentVersion);
    }
  }
}
