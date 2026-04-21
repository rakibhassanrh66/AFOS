import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';

class AuthService {
  static const String _emailKey = 'user_email';
  static const String _passwordKey = 'user_password';
  static const String _roleKey = 'user_role';
  static const String _nameKey = 'user_name';

  Future<UserModel?> signIn(String email, String password) async {
    final prefs = await SharedPreferences.getInstance();
    final storedEmail = prefs.getString(_emailKey);
    final storedPassword = prefs.getString(_passwordKey);

    if (storedEmail == email && storedPassword == password) {
      return UserModel(
        id: email.hashCode.toString(),
        email: email,
        name: prefs.getString(_nameKey) ?? 'User',
        role: prefs.getString(_roleKey) ?? 'user',
      );
    }
    throw Exception('Invalid email or password');
  }

  Future<UserModel?> signUp(String email, String password, String name, String role) async {
    final prefs = await SharedPreferences.getInstance();
    final existingEmail = prefs.getString(_emailKey);

    if (existingEmail == email) {
      throw Exception('Email already exists');
    }

    await prefs.setString(_emailKey, email);
    await prefs.setString(_passwordKey, password);
    await prefs.setString(_nameKey, name);
    await prefs.setString(_roleKey, role);

    return UserModel(
      id: email.hashCode.toString(),
      email: email,
      name: name,
      role: role,
    );
  }

  Future<UserModel?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString(_emailKey);
    final password = prefs.getString(_passwordKey);

    if (email != null && password != null) {
      return UserModel(
        id: email.hashCode.toString(),
        email: email,
        name: prefs.getString(_nameKey) ?? 'User',
        role: prefs.getString(_roleKey) ?? 'user',
      );
    }
    return null;
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_emailKey);
    await prefs.remove(_passwordKey);
    await prefs.remove(_nameKey);
    await prefs.remove(_roleKey);
  }
}
