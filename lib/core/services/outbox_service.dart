import 'package:hive_flutter/hive_flutter.dart';
import '../utils/error_formatter.dart';
import 'connectivity_service.dart';

typedef OutboxHandler = Future<void> Function(Map<String, dynamic> payload);

/// Generic write-outbox: one PendingAction shape (type, payload, status)
/// covers hall-application/feedback/mentorship-booking/club-join/CR-request
/// submissions rather than five bespoke queues. A submit call tries the real
/// Supabase call immediately when online; if that fails for a connectivity
/// reason (or the device is already offline), it's enqueued here and replayed
/// automatically once connectivity returns. A genuine app-level error
/// (validation, RLS, a real constraint violation) is rethrown immediately
/// instead of being queued to fail identically later.
class OutboxService {
  OutboxService._();
  static final OutboxService instance = OutboxService._();

  static const boxName = 'outbox';
  Box get _box => Hive.box(boxName);

  final Map<String, OutboxHandler> _handlers = {};

  void registerHandler(String type, OutboxHandler handler) => _handlers[type] = handler;

  List<Map<String, dynamic>> get pending => _box.keys.map((k) {
    final row = Map<String, dynamic>.from(_box.get(k) as Map);
    return {...row, 'key': k};
  }).toList()
    ..sort((a, b) => (a['createdAt'] as String).compareTo(b['createdAt'] as String));

  Future<String> enqueue(String type, Map<String, dynamic> payload) async {
    final key = '${DateTime.now().microsecondsSinceEpoch}_$type';
    await _box.put(key, {
      'type': type,
      'payload': payload,
      'createdAt': DateTime.now().toIso8601String(),
      'status': 'pending',
      'lastError': null,
    });
    return key;
  }

  /// Returns true if the action was queued (offline or a connectivity-shaped
  /// failure) rather than sent immediately -- callers use this to show
  /// "saved, will send later" instead of a normal success message.
  Future<bool> submitOrQueue(String type, Map<String, dynamic> payload) async {
    if (!ConnectivityService.instance.isOnline.value) {
      await enqueue(type, payload);
      return true;
    }
    final handler = _handlers[type];
    if (handler == null) throw StateError('No outbox handler registered for "$type"');
    try {
      await handler(payload);
      return false;
    } catch (e) {
      if (isConnectivityError(e)) {
        await enqueue(type, payload);
        return true;
      }
      rethrow;
    }
  }

  Future<void> flush() async {
    if (!ConnectivityService.instance.isOnline.value) return;
    for (final key in _box.keys.toList()) {
      final raw = _box.get(key);
      if (raw == null) continue;
      final row = Map<String, dynamic>.from(raw as Map);
      if (row['status'] != 'pending') continue;
      final handler = _handlers[row['type'] as String];
      if (handler == null) continue;
      try {
        await handler(Map<String, dynamic>.from(row['payload'] as Map));
        await _box.delete(key);
      } catch (e) {
        if (isConnectivityError(e)) continue; // still flaky -- retry next flush
        await _box.put(key, {...row, 'status': 'failed', 'lastError': e.toString()});
      }
    }
  }

  Future<void> retry(String key) async {
    final raw = _box.get(key);
    if (raw == null) return;
    final row = Map<String, dynamic>.from(raw as Map);
    await _box.put(key, {...row, 'status': 'pending', 'lastError': null});
    await flush();
  }

  Future<void> discard(String key) => _box.delete(key);
}
