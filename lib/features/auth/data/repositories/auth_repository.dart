import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart' show SignOutScope, FunctionException;
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
    /// Free-text office/section for a staff member with no ACADEMIC
    /// department — "Registrar Office", "Accounts", "IT Support".
    /// handle_new_user() writes it to staff.office.
    String? office,
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
        if(office != null) 'office': office,
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

  // ---------------------------------------------------------------------
  // Mailbox-proof registration.
  //
  // signUp() above is NO LONGER the registration path. It called
  // auth.signUp, which created a real auth user immediately — and because
  // auto_confirm_email stamps email_confirmed_at on every insert, that
  // account was confirmed without anyone ever proving they own the mailbox.
  // Registration now goes: requestRegistration -> emailed code/link ->
  // verifyRegistration, and the auth user is created server-side only after
  // the proof comes back. signUp is left in place because HARD RULE 2
  // forbids changing an existing signature, and because the QA seeding
  // helpers still reference it.
  // ---------------------------------------------------------------------

  /// Unwraps an edge-function reply. Supabase surfaces a non-2xx either as a
  /// thrown FunctionException or as a normal response carrying `error` —
  /// depending on version and on whether the body parsed — so both are
  /// handled here rather than at four call sites.
  Map<String, dynamic> _unwrap(dynamic data, {String fallback = 'Something went wrong.'}) {
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      final err = map['error'];
      if (err is String && err.isNotEmpty) throw Exception(err);
      return map;
    }
    throw Exception(fallback);
  }

  Future<Map<String, dynamic>> _invoke(String fn, Map<String, dynamic> body) async {
    try {
      final res = await _client.functions.invoke(fn, body: body);
      return _unwrap(res.data);
    } on FunctionException catch (e) {
      // The useful message is inside the JSON body, not e.toString().
      final d = e.details;
      if (d is Map && d['error'] is String) throw Exception(d['error']);
      throw Exception('Could not reach the server. Check your connection and try again.');
    }
  }

  /// Stages the signup and sends the confirmation code. Returns how long the
  /// code lasts and when a resend is allowed, so the UI can run an honest
  /// countdown instead of guessing.
  Future<Map<String, dynamic>> requestRegistration({
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
    String? office,
  }) =>
      _invoke('register-request', {
        'email': email,
        'password': password,
        'fullName': fullName,
        'universityId': studentId,
        'department': department,
        'semester': semester,
        'accountType': accountType,
        'gender': gender,
        if (programId != null) 'programId': programId,
        if (batch != null) 'batch': batch,
        if (section != null) 'section': section,
        if (designation != null) 'designation': designation,
        if (staffCategory != null) 'staffCategory': staffCategory,
        if (office != null) 'office': office,
      });

  /// Redeems the 6-digit code. Creates the real account server-side.
  Future<Map<String, dynamic>> verifyRegistration({
    required String email,
    required String code,
  }) =>
      _invoke('register-verify', {'email': email, 'code': code});

  /// Redeems the emailed link. Same row, same rules — the token is only spent
  /// by this call, never by the link being fetched, which is what stops
  /// university mail scanners from burning it.
  Future<Map<String, dynamic>> verifyRegistrationToken(String token) =>
      _invoke('register-verify', {'token': token});

  /// Raises the staged signup for human review, for someone whose code never
  /// arrived at all.
  ///
  /// Before this the fallback queue could only be entered by FAILING at the
  /// code — expiring it, or burning all five attempts — which someone holding
  /// no code cannot do. They had no route forward and were invisible to every
  /// administrator. Creates no account and grants nothing; approval still
  /// belongs to register-admin-approve behind can_browse_users().
  Future<Map<String, dynamic>> requestManualApproval(String email) =>
      _invoke('register-review-request', {'email': email});

  Future<Map<String, dynamic>> requestPasswordResetCode(String email) =>
      _invoke('password-reset', {'action': 'request', 'email': email});

  Future<Map<String, dynamic>> confirmPasswordReset({
    String? email,
    String? code,
    String? token,
    required String newPassword,
  }) =>
      _invoke('password-reset', {
        'action': 'verify',
        if (token != null) 'token': token,
        if (email != null) 'email': email,
        if (code != null) 'code': code,
        'newPassword': newPassword,
      });

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

  /// Explicit user-initiated logout, so the refresh token is revoked
  /// server-side rather than just dropped from this device. Without
  /// [SignOutScope.global] the token stays valid until it expires on its own,
  /// which means "log out" didn't actually end the session for anyone holding
  /// a copy of it.
  ///
  /// Deliberately NOT used by the account switcher or the unlock screen's
  /// password fallback — see the comments at those two call sites.
  Future<void> signOut() async =>
      await _client.auth.signOut(scope: SignOutScope.global);

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
