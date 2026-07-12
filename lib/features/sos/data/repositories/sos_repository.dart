import '../../../../config/supabase_config.dart';

/// Thin client wrapper around the SOS system's edge function + tables.
/// Recipient resolution itself lives server-side in trigger-sos-alert
/// (any authenticated user may call it for themselves, no role check) --
/// this repository never resolves recipients client-side.
class SosRepository {
  SosRepository._();

  static Future<Map<String, dynamic>> triggerAlert({
    required double latitude,
    required double longitude,
    String? message,
    String? voicePath,
  }) async {
    final res = await SupabaseConfig.client.functions.invoke('trigger-sos-alert', body: {
      'latitude': latitude,
      'longitude': longitude,
      if (message != null && message.trim().isNotEmpty) 'message': message.trim(),
      if (voicePath != null) 'voicePath': voicePath,
    });
    final data = res.data;
    if (data is Map && data['error'] != null) {
      throw Exception(data['error']);
    }
    return (data as Map).cast<String, dynamic>();
  }

  static Future<List<Map<String, dynamic>>> fetchMyAlerts() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) return const [];
    final res = await SupabaseConfig.client.from('sos_alerts')
        .select().eq('user_id', uid).order('created_at', ascending: false) as List;
    return res.cast();
  }

  static Future<List<Map<String, dynamic>>> fetchAllForAdmin() async {
    final res = await SupabaseConfig.client.from('sos_alerts')
        .select('*, profiles!user_id(full_name, phone, avatar_url, university_id, role, is_verified)')
        .order('created_at', ascending: false) as List;
    return res.cast();
  }

  static Future<Map<String, dynamic>?> fetchById(String id) async {
    return await SupabaseConfig.client.from('sos_alerts')
        .select('*, profiles!user_id(full_name, phone, avatar_url, university_id, role, is_verified, '
            'permanent_division, permanent_district, permanent_upazila)')
        .eq('id', id).maybeSingle();
  }

  static Future<void> resolve(String id, {required String status}) async {
    await SupabaseConfig.client.from('sos_alerts').update({
      'status': status,
      'resolved_by': SupabaseConfig.uid,
      'resolved_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
  }

  /// Active alerts within 5km of the caller's own last-known location --
  /// gated entirely by sos_alerts' nearby_select_sos_alerts RLS policy
  /// (live-verified), not client-side filtering. Anyone this query returns
  /// rows for is someone who could plausibly walk/drive over and help,
  /// regardless of whether they were an official trigger-sos-alert recipient.
  static Future<List<Map<String, dynamic>>> fetchNearbyActive() async {
    final res = await SupabaseConfig.client.from('sos_alerts')
        .select('*, profiles!user_id(full_name, avatar_url, role, is_verified)')
        .eq('status', 'active').order('created_at', ascending: false) as List;
    return res.cast<Map<String, dynamic>>();
  }

  /// "I'm on my way" -- registers the caller as responding to an alert they
  /// can see (RLS re-checks the alert is still active and visible to them).
  static Future<void> respond(String alertId) async {
    await SupabaseConfig.client.from('sos_responses').upsert({
      'alert_id': alertId,
      'responder_id': SupabaseConfig.uid,
    });
  }

  static Future<void> withdrawResponse(String alertId) async {
    final uid = SupabaseConfig.uid;
    if (uid == null) return;
    await SupabaseConfig.client.from('sos_responses').delete()
        .eq('alert_id', alertId).eq('responder_id', uid);
  }

  static Stream<List<Map<String, dynamic>>> watchResponses(String alertId) {
    return SupabaseConfig.client.from('sos_responses').stream(primaryKey: ['id'])
        .eq('alert_id', alertId).order('created_at').asBroadcastStream();
  }
}
