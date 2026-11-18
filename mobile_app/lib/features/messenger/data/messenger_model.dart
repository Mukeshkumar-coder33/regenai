// Messenger Data Models mapping directly to ReGen MongoDB backend APIs:
// - `GET /api/messages` & `POST /api/messages` (Company Team Chat)
// - `GET /api/dm/conversations` & `GET /api/dm/conversations/:id/messages` (1:1 Direct Messages)

class TeamMessageModel {
  final String id;
  final String messageId;
  final String senderId;
  final String senderName;
  final String content;
  final String timestamp;
  final String? editedAt;

  const TeamMessageModel({
    required this.id,
    required this.messageId,
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.timestamp,
    this.editedAt,
  });

  factory TeamMessageModel.fromJson(Map<String, dynamic> json) {
    final msgId = (json['messageId'] ?? json['id'] ?? json['_id'] ?? '').toString();
    return TeamMessageModel(
      id: (json['_id'] ?? json['id'] ?? msgId).toString(),
      messageId: msgId,
      senderId: (json['senderId'] ?? '').toString(),
      senderName: (json['senderName'] ?? json['senderId'] ?? 'Team Member').toString(),
      content: (json['content'] ?? '').toString(),
      timestamp: (json['timestamp'] ?? json['createdAt'] ?? '').toString(),
      editedAt: json['editedAt']?.toString(),
    );
  }
}

class DmConversationModel {
  final String conversationId;
  final List<String> participants;
  final String otherUserId;
  final String otherUserName;
  final String otherUserRole;
  final String lastMessage;
  final String lastTimestamp;
  final int unreadCount;

  const DmConversationModel({
    required this.conversationId,
    required this.participants,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserRole = '',
    this.lastMessage = '',
    this.lastTimestamp = '',
    this.unreadCount = 0,
  });

  factory DmConversationModel.fromJson(
    Map<String, dynamic> json, {
    String currentUserId = '',
  }) {
    final convId = (json['conversationId'] ?? json['id'] ?? json['_id'] ?? '').toString();
    final rawParticipants = (json['participants'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList();

    final otherUser = json['otherUser'] is Map<String, dynamic>
        ? json['otherUser'] as Map<String, dynamic>
        : null;

    String otherId = (otherUser?['userId'] ?? otherUser?['id'] ?? '').toString();
    if (otherId.isEmpty) {
      otherId = rawParticipants.firstWhere(
        (p) => p != currentUserId,
        orElse: () => rawParticipants.isNotEmpty ? rawParticipants.first : '',
      );
    }

    final otherName = (otherUser?['name'] ??
            otherUser?['username'] ??
            json['otherUserName'] ??
            otherId)
        .toString();

    final lastMsgObj = json['lastMessage'];
    String lastText = '';
    String lastTs = (json['updatedAt'] ?? '').toString();
    if (lastMsgObj is Map<String, dynamic>) {
      lastText = (lastMsgObj['content'] ?? lastMsgObj['text'] ?? '').toString();
      lastTs = (lastMsgObj['timestamp'] ?? lastMsgObj['createdAt'] ?? lastTs).toString();
    } else if (lastMsgObj is String) {
      lastText = lastMsgObj;
    }

    return DmConversationModel(
      conversationId: convId,
      participants: rawParticipants,
      otherUserId: otherId,
      otherUserName: otherName.isNotEmpty ? otherName : 'Colleague',
      otherUserRole: (otherUser?['role'] ?? '').toString(),
      lastMessage: lastText,
      lastTimestamp: lastTs,
      unreadCount: (json['unreadCount'] is num) ? (json['unreadCount'] as num).toInt() : 0,
    );
  }
}

class DirectMessageModel {
  final String id;
  final String conversationId;
  final String senderId;
  final String senderName;
  final String content;
  final String timestamp;

  const DirectMessageModel({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.timestamp,
  });

  factory DirectMessageModel.fromJson(Map<String, dynamic> json) {
    return DirectMessageModel(
      id: (json['messageId'] ?? json['id'] ?? json['_id'] ?? '').toString(),
      conversationId: (json['conversationId'] ?? '').toString(),
      senderId: (json['senderId'] ?? '').toString(),
      senderName: (json['senderName'] ?? json['senderId'] ?? 'User').toString(),
      content: (json['content'] ?? json['ciphertext'] ?? '').toString(),
      timestamp: (json['timestamp'] ?? json['createdAt'] ?? '').toString(),
    );
  }
}
