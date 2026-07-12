import 'package:flutter/foundation.dart' show kIsWeb;
import '../../../../config/supabase_config.dart';
import '../../../../shared/models/user_model.dart';

class AuthRepository {
  final _client = SupabaseConfig.client;

  Future<UserModel> signIn(String email, String password) async {
    final res = await _client.auth.signInWithPassword(email:email, password:password);
    if(res.user==null) throw Exception('Sign in failed');
    
    // Fetch profile, role, and potential student/teacher extensions
    final profile = await _client.from('profiles')
        .select('*, roles!role_id(name), students(*), teachers(*), staff(*)')
        .eq('id', res.user!.id)
        .single();
        
    return UserModel.fromJson(profile);
  }

  /// Returns the freshly-registered user if a session was issued immediately
  /// (accounts auto-confirm server-side), or null if email confirmation is
  /// still pending for some reason.
  Future<UserModel?> signUp({
    required String email,
    required String password,
    required String fullName,
    required String studentId,
    required String department,
    required int semester,
    required String accountType,
    required String gender,
    String? programId,
    String? batch,
    String? section,
    String? designation,
    String? staffCategory,
  }) async {
    final res = await _client.auth.signUp(
      email: email,
      password: password,
      data: {
        'full_name': fullName,
        'university_id': studentId,
        'department': department,
        'semester': semester,
        'account_type': accountType,
        'gender': gender,
        if(programId != null) 'program_id': programId,
        if(batch != null) 'batch': batch,
        if(section != null) 'section': section,
        if(designation != null) 'designation': designation,
        if(staffCategory != null) 'staff_category': staffCategory,
      },
    );
    if(res.user==null) throw Exception('Sign up failed');
    if(res.session==null) return null;

    final profile = await _client.from('profiles')
        .select('*, roles!role_id(name), students(*), teachers(*), staff(*)')
        .eq('id', res.user!.id)
        .single();
    return UserModel.fromJson(profile);
  }

  Future<void> forgotPassword(String email) async {
    // Without an explicit redirectTo, Supabase always sends the emailed
    // link to the configured web site_url -- correct for the web build,
    // but on Android/iOS that meant the link opened a mobile browser to
    // the web app instead of coming back into the native app the request
    // was actually made from. supabase_flutter already runs its own
    // app_links listener internally on native platforms and auto-detects
    // any incoming URI carrying access_token/code as an auth callback
    // (see SupabaseAuth._isAuthCallbackDeeplink), so no extra listener
    // code is needed here -- just pointing the link at this app's own
    // registered afos:// scheme (AndroidManifest.xml / Info.plist) is
    // enough for it to land back in the app and fire the same
    // AuthChangeEvent.passwordRecovery the web flow does.
    await _client.auth.resetPasswordForEmail(
      email,
      redirectTo: kIsWeb ? null : 'afos://reset-password',
    );
  }

  Future<void> signOut() async => await _client.auth.signOut();

  Future<UserModel?> getCurrentUser() async {
    final user = _client.auth.currentUser;
    if(user==null) return null;
    final profile = await _client.from('profiles')
        .select('*, roles!role_id(name), students(*), teachers(*), staff(*)')
        .eq('id', user.id)
        .maybeSingle();
    if(profile==null) return null;
    return UserModel.fromJson(profile);
  }
}
