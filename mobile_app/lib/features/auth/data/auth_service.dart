import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../../app/app_config.dart';
import '../../../core/storage/session_storage.dart';
import 'user_model.dart';

/// Custom Exception for Authentication Failures
class AuthException implements Exception {
  final String message;
  final String? code;
  final int? statusCode;

  const AuthException({
    required this.message,
    this.code,
    this.statusCode,
  });

  @override
  String toString() => message;
}

/// Authentication Service
///
/// Communicates with ReGen Express backend at `POST /api/auth/login`.
/// Handles PostgreSQL dual authentication (port 3004) via backend,
/// error decoding, and secure token persistence.
class AuthService {
  final http.Client _client;

  AuthService({http.Client? client}) : _client = client ?? http.Client();

  /// Authenticate against backend
  Future<UserModel> login({
    required String username,
    required String password,
    String portal = 'company',
  }) async {
    final cleanId = username.trim();
    final cleanPassword = password;

    if (cleanId.isEmpty || cleanPassword.isEmpty) {
      throw const AuthException(
        message: 'Username and password are required',
        statusCode: 400,
      );
    }

    final url = Uri.parse(AppConfig.loginUrl);
    final payload = jsonEncode({
      'identifier': cleanId,
      'password': cleanPassword,
      'portal': portal,
    });

    try {
      final response = await _client.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'x-portal-view': portal,
        },
        body: payload,
      ).timeout(const Duration(seconds: 12));

      final Map<String, dynamic> body;
      try {
        body = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        throw AuthException(
          message: 'Invalid server response (${response.statusCode})',
          statusCode: response.statusCode,
        );
      }

      // Handle successful authentication
      if (response.statusCode == 200) {
        final user = UserModel.fromJson(body);
        // Persist session locally
        await SessionStorage.saveSession(user);
        return user;
      }

      // Handle server error responses (400, 401, 403, 503, etc.)
      final errorMessage = body['message']?.toString() ?? 'Authentication failed';
      final errorCode = body['code']?.toString();

      throw AuthException(
        message: errorMessage,
        code: errorCode,
        statusCode: response.statusCode,
      );
    } on SocketException {
      throw AuthException(
        message: 'Cannot reach ReGen server at ${AppConfig.activeBaseUrl}. Make sure the Node.js backend is running on port ${AppConfig.backendPort}.',
        statusCode: 0,
      );
    } on http.ClientException {
      throw AuthException(
        message: 'Network connection error. Check server status at ${AppConfig.activeBaseUrl}.',
        statusCode: 0,
      );
    } on FormatException {
      throw const AuthException(
        message: 'Malformed response received from backend.',
        statusCode: 500,
      );
    }
  }

  /// Mock login for UI testing without live backend
  Future<UserModel> mockLogin({
    required String username,
    required String password,
    String role = 'staff',
  }) async {
    await Future.delayed(const Duration(milliseconds: 600));

    if (password.length < 3) {
      throw const AuthException(
        message: 'Invalid credentials. Password too short.',
        statusCode: 401,
      );
    }

    final user = UserModel(
      id: 'mock_123',
      userId: username.toUpperCase(),
      username: username,
      name: username.replaceRange(0, 1, username[0].toUpperCase()),
      role: role,
      company: 'krish Tech Computer',
      companyId: 'comp_123',
      token: 'mock_jwt_token_for_testing',
      authSource: 'mock:test',
    );

    await SessionStorage.saveSession(user);
    return user;
  }

  /// Switch from Super Admin to EMS Company Owner mode
  Future<UserModel> switchToEms() async {
    final token = await SessionStorage.getToken();
    if (token == null || token.isEmpty) {
      throw const AuthException(message: 'Authentication token not found');
    }

    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/auth/switch-to-ems');
    try {
      final response = await _client.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final user = UserModel.fromJson(body);
        await SessionStorage.saveSession(user);
        return user;
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw AuthException(
        message: body['message']?.toString() ?? 'Failed to switch to EMS mode',
        statusCode: response.statusCode,
      );
    } on SocketException {
      throw AuthException(
        message: 'Cannot reach ReGen server at ${AppConfig.activeBaseUrl}',
        statusCode: 0,
      );
    }
  }

  /// Switch from Company Owner back to Super Admin console
  Future<UserModel> switchToSuperAdmin() async {
    final token = await SessionStorage.getToken();
    if (token == null || token.isEmpty) {
      throw const AuthException(message: 'Authentication token not found');
    }

    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/auth/switch-to-superadmin');
    try {
      final response = await _client.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final user = UserModel.fromJson(body);
        await SessionStorage.saveSession(user);
        return user;
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw AuthException(
        message: body['message']?.toString() ?? 'Failed to switch to Super Admin mode',
        statusCode: response.statusCode,
      );
    } on SocketException {
      throw AuthException(
        message: 'Cannot reach ReGen server at ${AppConfig.activeBaseUrl}',
        statusCode: 0,
      );
    }
  }
}

