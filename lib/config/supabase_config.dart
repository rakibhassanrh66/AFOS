import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  SupabaseConfig._();
  static const String url = 'https://dtsptjallznnvattadlu.supabase.co';
  static const String anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'
      '.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR0c3B0amFsbHpubnZhdHRhZGx1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzYxOTUzMzUsImV4cCI6MjA5MTc3MTMzNX0'
      '.keNghrC4C3wIDWlquCo00YjR024Mjbd1Bbwt3r73q0o';
  static SupabaseClient get client => Supabase.instance.client;
  static String? get uid => client.auth.currentUser?.id;
  static String? get jwt => client.auth.currentSession?.accessToken;
}
