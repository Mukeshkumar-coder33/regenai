import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/auth/data/user_model.dart';

/// Secure Session Storage
///
/// Persists JWT token and serialized user session locally.
/// Avoids storing plaintext passwords or sensitive credentials.
class SessionStorage {
  static const String _tokenKey = 'regen_jwt_token';
  static const String _userSessionKey = 'regen_user_session';

  /// Saves the authenticated user and token
  static Future<void> saveSession(UserModel user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, user.token);
    await prefs.setString(_userSessionKey, jsonEncode(user.toJson()));
  }

  /// Retrieves the active user session if exists
  static Future<UserModel?> getUserSession() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_userSessionKey);
    if (jsonStr == null || jsonStr.isEmpty) return null;

    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return UserModel.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  /// Retrieves only the JWT token for network headers
  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  /// Clears stored credentials on logout
  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userSessionKey);
  }
}

