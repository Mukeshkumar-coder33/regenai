import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../app/app_config.dart';
import '../../features/auth/data/user_model.dart';

/// Secure Session Storage
///
/// Persists JWT token, serialized user session, and issuing server URL locally.
/// Avoids storing plaintext passwords or sensitive credentials.
class SessionStorage {
  static const String _tokenKey = 'regen_jwt_token';
  static const String _userSessionKey = 'regen_user_session';
  static const String _sessionServerKey = 'regen_session_server_url';

  /// Saves the authenticated user, token, and the backend server URL that issued it.
  static Future<void> saveSession(UserModel user, {String? serverUrl}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, user.token);
    await prefs.setString(_userSessionKey, jsonEncode(user.toJson()));
    final normalizedServer = AppConfig.normalizeServerUrl(serverUrl ?? AppConfig.activeBaseUrl);
    await prefs.setString(_sessionServerKey, normalizedServer);
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

  /// Retrieves the backend server URL associated with the saved session.
  static Future<String?> getSessionServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_sessionServerKey);
  }

  /// Returns false when the saved session was issued by a different backend server
  /// than [AppConfig.activeBaseUrl] (e.g., switching Local Wi-Fi <-> Public Server).
  static Future<bool> isSessionValidForCurrentServer() async {
    final savedUrl = await getSessionServerUrl();
    if (savedUrl == null || savedUrl.trim().isEmpty) return true;
    return AppConfig.normalizeServerUrl(savedUrl) == AppConfig.activeBaseUrl;
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
    await prefs.remove(_sessionServerKey);
  }
}

