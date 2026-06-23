import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/supabase_config.dart';
import '../utils/logger.dart';

class SupabaseService {
  static final SupabaseClient _client = SupabaseConfig.client;

  static Future<List<Map<String,dynamic>>> fetchAll(String table, {
    String? orderBy, bool ascending = false, int? limit,
    String? eqColumn, dynamic eqValue,
  }) async {
    try {
      dynamic q = _client.from(table).select();
      if (eqColumn != null) q = q.eq(eqColumn, eqValue);
      if (orderBy != null) q = q.order(orderBy, ascending: ascending);
      if (limit != null) q = q.limit(limit);
      final result = await q;
      return (result as List).cast<Map<String,dynamic>>();
    } catch (e) {
      AppLogger.e('fetchAll $table', error: e);
      rethrow;
    }
  }

  static Future<Map<String,dynamic>?> fetchOne(String table, String id) async {
    try {
      final res = await _client.from(table).select().eq('id', id).maybeSingle();
      return res;
    } catch (e) {
      AppLogger.e('fetchOne $table $id', error: e);
      rethrow;
    }
  }

  static Future<void> insert(String table, Map<String,dynamic> data) async {
    try {
      await _client.from(table).insert(data);
    } catch (e) {
      AppLogger.e('insert $table', error: e);
      rethrow;
    }
  }

  static Future<void> update(String table, String id, Map<String,dynamic> data) async {
    try {
      await _client.from(table).update(data).eq('id', id);
    } catch (e) {
      AppLogger.e('update $table $id', error: e);
      rethrow;
    }
  }

  static Future<void> delete(String table, String id) async {
    try {
      await _client.from(table).delete().eq('id', id);
    } catch (e) {
      AppLogger.e('delete $table $id', error: e);
      rethrow;
    }
  }

  /// Stream all rows from a table, filter client-side.
  static Stream<List<Map<String,dynamic>>> stream(String table, {
    String orderBy = 'created_at',
    String? eqColumn, dynamic eqValue,
  }) {
    return _client
        .from(table)
        .stream(primaryKey: ['id'])
        .order(orderBy, ascending: false)
        .map((list) {
          final rows = list.cast<Map<String,dynamic>>();
          if (eqColumn != null) {
            return rows.where((r) => r[eqColumn] == eqValue).toList();
          }
          return rows;
        });
  }
}
