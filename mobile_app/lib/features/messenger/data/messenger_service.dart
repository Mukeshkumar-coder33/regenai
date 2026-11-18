import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../app/app_config.dart';
import '../../../core/storage/session_storage.dart';
import '../../auth/data/user_model.dart';
import 'messenger_model.dart';

/// Live Messenger API Service reusing ReGen's existing `/api/messages`, `/api/dm`,
/// and `/api/notifications` endpoints with strict role-based scoping.
class MessengerService {
  final http.Client _client;

  MessengerService({http.Client? client}) : _client = client ?? http.Client();

  Future<Map<String, String>> _getHeaders({required UserModel user}) async {
    final storedToken = await SessionStorage.getToken();
    final token = user.token.isNotEmpty ? user.token : (storedToken ?? '');
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      'x-portal-view': user.isSuperAdmin ? 'superadmin' : 'ems',
    };
  }

  /// Fetch authorized Messenger contacts using ReGen's existing `/api/users` endpoint
  /// (zero 404s across all server versions) with strict role & company scoping:
  /// - Super Admin: active company owners/admins across the platform
  /// - Company Admin/Owner: own-company employees + platform Super Admin
  /// - Employee: own-company employees + own company owner/admin
  Future<List<MessengerContactModel>> getAuthorizedContacts({required UserModel user}) async {
    final headers = await _getHeaders(user: user);
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/users');
    final myId = (user.userId.isNotEmpty ? user.userId : user.id).trim().toLowerCase();
    final myCompanyId = (user.companyId ?? '').trim();

    try {
      final res = await _client.get(url, headers: headers).timeout(const Duration(seconds: 10));
      final contacts = <MessengerContactModel>[];

      if (res.statusCode == 200) {
        final raw = jsonDecode(res.body);
        if (raw is List) {
          for (final item in raw.whereType<Map<String, dynamic>>()) {
            final status = (item['status'] ?? 'active').toString().toLowerCase();
            if (status == 'inactive') continue;

            final c = MessengerContactModel.fromJson(item);
            final cid = c.userId.trim().toLowerCase();
            if (cid.isEmpty || cid == myId || c.id.trim().toLowerCase() == myId) continue;

            final role = c.role.toLowerCase();
            if (user.isSuperAdmin) {
              // Super Admin talks strictly to company owners & admins (never regular employees)
              if (role != 'owner' && role != 'admin') continue;
            } else {
              // Strict company isolation
              if (myCompanyId.isNotEmpty &&
                  c.companyId != null &&
                  c.companyId!.isNotEmpty &&
                  c.companyId != myCompanyId) {
                continue;
              }
            }
            contacts.add(c);
          }
        }
      }

      // Company Owners / Admins can also communicate with Platform Super Admin
      if (user.isCompanyAdmin && !user.isSuperAdmin && myId != 'vyshwa') {
        final hasSuperAdmin = contacts.any((c) => c.role.toLowerCase() == 'param');
        if (!hasSuperAdmin) {
          contacts.insert(
            0,
            const MessengerContactModel(
              id: 'Vyshwa',
              userId: 'Vyshwa',
              username: 'Vyshwa',
              name: 'Vyshwa',
              role: 'param',
              company: 'ReGen Central',
              designation: 'Platform Administrator',
              department: 'Central Administration',
              online: false,
            ),
          );
        }
      }

      return contacts;
    } catch (_) {
      return [];
    }
  }

  /// Fetch Team Chat messages (`GET /api/messages`)
  Future<List<TeamMessageModel>> getTeamMessages({required UserModel user}) async {
    final headers = await _getHeaders(user: user);
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/messages');
    try {
      final res = await _client.get(url, headers: headers).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List<dynamic>;
        return list
            .whereType<Map<String, dynamic>>()
            .map(TeamMessageModel.fromJson)
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Send a Team Chat text or voice message (`POST /api/messages`)
  Future<TeamMessageModel?> sendTeamMessage({
    required UserModel user,
    required String content,
    List<Map<String, dynamic>>? attachments,
  }) async {
    final headers = await _getHeaders(user: user);
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/messages');
    final msgId = 'msg-${DateTime.now().millisecondsSinceEpoch}';
    final senderId = user.userId.isNotEmpty ? user.userId : user.id;
    final senderName = user.name.isNotEmpty ? user.name : user.username;
    final body = jsonEncode({
      'messageId': msgId,
      'id': msgId,
      'senderId': senderId,
      'senderName': senderName,
      'content': content.trim(),
      'timestamp': DateTime.now().toIso8601String(),
      if (attachments != null && attachments.isNotEmpty) 'attachments': attachments,
      if (user.companyId != null && user.companyId!.isNotEmpty) 'companyId': user.companyId,
    });
    try {
      final res = await _client
          .post(url, headers: headers, body: body)
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return TeamMessageModel.fromJson(data);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Edit a Team Chat message (`PUT /api/messages/:id`)
  Future<TeamMessageModel?> editTeamMessage({
    required UserModel user,
    required String messageId,
    required String content,
  }) async {
    final headers = await _getHeaders(user: user);
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/messages/$messageId');
    try {
      final res = await _client
          .put(url, headers: headers, body: jsonEncode({'content': content.trim()}))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return TeamMessageModel.fromJson(data);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Delete a Team Chat message (`DELETE /api/messages/:id`)
  Future<bool> deleteTeamMessage({
    required UserModel user,
    required String messageId,
  }) async {
    final headers = await _getHeaders(user: user);
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/messages/$messageId');
    try {
      final res = await _client.delete(url, headers: headers).timeout(const Duration(seconds: 8));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Fetch my 1:1 and Group conversations (`GET /api/dm/conversations`)
  Future<List<DmConversationModel>> getConversations({required UserModel user}) async {
    final headers = await _getHeaders(user: user);
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/dm/conversations');
    final myId = user.userId.isNotEmpty ? user.userId : user.id;
    try {
      final res = await _client.get(url, headers: headers).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final raw = jsonDecode(res.body);
        final list = raw is List
            ? raw
            : (raw is Map && raw['conversations'] is List ? raw['conversations'] as List : []);
        return list
            .whereType<Map<String, dynamic>>()
            .map((item) => DmConversationModel.fromJson(item, currentUserId: myId))
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Start or get an existing 1:1 DM conversation (`POST /api/dm/conversations`)
  Future<DmConversationModel?> getOrCreateConversation({
    required UserModel user,
    required String recipientId,
  }) async {
    final headers = await _getHeaders(user: user);
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/dm/conversations');
    final myId = user.userId.isNotEmpty ? user.userId : user.id;
    try {
      final res = await _client
          .post(
            url,
            headers: headers,
            body: jsonEncode({'recipientId': recipientId}),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final convObj = data['conversation'] is Map<String, dynamic>
            ? data['conversation'] as Map<String, dynamic>
            : data;
        return DmConversationModel.fromJson(convObj, currentUserId: myId);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Create a new multi-user Group conversation (`POST /api/dm/groups`)
  Future<DmConversationModel?> createGroupConversation({
    required UserModel user,
    required String name,
    required List<String> participantIds,
  }) async {
    final headers = await _getHeaders(user: user);
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/dm/groups');
    final myId = user.userId.isNotEmpty ? user.userId : user.id;
    try {
      final res = await _client
          .post(
            url,
            headers: headers,
            body: jsonEncode({
              'name': name.trim(),
              'participantIds': participantIds,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return DmConversationModel.fromJson(data, currentUserId: myId);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Fetch messages in a 1:1 or Group conversation (`GET /api/dm/conversations/:id/messages`)
  Future<List<DirectMessageModel>> getDirectMessages({
    required UserModel user,
    required String conversationId,
  }) async {
    final headers = await _getHeaders(user: user);
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/dm/conversations/$conversationId/messages');
    try {
      final res = await _client.get(url, headers: headers).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final raw = jsonDecode(res.body);
        final list = raw is List
            ? raw
            : (raw is Map && raw['messages'] is List ? raw['messages'] as List : []);
        return list
            .whereType<Map<String, dynamic>>()
            .map(DirectMessageModel.fromJson)
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Send a Direct or Group message (text, E2E ciphertext, or voice attachment)
  /// (`POST /api/dm/conversations/:id/messages`)
  Future<DirectMessageModel?> sendDirectMessage({
    required UserModel user,
    required String conversationId,
    required String content,
    bool isVoice = false,
    bool encrypted = false,
    String iv = '',
    List<Map<String, dynamic>>? attachments,
  }) async {
    final headers = await _getHeaders(user: user);
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/dm/conversations/$conversationId/messages');
    final msgId = 'dm-${DateTime.now().millisecondsSinceEpoch}';
    final senderId = user.userId.isNotEmpty ? user.userId : user.id;
    final senderName = user.name.isNotEmpty ? user.name : user.username;
    try {
      final res = await _client
          .post(
            url,
            headers: headers,
            body: jsonEncode({
              'messageId': msgId,
              'id': msgId,
              'senderId': senderId,
              'senderName': senderName,
              'content': encrypted ? content : content.trim(),
              'encrypted': encrypted,
              if (iv.isNotEmpty) 'iv': iv,
              'isVoice': isVoice,
              if (attachments != null && attachments.isNotEmpty) 'attachments': attachments,
              'timestamp': DateTime.now().toIso8601String(),
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 200 || res.statusCode == 201) {
        final raw = jsonDecode(res.body) as Map<String, dynamic>;
        final msgObj = raw['message'] is Map<String, dynamic>
            ? raw['message'] as Map<String, dynamic>
            : raw;
        return DirectMessageModel.fromJson(msgObj);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Mark all messages in a conversation as read (`PUT /api/dm/conversations/:id/read`)
  Future<bool> markConversationRead({
    required UserModel user,
    required String conversationId,
  }) async {
    final headers = await _getHeaders(user: user);
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/dm/conversations/$conversationId/read');
    try {
      final res = await _client.put(url, headers: headers).timeout(const Duration(seconds: 8));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Store ECDH P-256 public key for E2E encryption (`POST /api/dm/conversations/:id/keys`)
  Future<bool> storePublicKey({
    required UserModel user,
    required String conversationId,
    required String publicKeyJwkJson,
  }) async {
    final headers = await _getHeaders(user: user);
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/dm/conversations/$conversationId/keys');
    try {
      final res = await _client
          .post(
            url,
            headers: headers,
            body: jsonEncode({'publicKey': publicKeyJwkJson}),
          )
          .timeout(const Duration(seconds: 8));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Edit a direct/group message (`PUT /api/dm/messages/:messageId`)
  Future<DirectMessageModel?> editDirectMessage({
    required UserModel user,
    required String messageId,
    required String content,
    bool encrypted = false,
    String iv = '',
  }) async {
    final headers = await _getHeaders(user: user);
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/dm/messages/$messageId');
    try {
      final res = await _client
          .put(
            url,
            headers: headers,
            body: jsonEncode({
              'content': encrypted ? content : content.trim(),
              'encrypted': encrypted,
              if (iv.isNotEmpty) 'iv': iv,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        return DirectMessageModel.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Delete a direct/group message (`DELETE /api/dm/messages/:messageId`)
  Future<bool> deleteDirectMessage({
    required UserModel user,
    required String messageId,
  }) async {
    final headers = await _getHeaders(user: user);
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/dm/messages/$messageId');
    try {
      final res = await _client.delete(url, headers: headers).timeout(const Duration(seconds: 8));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Register mobile push token (`POST /api/notifications/device-token`)
  Future<bool> registerDeviceToken({
    required UserModel user,
    required String token,
    String platform = 'android',
  }) async {
    final headers = await _getHeaders(user: user);
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/notifications/device-token');
    try {
      final res = await _client
          .post(
            url,
            headers: headers,
            body: jsonEncode({'token': token, 'platform': platform}),
          )
          .timeout(const Duration(seconds: 8));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Unregister mobile push token on logout (`DELETE /api/notifications/device-token`)
  Future<bool> unregisterDeviceToken({
    required UserModel user,
    required String token,
  }) async {
    final headers = await _getHeaders(user: user);
    final url = Uri.parse('${AppConfig.activeBaseUrl}/api/notifications/device-token');
    try {
      final res = await _client
          .delete(
            url,
            headers: headers,
            body: jsonEncode({'token': token}),
          )
          .timeout(const Duration(seconds: 8));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
