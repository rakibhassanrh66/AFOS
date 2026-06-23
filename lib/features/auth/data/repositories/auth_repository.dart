import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../config/supabase_config.dart';
import '../../../../shared/models/user_model.dart';

class AuthRepository {
  final _client = SupabaseConfig.client;

  Future<UserModel> signIn(String email, String password) async {
    final res = await _client.auth.signInWithPassword(email:email, password:password);
    if(res.user==null) throw Exception('Sign in failed');
    
    // Fetch profile, role, and potential student/teacher extensions
    final profile = await _client.from('profiles')
        .select('*, roles(name), students(*), teachers(*)')
        .eq('id', res.user!.id)
        .single();
        
    return UserModel.fromJson(profile);
  }

  Future<void> signUp({required String email, required String password}) async {
    final res = await _client.auth.signUp(email:email, password:password);
    if(res.user==null) throw Exception('Sign up failed');
    // Trigger handles profile and role creation
  }

  Future<void> forgotPassword(String email) async {
    await _client.auth.resetPasswordForEmail(email);
  }

  Future<void> signOut() async => await _client.auth.signOut();

  Future<UserModel?> getCurrentUser() async {
    final user = _client.auth.currentUser;
    if(user==null) return null;
    final profile = await _client.from('profiles').select().eq('id',user.id).maybeSingle();
    if(profile==null) return null;
    return UserModel.fromJson(profile);
  }
}
