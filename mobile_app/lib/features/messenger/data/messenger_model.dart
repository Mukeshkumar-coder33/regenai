import '../../../app/app_config.dart';

// Messenger Data Models mapping directly to ReGen MongoDB backend APIs:
// - `GET /api/messages` & `POST /api/messages` (Company Team Chat)
// - `GET /api/dm/contacts` (Server-authorized role-scoped contacts)
// - `GET /api/dm/conversations`, `POST /api/dm/conversations`, `POST /api/dm/groups`
// - `GET/POST /api/dm/conversations/:id/messages` (1:1 & Group Messages + Voice Attachments + E2E)

class MessageAttachmentModel {
  final String path;
  final String name;
  final String type;
  final int? size;
  final int? duration;
  final String? transcript;

  const MessageAttachmentModel({
    required this.path,
    required this.name,
    this.type = '',
    this.size,
    this.duration,
    this.transcript,
  });

  factory MessageAttachmentModel.fromDynamic(dynamic raw) {
    if (raw is String) {
      final cleaned = raw.trim();
      final name = cleaned.split('/').last;
      return MessageAttachmentModel(path: cleaned, name: name.isNotEmpty ? name : 'attachment');
    }
    if (raw is Map) {
      final path = (raw['path'] ?? raw['url'] ?? raw['data'] ?? '').toString();
      final name = (raw['name'] ?? (path.isNotEmpty ? path.split('/').last : 'attachment')).toString();
      final type = (raw['type'] ?? raw['mimetype'] ?? '').toString();
      final size = raw['size'] is num ? (raw['size'] as num).toInt() : null;
      final duration = raw['duration'] is num ? (raw['duration'] as num).toInt() : null;
      final transcript = raw['transcript']?.toString();
      return MessageAttachmentModel(
        path: path,
        name: name,
        type: type,
        size: size,
        duration: duration,
        transcript: transcript,
      );
    }
    return const MessageAttachmentModel(path: '', name: 'attachment');
  }

  bool get isVideo {
    final lowerType = type.toLowerCase();
    final lowerName = name.toLowerCase();
    final lowerPath = path.toLowerCase();
    if (lowerType.startsWith('video')) return true;
    if (lowerPath.startsWith('data:video')) return true;
    if (lowerName.contains('video') || lowerPath.contains('video')) return true;
    if (RegExp(r'\.(mp4|mov|mkv)$').hasMatch(lowerName) && !lowerName.contains('voice')) {
      return !lowerType.startsWith('audio');
    }
    return false;
  }

  bool get isAudio {
    if (isVideo) return false;
    final lowerType = type.toLowerCase();
    final lowerName = name.toLowerCase();
    final lowerPath = path.toLowerCase();
    if (lowerType.startsWith('audio')) return true;
    if (lowerPath.startsWith('data:audio')) return true;
    if (lowerName.contains('voice') || lowerPath.contains('voice')) return true;
    return RegExp(r'\.(wav|mp3|ogg|m4a|aac|webm)$').hasMatch(lowerName) ||
        RegExp(r'\.(wav|mp3|ogg|m4a|aac)$').hasMatch(lowerPath);
  }

  bool get isImage {
    final lowerType = type.toLowerCase();
    final lowerName = name.toLowerCase();
    final lowerPath = path.toLowerCase();
    if (lowerType.startsWith('image/')) return true;
    return RegExp(r'\.(png|jpe?g|gif|webp|svg)$').hasMatch(lowerName) ||
        RegExp(r'\.(png|jpe?g|gif|webp|svg)$').hasMatch(lowerPath);
  }

  String get resolvedUrl {
    if (path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://') || path.startsWith('data:')) {
      return path;
    }
    final normalized = path.startsWith('/') ? path : '/$path';
    return '${AppConfig.activeBaseUrl}$normalized';
  }
}

class MessengerContactModel {
  final String id;
  final String userId;
  final String username;
  final String name;
  final String role;
  final String? companyId;
  final String company;
  final String designation;
  final String department;
  final String avatar;
  final bool online;
  final String? lastActive;

  const MessengerContactModel({
    required this.id,
    required this.userId,
    required this.username,
    required this.name,
    required this.role,
    this.companyId,
    this.company = '',
    this.designation = '',
    this.department = '',
    this.avatar = '',
    this.online = false,
    this.lastActive,
  });

  String get displayName => name.isNotEmpty ? name : (username.isNotEmpty ? username : userId);

  String get roleLabel {
    switch (role.toLowerCase()) {
      case 'param':
        return 'Super Admin';
      case 'owner':
        return 'Company Owner';
      case 'admin':
        return 'Company Admin';
      case 'intern':
        return 'Intern';
      case 'staff':
        return 'Staff';
      default:
        return role.isNotEmpty ? role : 'Member';
    }
  }

  MessengerContactModel copyWith({bool? online, String? lastActive}) {
    return MessengerContactModel(
      id: id,
      userId: userId,
      username: username,
      name: name,
      role: role,
      companyId: companyId,
      company: company,
      designation: designation,
      department: department,
      avatar: avatar,
      online: online ?? this.online,
      lastActive: lastActive ?? this.lastActive,
    );
  }

  factory MessengerContactModel.fromJson(Map<String, dynamic> json) {
    final uid = (json['userId'] ?? json['adminId'] ?? json['id'] ?? json['_id'] ?? '').toString();
    final uname = (json['username'] ?? uid).toString();
    final fullName = (json['name'] ?? uname).toString();
    return MessengerContactModel(
      id: (json['id'] ?? json['_id'] ?? uid).toString(),
      userId: uid,
      username: uname,
      name: fullName,
      role: (json['role'] ?? 'staff').toString().toLowerCase(),
      companyId: json['companyId']?.toString(),
      company: (json['company'] ?? '').toString(),
      designation: (json['designation'] ?? '').toString(),
      department: (json['department'] ?? '').toString(),
      avatar: (json['avatar'] ?? '').toString(),
      online: json['online'] == true,
      lastActive: json['lastActive']?.toString(),
    );
  }
}

class TeamMessageModel {
  final String id;
  final String messageId;
  final String senderId;
  final String senderName;
  final String content;
  final String timestamp;
  final String? editedAt;
  final List<MessageAttachmentModel> attachments;

  const TeamMessageModel({
    required this.id,
    required this.messageId,
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.timestamp,
    this.editedAt,
    this.attachments = const [],
  });

  factory TeamMessageModel.fromJson(Map<String, dynamic> json) {
    final msgId = (json['messageId'] ?? json['id'] ?? json['_id'] ?? '').toString();
    final rawAtts = json['attachments'] as List<dynamic>? ?? const [];
    return TeamMessageModel(
      id: (json['_id'] ?? json['id'] ?? msgId).toString(),
      messageId: msgId,
      senderId: (json['senderId'] ?? '').toString(),
      senderName: (json['senderName'] ?? json['senderId'] ?? 'Team Member').toString(),
      content: (json['content'] ?? '').toString(),
      timestamp: (json['timestamp'] ?? json['createdAt'] ?? '').toString(),
      editedAt: json['editedAt']?.toString(),
      attachments: rawAtts.map(MessageAttachmentModel.fromDynamic).where((a) => a.path.isNotEmpty).toList(),
    );
  }
}

class DmConversationModel {
  final String conversationId;
  final List<String> participants;
  final bool isGroup;
  final String name;
  final String scope;
  final String createdBy;
  final String otherUserId;
  final String otherUserName;
  final String otherUserRole;
  final bool otherUserOnline;
  final String lastMessage;
  final String lastTimestamp;
  final int unreadCount;
  final Map<String, String> publicKeys;
  final List<MessengerContactModel> participantDetails;

  const DmConversationModel({
    required this.conversationId,
    required this.participants,
    this.isGroup = false,
    this.name = '',
    this.scope = 'company',
    this.createdBy = '',
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserRole = '',
    this.otherUserOnline = false,
    this.lastMessage = '',
    this.lastTimestamp = '',
    this.unreadCount = 0,
    this.publicKeys = const {},
    this.participantDetails = const [],
  });

  String get displayTitle => isGroup
      ? (name.isNotEmpty ? name : 'Group Chat (${participants.length})')
      : (otherUserName.isNotEmpty ? otherUserName : 'Colleague');

  DmConversationModel copyWith({
    bool? otherUserOnline,
    int? unreadCount,
    String? lastMessage,
    String? lastTimestamp,
    Map<String, String>? publicKeys,
  }) {
    return DmConversationModel(
      conversationId: conversationId,
      participants: participants,
      isGroup: isGroup,
      name: name,
      scope: scope,
      createdBy: createdBy,
      otherUserId: otherUserId,
      otherUserName: otherUserName,
      otherUserRole: otherUserRole,
      otherUserOnline: otherUserOnline ?? this.otherUserOnline,
      lastMessage: lastMessage ?? this.lastMessage,
      lastTimestamp: lastTimestamp ?? this.lastTimestamp,
      unreadCount: unreadCount ?? this.unreadCount,
      publicKeys: publicKeys ?? this.publicKeys,
      participantDetails: participantDetails,
    );
  }

  factory DmConversationModel.fromJson(
    Map<String, dynamic> json, {
    String currentUserId = '',
    Iterable<String> currentIdentities = const [],
  }) {
    final convId = (json['conversationId'] ?? json['id'] ?? json['_id'] ?? '').toString();
    final rawParticipants = (json['participants'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList();
    final isGroup = json['isGroup'] == true || rawParticipants.length > 2;

    final rawDetails = (json['participantDetails'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(MessengerContactModel.fromJson)
        .toList();

    final myIds = <String>{
      if (currentUserId.trim().isNotEmpty) currentUserId.trim().toLowerCase(),
      for (final id in currentIdentities)
        if (id.trim().isNotEmpty) id.trim().toLowerCase(),
    };

    final otherUser = json['otherUser'] is Map<String, dynamic>
        ? json['otherUser'] as Map<String, dynamic>
        : null;

    String otherId = (otherUser?['userId'] ?? otherUser?['id'] ?? '').toString().trim();
    if (otherId.isEmpty || myIds.contains(otherId.toLowerCase())) {
      otherId = '';
      for (final p in rawParticipants) {
        final pClean = p.trim();
        if (pClean.isNotEmpty && !myIds.contains(pClean.toLowerCase())) {
          otherId = pClean;
          break;
        }
      }
    }
    if (otherId.isEmpty) {
      for (final d in rawDetails) {
        final dId = d.userId.trim();
        if (dId.isNotEmpty &&
            !myIds.contains(dId.toLowerCase()) &&
            !myIds.contains(d.username.trim().toLowerCase()) &&
            !myIds.contains(d.id.trim().toLowerCase())) {
          otherId = dId;
          break;
        }
      }
    }
    if (otherId.isEmpty && rawParticipants.isNotEmpty) {
      otherId = rawParticipants.first;
    }

    String otherName = '';
    if (otherUser != null && !myIds.contains((otherUser['userId'] ?? '').toString().toLowerCase())) {
      otherName = (otherUser['name'] ?? otherUser['username'] ?? '').toString().trim();
    }
    if (otherName.isEmpty) {
      for (final d in rawDetails) {
        if (d.userId.trim().toLowerCase() == otherId.toLowerCase() ||
            d.id.trim().toLowerCase() == otherId.toLowerCase() ||
            d.username.trim().toLowerCase() == otherId.toLowerCase()) {
          otherName = d.displayName;
          break;
        }
      }
    }
    if (otherName.isEmpty) {
      otherName = (json['otherUserName'] ?? otherId).toString();
    }

    final lastMsgObj = json['lastMessage'];
    String lastText = '';
    String lastTs = (json['updatedAt'] ?? '').toString();
    if (lastMsgObj is Map<String, dynamic>) {
      lastText = (lastMsgObj['content'] ?? lastMsgObj['text'] ?? '').toString();
      lastTs = (lastMsgObj['timestamp'] ?? lastMsgObj['createdAt'] ?? lastTs).toString();
    } else if (lastMsgObj is String) {
      lastText = lastMsgObj;
    }

    final pubKeys = <String, String>{};
    if (json['publicKeys'] is Map) {
      (json['publicKeys'] as Map).forEach((k, v) {
        if (v != null) pubKeys[k.toString()] = v.toString();
      });
    }

    return DmConversationModel(
      conversationId: convId,
      participants: rawParticipants,
      isGroup: isGroup,
      name: (json['name'] ?? '').toString(),
      scope: (json['scope'] ?? 'company').toString(),
      createdBy: (json['createdBy'] ?? '').toString(),
      otherUserId: otherId,
      otherUserName: otherName.isNotEmpty ? otherName : 'Colleague',
      otherUserRole: (otherUser?['role'] ?? '').toString(),
      otherUserOnline: otherUser?['online'] == true,
      lastMessage: lastText,
      lastTimestamp: lastTs,
      unreadCount: (json['unreadCount'] is num) ? (json['unreadCount'] as num).toInt() : 0,
      publicKeys: pubKeys,
      participantDetails: rawDetails,
    );
  }
}

class DirectMessageModel {
  final String id;
  final String conversationId;
  final String senderId;
  final String senderName;
  final String content;
  final String? decryptedContent;
  final String iv;
  final bool encrypted;
  final String timestamp;
  final String? editedAt;
  final List<String> readBy;
  final List<MessageAttachmentModel> attachments;

  const DirectMessageModel({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderName,
    required this.content,
    this.decryptedContent,
    this.iv = '',
    this.encrypted = false,
    required this.timestamp,
    this.editedAt,
    this.readBy = const [],
    this.attachments = const [],
  });

  String get displayContent =>
      (decryptedContent != null && decryptedContent!.isNotEmpty) ? decryptedContent! : content;

  bool get hasAudioAttachment => attachments.any((a) => a.isAudio);

  DirectMessageModel copyWith({String? decryptedContent}) {
    return DirectMessageModel(
      id: id,
      conversationId: conversationId,
      senderId: senderId,
      senderName: senderName,
      content: content,
      decryptedContent: decryptedContent ?? this.decryptedContent,
      iv: iv,
      encrypted: encrypted,
      timestamp: timestamp,
      editedAt: editedAt,
      readBy: readBy,
      attachments: attachments,
    );
  }

  factory DirectMessageModel.fromJson(Map<String, dynamic> json) {
    final rawAtts = json['attachments'] as List<dynamic>? ?? const [];
    final rawReadBy = (json['readBy'] as List<dynamic>? ?? const []).map((e) => e.toString()).toList();
    return DirectMessageModel(
      id: (json['_id'] ?? json['messageId'] ?? json['id'] ?? '').toString(),
      conversationId: (json['conversationId'] ?? '').toString(),
      senderId: (json['senderId'] ?? '').toString(),
      senderName: (json['senderName'] ?? json['senderId'] ?? 'User').toString(),
      content: (json['content'] ?? json['ciphertext'] ?? '').toString(),
      iv: (json['iv'] ?? '').toString(),
      encrypted: json['encrypted'] == true,
      timestamp: (json['timestamp'] ?? json['createdAt'] ?? '').toString(),
      editedAt: json['editedAt']?.toString(),
      readBy: rawReadBy,
      attachments: rawAtts.map(MessageAttachmentModel.fromDynamic).where((a) => a.path.isNotEmpty).toList(),
    );
  }
}

class IncomingCallPayload {
  final String callId;
  final String callerId;
  final String callerName;
  final String mediaType; // 'voice' | 'video'
  final Map<String, dynamic>? offer;

  const IncomingCallPayload({
    required this.callId,
    required this.callerId,
    required this.callerName,
    this.mediaType = 'voice',
    this.offer,
  });

  factory IncomingCallPayload.fromMap(Map<String, dynamic> map) {
    return IncomingCallPayload(
      callId: (map['callId'] ?? '').toString(),
      callerId: (map['callerId'] ?? map['senderId'] ?? '').toString(),
      callerName: (map['callerName'] ?? map['senderName'] ?? 'Colleague').toString(),
      mediaType: (map['mediaType'] ?? 'voice').toString(),
      offer: map['offer'] is Map ? Map<String, dynamic>.from(map['offer'] as Map) : null,
    );
  }
}

class MeetingInvitePayload {
  final String meetingId;
  final String title;
  final String hostId;
  final String hostName;
  final String mediaType; // 'voice' | 'video'
  final String? conversationId;

  const MeetingInvitePayload({
    required this.meetingId,
    required this.title,
    required this.hostId,
    required this.hostName,
    this.mediaType = 'video',
    this.conversationId,
  });

  factory MeetingInvitePayload.fromMap(Map<String, dynamic> map) {
    return MeetingInvitePayload(
      meetingId: (map['meetingId'] ?? '').toString(),
      title: (map['title'] ?? 'Team Meeting').toString(),
      hostId: (map['hostId'] ?? map['senderId'] ?? '').toString(),
      hostName: (map['hostName'] ?? map['senderName'] ?? 'Colleague').toString(),
      mediaType: (map['mediaType'] ?? 'video').toString(),
      conversationId: map['conversationId']?.toString(),
    );
  }
}
