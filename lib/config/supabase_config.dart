import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  SupabaseConfig._();
  static const String url = 'https://dtsptjallznnvattadlu.supabase.co';
  static const String publishableKey = 'sb_publishable_x92WJ4FXzEVBTTY_9IKN5Q_0qK9qyuc';
  static SupabaseClient get client => Supabase.instance.client;
  static String? get uid => client.auth.currentUser?.id;
  static String? get jwt => client.auth.currentSession?.accessToken;
}
