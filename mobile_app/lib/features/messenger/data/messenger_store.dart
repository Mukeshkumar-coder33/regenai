import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../auth/data/user_model.dart';
import 'messenger_model.dart';
import 'messenger_service.dart';
import 'messenger_socket_service.dart';
import 'webrtc_call_manager.dart';

// ═══════════════════════════════════════════════════════════════════════════
// MESSENGER IMMUTABLE STATE MODELS (REDUX PATTERN)
// ═══════════════════════════════════════════════════════════════════════════

@immutable
class MessengerState {
  final Map<String, List<DirectMessageModel>> messagesByConversation;
  final Set<String> pendingMessageIds;
  final Set<String> failedMessageIds;
  final Map<String, double> mediaUploadProgress;

  final List<DmConversationModel> conversations;
  final String? activeConversationId;
  final bool isConversationVisible;
  final bool isLoadingConversations;
  final bool isLoadingMessages;
  final String? conversationError;

  final Set<String> onlineUserIds;
  final Map<String, DateTime> lastSeen;

  final CallPhase callPhase;
  final String? activeCallId;
  final String? callPeerId;
  final String? callPeerName;
  final String callMediaType;
  final bool isCallMuted;
  final bool isCallSpeakerOn;
  final bool isCallVideoOff;
  final int callDurationSeconds;

  final bool isSocketConnected;
  final UserModel? currentUser;

  const MessengerState({
    this.messagesByConversation = const {},
    this.pendingMessageIds = const {},
    this.failedMessageIds = const {},
    this.mediaUploadProgress = const {},
    this.conversations = const [],
    this.activeConversationId,
    this.isConversationVisible = false,
    this.isLoadingConversations = false,
    this.isLoadingMessages = false,
    this.conversationError,
    this.onlineUserIds = const {},
    this.lastSeen = const {},
    this.callPhase = CallPhase.idle,
    this.activeCallId,
    this.callPeerId,
    this.callPeerName,
    this.callMediaType = 'voice',
    this.isCallMuted = false,
    this.isCallSpeakerOn = false,
    this.isCallVideoOff = false,
    this.callDurationSeconds = 0,
    this.isSocketConnected = false,
    this.currentUser,
  });

  factory MessengerState.initial() => const MessengerState();

  List<DirectMessageModel> get activeMessages {
    if (activeConversationId == null) return const [];
    return messagesByConversation[activeConversationId!] ?? const [];
  }

  DmConversationModel? get activeConversation {
    if (activeConversationId == null) return null;
    return conversations.cast<DmConversationModel?>().firstWhere(
      (c) => c?.conversationId == activeConversationId,
      orElse: () => null,
    );
  }

  int get totalUnreadCount {
    return conversations.fold<int>(0, (sum, c) => sum + c.unreadCount);
  }

  bool isUserOnline(String? userId) {
    if (userId == null || userId.isEmpty) return false;
    return onlineUserIds.contains(userId.trim().toLowerCase());
  }

  MessengerState copyWith({
    Map<String, List<DirectMessageModel>>? messagesByConversation,
    Set<String>? pendingMessageIds,
    Set<String>? failedMessageIds,
    Map<String, double>? mediaUploadProgress,
    List<DmConversationModel>? conversations,
    String? activeConversationId,
    bool clearActiveConversation = false,
    bool? isConversationVisible,
    bool? isLoadingConversations,
    bool? isLoadingMessages,
    String? conversationError,
    bool clearError = false,
    Set<String>? onlineUserIds,
    Map<String, DateTime>? lastSeen,
    CallPhase? callPhase,
    String? activeCallId,
    bool clearCallId = false,
    String? callPeerId,
    String? callPeerName,
    String? callMediaType,
    bool? isCallMuted,
    bool? isCallSpeakerOn,
    bool? isCallVideoOff,
    int? callDurationSeconds,
    bool? isSocketConnected,
    UserModel? currentUser,
  }) {
    return MessengerState(
      messagesByConversation: messagesByConversation ?? this.messagesByConversation,
      pendingMessageIds: pendingMessageIds ?? this.pendingMessageIds,
      failedMessageIds: failedMessageIds ?? this.failedMessageIds,
      mediaUploadProgress: mediaUploadProgress ?? this.mediaUploadProgress,
      conversations: conversations ?? this.conversations,
      activeConversationId: clearActiveConversation
          ? null
          : (activeConversationId ?? this.activeConversationId),
      isConversationVisible: isConversationVisible ?? this.isConversationVisible,
      isLoadingConversations: isLoadingConversations ?? this.isLoadingConversations,
      isLoadingMessages: isLoadingMessages ?? this.isLoadingMessages,
      conversationError: clearError ? null : (conversationError ?? this.conversationError),
      onlineUserIds: onlineUserIds ?? this.onlineUserIds,
      lastSeen: lastSeen ?? this.lastSeen,
      callPhase: callPhase ?? this.callPhase,
      activeCallId: clearCallId ? null : (activeCallId ?? this.activeCallId),
      callPeerId: clearCallId ? null : (callPeerId ?? this.callPeerId),
      callPeerName: clearCallId ? null : (callPeerName ?? this.callPeerName),
      callMediaType: callMediaType ?? this.callMediaType,
      isCallMuted: isCallMuted ?? this.isCallMuted,
      isCallSpeakerOn: isCallSpeakerOn ?? this.isCallSpeakerOn,
      isCallVideoOff: isCallVideoOff ?? this.isCallVideoOff,
      callDurationSeconds: callDurationSeconds ?? this.callDurationSeconds,
      isSocketConnected: isSocketConnected ?? this.isSocketConnected,
      currentUser: currentUser ?? this.currentUser,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MESSENGER ACTIONS (REDUX ARCHITECTURE)
// ═══════════════════════════════════════════════════════════════════════════

sealed class MessengerAction {
  const MessengerAction();
}

class SetCurrentUserAction extends MessengerAction {
  final UserModel user;
  const SetCurrentUserAction(this.user);
}

class LoadConversationsAction extends MessengerAction {
  const LoadConversationsAction();
}

class ConversationsLoadedAction extends MessengerAction {
  final List<DmConversationModel> conversations;
  const ConversationsLoadedAction(this.conversations);
}

class ConversationsLoadFailedAction extends MessengerAction {
  final String error;
  const ConversationsLoadFailedAction(this.error);
}

class OpenConversationAction extends MessengerAction {
  final String conversationId;
  final bool isVisible;
  const OpenConversationAction(this.conversationId, {this.isVisible = true});
}

class CloseConversationAction extends MessengerAction {
  const CloseConversationAction();
}

class SetConversationVisibilityAction extends MessengerAction {
  final bool isVisible;
  const SetConversationVisibilityAction(this.isVisible);
}

class LoadMessagesAction extends MessengerAction {
  final String conversationId;
  const LoadMessagesAction(this.conversationId);
}

class MessagesLoadedAction extends MessengerAction {
  final String conversationId;
  final List<DirectMessageModel> messages;
  const MessagesLoadedAction(this.conversationId, this.messages);
}

class SendMessageOptimisticAction extends MessengerAction {
  final DirectMessageModel optimisticMessage;
  const SendMessageOptimisticAction(this.optimisticMessage);
}

class MessageSendSuccessAction extends MessengerAction {
  final String tempId;
  final DirectMessageModel confirmedMessage;
  const MessageSendSuccessAction(this.tempId, this.confirmedMessage);
}

class MessageSendFailedAction extends MessengerAction {
  final String tempId;
  final String error;
  const MessageSendFailedAction(this.tempId, this.error);
}

class ReceiveSocketMessageAction extends MessengerAction {
  final DirectMessageModel message;
  const ReceiveSocketMessageAction(this.message);
}

class UpdateMessageReadReceiptAction extends MessengerAction {
  final String conversationId;
  final String readerUserId;
  final List<String> readBy;
  const UpdateMessageReadReceiptAction({
    required this.conversationId,
    required this.readerUserId,
    this.readBy = const [],
  });
}

class MarkConversationReadLocallyAction extends MessengerAction {
  final String conversationId;
  final String readerUserId;
  const MarkConversationReadLocallyAction({
    required this.conversationId,
    required this.readerUserId,
  });
}

class UpdateUserPresenceAction extends MessengerAction {
  final String userId;
  final bool isOnline;
  final DateTime? lastSeen;
  const UpdateUserPresenceAction({
    required this.userId,
    required this.isOnline,
    this.lastSeen,
  });
}

class SyncOnlineUsersAction extends MessengerAction {
  final Set<String> onlineUserIds;
  const SyncOnlineUsersAction(this.onlineUserIds);
}

class SocketConnectionChangedAction extends MessengerAction {
  final bool isConnected;
  const SocketConnectionChangedAction(this.isConnected);
}

class CallPhaseChangedAction extends MessengerAction {
  final CallPhase phase;
  final String? callId;
  final String? peerId;
  final String? peerName;
  final String? mediaType;
  const CallPhaseChangedAction({
    required this.phase,
    this.callId,
    this.peerId,
    this.peerName,
    this.mediaType,
  });
}

class CallDurationTickAction extends MessengerAction {
  const CallDurationTickAction();
}

class CallMediaToggledAction extends MessengerAction {
  final bool? isMuted;
  final bool? isSpeakerOn;
  final bool? isVideoOff;
  const CallMediaToggledAction({this.isMuted, this.isSpeakerOn, this.isVideoOff});
}

class ResetMessengerStateAction extends MessengerAction {
  const ResetMessengerStateAction();
}

// ═══════════════════════════════════════════════════════════════════════════
// PURE REDUCER
// ═══════════════════════════════════════════════════════════════════════════

MessengerState messengerReducer(MessengerState state, MessengerAction action) {
  switch (action) {
    case SetCurrentUserAction(:final user):
      return state.copyWith(currentUser: user);

    case LoadConversationsAction():
      return state.copyWith(isLoadingConversations: true, clearError: true);

    case ConversationsLoadedAction(:final conversations):
      return state.copyWith(
        conversations: conversations,
        isLoadingConversations: false,
        clearError: true,
      );

    case ConversationsLoadFailedAction(:final error):
      return state.copyWith(
        isLoadingConversations: false,
        conversationError: error,
      );

    case OpenConversationAction(:final conversationId, :final isVisible):
      // When opening a conversation, reset its unreadCount locally
      final updatedConvs = state.conversations.map((c) {
        if (c.conversationId == conversationId) {
          return c.copyWith(unreadCount: 0);
        }
        return c;
      }).toList();

      return state.copyWith(
        activeConversationId: conversationId,
        isConversationVisible: isVisible,
        conversations: updatedConvs,
        isLoadingMessages: true,
      );

    case CloseConversationAction():
      return state.copyWith(
        clearActiveConversation: true,
        isConversationVisible: false,
      );

    case SetConversationVisibilityAction(:final isVisible):
      return state.copyWith(isConversationVisible: isVisible);

    case LoadMessagesAction():
      return state.copyWith(isLoadingMessages: true);

    case MessagesLoadedAction(:final conversationId, :final messages):
      final existingMessages = state.messagesByConversation[conversationId] ?? const [];
      final pendingMap = <String, DirectMessageModel>{};
      for (final m in existingMessages) {
        if (state.pendingMessageIds.contains(m.id)) {
          pendingMap[m.id] = m;
        }
      }

      // Merge and deduplicate by message ID & timestamp
      final seenIds = <String>{};
      final merged = <DirectMessageModel>[];

      for (final m in messages) {
        if (seenIds.add(m.id)) {
          merged.add(m);
        }
      }

      // Keep pending optimistic messages that haven't returned from server yet
      for (final p in pendingMap.values) {
        final alreadyConfirmed = merged.any(
          (m) => m.content == p.content && m.senderId == p.senderId,
        );
        if (!alreadyConfirmed && seenIds.add(p.id)) {
          merged.add(p);
        }
      }

      // Sort strictly in chronological order
      merged.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      final updatedMap = Map<String, List<DirectMessageModel>>.from(state.messagesByConversation);
      updatedMap[conversationId] = merged;

      return state.copyWith(
        messagesByConversation: updatedMap,
        isLoadingMessages: false,
      );

    case SendMessageOptimisticAction(:final optimisticMessage):
      final convId = optimisticMessage.conversationId;
      final existing = state.messagesByConversation[convId] ?? const [];
      final updatedList = List<DirectMessageModel>.from(existing)..add(optimisticMessage);
      updatedList.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      final updatedMap = Map<String, List<DirectMessageModel>>.from(state.messagesByConversation);
      updatedMap[convId] = updatedList;

      final updatedPending = Set<String>.from(state.pendingMessageIds)..add(optimisticMessage.id);

      // Update last message in conversation list
      final updatedConvs = state.conversations.map((c) {
        if (c.conversationId == convId) {
          return c.copyWith(
            lastMessage: optimisticMessage.displayContent,
            lastTimestamp: optimisticMessage.timestamp,
          );
        }
        return c;
      }).toList();

      return state.copyWith(
        messagesByConversation: updatedMap,
        pendingMessageIds: updatedPending,
        conversations: updatedConvs,
      );

    case MessageSendSuccessAction(:final tempId, :final confirmedMessage):
      final convId = confirmedMessage.conversationId;
      final existing = state.messagesByConversation[convId] ?? const [];

      // Idempotently replace optimistic temporary message with server-confirmed message
      bool replaced = false;
      final updatedList = existing.map<DirectMessageModel>((m) {
        if (m.id == tempId ||
            (m.id.startsWith('local-') &&
             m.senderId == confirmedMessage.senderId &&
             m.content == confirmedMessage.content)) {
          replaced = true;
          return confirmedMessage;
        }
        return m;
      }).toList();

      if (!replaced && !updatedList.any((m) => m.id == confirmedMessage.id)) {
        updatedList.add(confirmedMessage);
      }
      updatedList.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      final updatedMap = Map<String, List<DirectMessageModel>>.from(state.messagesByConversation);
      updatedMap[convId] = updatedList;

      final updatedPending = Set<String>.from(state.pendingMessageIds)..remove(tempId);
      final updatedFailed = Set<String>.from(state.failedMessageIds)..remove(tempId);

      return state.copyWith(
        messagesByConversation: updatedMap,
        pendingMessageIds: updatedPending,
        failedMessageIds: updatedFailed,
      );

    case MessageSendFailedAction(:final tempId):
      final updatedPending = Set<String>.from(state.pendingMessageIds)..remove(tempId);
      final updatedFailed = Set<String>.from(state.failedMessageIds)..add(tempId);
      return state.copyWith(
        pendingMessageIds: updatedPending,
        failedMessageIds: updatedFailed,
      );

    case ReceiveSocketMessageAction(:final message):
      final convId = message.conversationId;
      final existing = state.messagesByConversation[convId] ?? const [];

      // Check if this message replaces an optimistic message
      bool matchedOptimistic = false;
      final updatedList = existing.map<DirectMessageModel>((m) {
        if (m.id == message.id) {
          return message; // In-place update (e.g. read receipts or edits)
        }
        if (m.id.startsWith('local-') &&
            m.senderId == message.senderId &&
            m.content == message.content) {
          matchedOptimistic = true;
          return message;
        }
        return m;
      }).toList();

      if (!matchedOptimistic && !updatedList.any((m) => m.id == message.id)) {
        updatedList.add(message);
      }
      updatedList.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      final updatedMap = Map<String, List<DirectMessageModel>>.from(state.messagesByConversation);
      updatedMap[convId] = updatedList;

      // Update conversation last message & unread count
      final myId = state.currentUser?.userId ?? '';
      final isFromMe = message.senderId.trim().toLowerCase() == myId.trim().toLowerCase();
      final isCurrentlyViewing = state.activeConversationId == convId && state.isConversationVisible;

      final updatedConvs = state.conversations.map((c) {
        if (c.conversationId == convId) {
          final newUnread = (!isFromMe && !isCurrentlyViewing) ? c.unreadCount + 1 : 0;
          return c.copyWith(
            lastMessage: message.displayContent,
            lastTimestamp: message.timestamp,
            unreadCount: newUnread,
          );
        }
        return c;
      }).toList();

      return state.copyWith(
        messagesByConversation: updatedMap,
        conversations: updatedConvs,
      );

    case UpdateMessageReadReceiptAction(:final conversationId, :final readerUserId, :final readBy):
      // STRICT READ RECEIPT: Only update messages in the target conversation
      final existing = state.messagesByConversation[conversationId];
      if (existing == null) return state;

      final updatedList = existing.map<DirectMessageModel>((m) {
        final updatedReadBy = Set<String>.from(m.readBy);
        if (readerUserId.isNotEmpty) updatedReadBy.add(readerUserId);
        if (readBy.isNotEmpty) updatedReadBy.addAll(readBy);
        return m.copyWith(readBy: updatedReadBy.toList());
      }).toList();

      final updatedMap = Map<String, List<DirectMessageModel>>.from(state.messagesByConversation);
      updatedMap[conversationId] = updatedList;

      return state.copyWith(messagesByConversation: updatedMap);

    case MarkConversationReadLocallyAction(:final conversationId, :final readerUserId):
      final existing = state.messagesByConversation[conversationId];
      if (existing == null) return state;

      final updatedList = existing.map<DirectMessageModel>((m) {
        if (!m.readBy.contains(readerUserId)) {
          final set = Set<String>.from(m.readBy)..add(readerUserId);
          return m.copyWith(readBy: set.toList());
        }
        return m;
      }).toList();

      final updatedMap = Map<String, List<DirectMessageModel>>.from(state.messagesByConversation);
      updatedMap[conversationId] = updatedList;

      final updatedConvs = state.conversations.map((c) {
        if (c.conversationId == conversationId) {
          return c.copyWith(unreadCount: 0);
        }
        return c;
      }).toList();

      return state.copyWith(
        messagesByConversation: updatedMap,
        conversations: updatedConvs,
      );

    case UpdateUserPresenceAction(:final userId, :final isOnline, :final lastSeen):
      final cleanId = userId.trim().toLowerCase();
      final updatedOnline = Set<String>.from(state.onlineUserIds);
      if (isOnline) {
        updatedOnline.add(cleanId);
      } else {
        updatedOnline.remove(cleanId);
      }

      final updatedLastSeen = Map<String, DateTime>.from(state.lastSeen);
      if (lastSeen != null) {
        updatedLastSeen[cleanId] = lastSeen;
      }

      // Update conversations otherUserOnline flag
      final updatedConvs = state.conversations.map((c) {
        if (c.otherUserId.trim().toLowerCase() == cleanId) {
          return c.copyWith(otherUserOnline: isOnline);
        }
        return c;
      }).toList();

      return state.copyWith(
        onlineUserIds: updatedOnline,
        lastSeen: updatedLastSeen,
        conversations: updatedConvs,
      );

    case SyncOnlineUsersAction(:final onlineUserIds):
      final normalized = onlineUserIds.map((e) => e.trim().toLowerCase()).toSet();
      final updatedConvs = state.conversations.map((c) {
        final isOnline = normalized.contains(c.otherUserId.trim().toLowerCase());
        return c.copyWith(otherUserOnline: isOnline);
      }).toList();

      return state.copyWith(
        onlineUserIds: normalized,
        conversations: updatedConvs,
      );

    case SocketConnectionChangedAction(:final isConnected):
      return state.copyWith(isSocketConnected: isConnected);

    case CallPhaseChangedAction(:final phase, :final callId, :final peerId, :final peerName, :final mediaType):
      final isEnding = phase == CallPhase.idle;
      return state.copyWith(
        callPhase: phase,
        activeCallId: isEnding ? null : callId,
        clearCallId: isEnding,
        callPeerId: isEnding ? null : peerId,
        callPeerName: isEnding ? null : peerName,
        callMediaType: mediaType ?? state.callMediaType,
        callDurationSeconds: isEnding ? 0 : state.callDurationSeconds,
      );

    case CallDurationTickAction():
      return state.copyWith(callDurationSeconds: state.callDurationSeconds + 1);

    case CallMediaToggledAction(:final isMuted, :final isSpeakerOn, :final isVideoOff):
      return state.copyWith(
        isCallMuted: isMuted ?? state.isCallMuted,
        isCallSpeakerOn: isSpeakerOn ?? state.isCallSpeakerOn,
        isCallVideoOff: isVideoOff ?? state.isCallVideoOff,
      );

    case ResetMessengerStateAction():
      return MessengerState.initial();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CENTRAL MESSENGER STORE (REDUX ARCHITECTURE + MIDDLEWARE EFFECTS)
// ═══════════════════════════════════════════════════════════════════════════

class MessengerStore extends ChangeNotifier {
  MessengerStore._();
  static final MessengerStore instance = MessengerStore._();

  MessengerState _state = MessengerState.initial();
  MessengerState get state => _state;

  final MessengerService _messengerService = MessengerService();
  final List<StreamSubscription<dynamic>> _socketSubscriptions = [];
  bool _initialized = false;
  Timer? _callDurationTicker;

  UserModel? get currentUser => _state.currentUser;

  /// Initialize store with authenticated user and bind socket listeners
  void initialize(UserModel user) {
    if (_initialized && _state.currentUser?.userId == user.userId) {
      return;
    }
    _cleanup();
    _initialized = true;

    dispatch(SetCurrentUserAction(user));
    _bindSocketEvents();
    dispatch(const LoadConversationsAction());
    _loadConversationsFromApi();
  }

  void init(UserModel user) => initialize(user);

  /// Clean up store on logout or user switch
  void reset() {
    _cleanup();
    dispatch(const ResetMessengerStateAction());
  }

  void _cleanup() {
    for (final sub in _socketSubscriptions) {
      sub.cancel();
    }
    _socketSubscriptions.clear();
    _callDurationTicker?.cancel();
    _callDurationTicker = null;
    _initialized = false;
  }

  /// Centralized Redux Dispatcher
  Future<void> dispatch(MessengerAction action) async {
    final oldState = _state;
    _state = messengerReducer(_state, action);

    // Only notify listeners if state actually changed
    if (!identical(oldState, _state)) {
      notifyListeners();
    }

    // Middleware / Asynchronous Side Effects
    await _handleMiddlewareEffects(action);
  }

  Future<void> _handleMiddlewareEffects(MessengerAction action) async {
    switch (action) {
      case OpenConversationAction(:final conversationId, :final isVisible):
        // 1. Notify socket server of active conversation
        MessengerSocketService.instance.setActiveConversation(conversationId);

        // 2. Fetch conversation message history
        await _loadMessagesFromApi(conversationId);

        // 3. Mark conversation read strictly if user is viewing and eligible
        if (isVisible) {
          _checkAndEmitReadReceipt(conversationId);
        }

      case CloseConversationAction():
        MessengerSocketService.instance.setActiveConversation(null);

      case SetConversationVisibilityAction(:final isVisible):
        if (isVisible && _state.activeConversationId != null) {
          MessengerSocketService.instance.setActiveConversation(_state.activeConversationId);
          _checkAndEmitReadReceipt(_state.activeConversationId!);
        } else {
          MessengerSocketService.instance.setActiveConversation(null);
        }

      case CallPhaseChangedAction(:final phase):
        if (phase == CallPhase.connected) {
          _callDurationTicker?.cancel();
          _callDurationTicker = Timer.periodic(const Duration(seconds: 1), (_) {
            dispatch(const CallDurationTickAction());
          });
        } else if (phase == CallPhase.idle) {
          _callDurationTicker?.cancel();
          _callDurationTicker = null;
        }

      default:
        break;
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // ASYNC API & EFFECT HANDLERS
  // ═════════════════════════════════════════════════════════════════════════

  Future<void> _loadConversationsFromApi() async {
    final user = _state.currentUser;
    if (user == null) return;

    try {
      final conversations = await _messengerService.getConversations(user: user);
      await dispatch(ConversationsLoadedAction(conversations));
    } catch (e) {
      await dispatch(ConversationsLoadFailedAction(e.toString()));
    }
  }

  Future<void> _loadMessagesFromApi(String conversationId) async {
    final user = _state.currentUser;
    if (user == null) return;

    try {
      final messages = await _messengerService.getDirectMessages(
        user: user,
        conversationId: conversationId,
      );
      await dispatch(MessagesLoadedAction(conversationId, messages));
    } catch (_) {
      // Keep optimistic or existing messages if network is temporarily slow
    }
  }

  /// Sends a text or media message through the Redux pipeline
  Future<void> sendMessage({
    required String conversationId,
    required String content,
    String? recipientId,
    bool isVoice = false,
    List<MessageAttachmentModel> attachments = const [],
    bool isEncrypted = false,
    String iv = '',
  }) async {
    final user = _state.currentUser;
    if (user == null) return;

    final myId = user.userId.isNotEmpty ? user.userId : user.id;
    final myName = user.name.isNotEmpty ? user.name : user.username;
    final tempId = 'local-dm-${DateTime.now().millisecondsSinceEpoch}';
    final nowIso = DateTime.now().toIso8601String();

    final optimistic = DirectMessageModel(
      id: tempId,
      conversationId: conversationId,
      senderId: myId,
      senderName: myName,
      content: content,
      decryptedContent: content,
      iv: iv,
      encrypted: isEncrypted,
      timestamp: nowIso,
      readBy: [myId],
      attachments: attachments,
    );

    // 1. Optimistic insertion
    await dispatch(SendMessageOptimisticAction(optimistic));

    // 2. Perform authenticated backend send
    try {
      final confirmed = await _messengerService.sendDirectMessage(
        user: user,
        conversationId: conversationId,
        content: content,
        isVoice: isVoice,
        encrypted: isEncrypted,
        iv: iv,
        attachments: attachments.map((a) => a.toJson()).toList(),
      );

      if (confirmed != null) {
        await dispatch(MessageSendSuccessAction(tempId, confirmed));
      } else {
        await dispatch(MessageSendSuccessAction(tempId, optimistic));
      }
    } catch (e) {
      await dispatch(MessageSendFailedAction(tempId, e.toString()));
    }
  }

  /// STRICT Read Receipt Emission
  ///
  /// Criteria for marking messages as read:
  /// 1. Conversation MUST be currently open in the active state.
  /// 2. Conversation MUST be visible on screen in the foreground.
  /// 3. Conversation MUST contain messages sent by other participants where readBy does not include current user.
  void _checkAndEmitReadReceipt(String conversationId) {
    final user = _state.currentUser;
    if (user == null) return;
    if (_state.activeConversationId != conversationId || !_state.isConversationVisible) {
      return;
    }

    final myId = user.userId.isNotEmpty ? user.userId : user.id;
    final messages = _state.messagesByConversation[conversationId] ?? const [];

    final hasUnreadFromOthers = messages.any(
      (m) => m.senderId != myId && !m.readBy.contains(myId),
    );

    if (hasUnreadFromOthers) {
      // 1. Update state immediately (optimistic read)
      dispatch(MarkConversationReadLocallyAction(
        conversationId: conversationId,
        readerUserId: myId,
      ));

      // 2. Emit read event to Socket.IO server
      MessengerSocketService.instance.emit('dm:read', {
        'conversationId': conversationId,
        'userId': myId,
      });

      // 3. Persist read status via REST API
      _messengerService.markConversationRead(
        user: user,
        conversationId: conversationId,
      ).catchError((_) => false);
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // CENTRALIZED SOCKET EVENT BINDING
  // ═════════════════════════════════════════════════════════════════════════

  void _bindSocketEvents() {
    final socket = MessengerSocketService.instance;

    _socketSubscriptions.addAll([
      socket.onConnectionChange.listen((isConnected) {
        dispatch(SocketConnectionChangedAction(isConnected));
        if (isConnected) {
          _loadConversationsFromApi();
          if (_state.activeConversationId != null) {
            _loadMessagesFromApi(_state.activeConversationId!);
          }
        }
      }),

      socket.onDmChange.listen((payload) {
        final action = payload['action']?.toString() ?? 'create';

        if (action == 'create') {
          final rawMsg = payload['message'];
          if (rawMsg is Map<String, dynamic>) {
            final msg = DirectMessageModel.fromJson(rawMsg);
            dispatch(ReceiveSocketMessageAction(msg));

            // Check if read receipt should be triggered
            if (msg.conversationId == _state.activeConversationId && _state.isConversationVisible) {
              _checkAndEmitReadReceipt(msg.conversationId);
            }
          }
        } else if (action == 'read') {
          final convId = (payload['conversationId'] ?? '').toString();
          // STRICT: Only process read receipt if conversationId is provided
          if (convId.isNotEmpty) {
            final readerId = (payload['userId'] ?? '').toString();
            final readByList = (payload['readBy'] is List)
                ? (payload['readBy'] as List).map((e) => e.toString()).toList()
                : <String>[];

            dispatch(UpdateMessageReadReceiptAction(
              conversationId: convId,
              readerUserId: readerId,
              readBy: readByList,
            ));
          }
        }
      }),

      socket.onPresenceUpdate.listen((payload) {
        final uid = (payload['userId'] ?? '').toString();
        final status = (payload['status'] ?? '').toString().toLowerCase();
        final isOnline = status == 'online';
        final lastActiveStr = payload['lastActive']?.toString();
        final lastSeen = lastActiveStr != null ? DateTime.tryParse(lastActiveStr) : null;

        if (uid.isNotEmpty) {
          dispatch(UpdateUserPresenceAction(
            userId: uid,
            isOnline: isOnline,
            lastSeen: lastSeen,
          ));
        }
      }),
    ]);
  }
}
