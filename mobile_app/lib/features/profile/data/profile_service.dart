import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../../app/app_config.dart';
import '../../../core/storage/session_storage.dart';
import '../../auth/data/user_model.dart';

/// Profile Management API Service
///
/// Handles updating employee personal details (Name, Phone, Email, Avatar)
/// and fetching current profile data from the ReGen backend (`/api/users`).
class ProfileService {
  final http.Client _client;

  ProfileService({http.Client? client}) : _client = client ?? http.Client();

  /// Fetch full fresh profile from backend
  Future<UserModel> fetchUserProfile(String userId, String token) async {
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/users/me');
    try {
      final response = await _client.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final updatedUser = UserModel.fromJson(body, fallbackToken: token);
        await SessionStorage.saveSession(updatedUser);
        return updatedUser;
      }
      return await _fetchUserById(userId, token);
    } catch (_) {
      return await _fetchUserById(userId, token);
    }
  }

  Future<UserModel> _fetchUserById(String userId, String token) async {
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/users/$userId');
    try {
      final response = await _client.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final updatedUser = UserModel.fromJson(body, fallbackToken: token);
        await SessionStorage.saveSession(updatedUser);
        return updatedUser;
      }
    } catch (_) {}

    final cached = await SessionStorage.getUserSession();
    if (cached != null) return cached;
    throw Exception('Unable to load employee profile');
  }

  /// Update authorized employee personal details (Name, Phone, Email, Avatar)
  Future<UserModel> updatePersonalDetails({
    required String userId,
    required String token,
    required String name,
    String? phone,
    String? email,
    String? avatarBase64,
  }) async {
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/users/$userId');

    final Map<String, dynamic> payload = {
      'name': name.trim(),
    };
    if (phone != null && phone.trim().isNotEmpty) {
      payload['phone'] = phone.trim();
    }
    if (email != null && email.trim().isNotEmpty) {
      payload['email'] = email.trim();
    }
    if (avatarBase64 != null && avatarBase64.isNotEmpty) {
      payload['avatar'] = avatarBase64;
    }

    try {
      final response = await _client.put(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 14));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final updatedUser = UserModel.fromJson(body, fallbackToken: token);
        await SessionStorage.saveSession(updatedUser);
        return updatedUser;
      }

      final errorBody = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(errorBody['message'] ?? 'Failed to update profile (${response.statusCode})');
    } on SocketException {
      throw Exception('Cannot reach ReGen server at ${AppConfig.activeBaseUrl}. Please check backend connection.');
    }
  }
}

