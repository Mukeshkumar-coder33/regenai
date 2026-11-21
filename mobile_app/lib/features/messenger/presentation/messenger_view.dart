import 'dart:async';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/celadon_colors.dart';
import '../../auth/data/user_model.dart';
import '../../dashboard/data/dashboard_service.dart';
import '../data/e2e_crypto_service.dart';
import '../data/messenger_model.dart';
import '../data/messenger_service.dart';
import '../data/messenger_socket_service.dart';
import '../data/webrtc_call_manager.dart';
import 'call_overlay.dart';
import 'media_attachment_widgets.dart';
import 'voice_recorder_sheet.dart';

/// Unified Role-Aware ReGen Messenger Screen
///
/// Modern mobile messenger design (WhatsApp / Slack / Teams inspired) built in
/// ReGen's Premium Celadon design system, connected directly to ReGen's MERN +
/// Socket.IO (`/ws`) + WebRTC backend.
class MessengerView extends StatefulWidget {
  final UserModel user;
  final VoidCallback? onBack;
  final VoidCallback? onOpenDrawer;
  final bool embedded;
  final MessengerService? messengerService;
  final DashboardService? dashboardService;
  final void Function(bool inChatOrTeam)? onChatStateChanged;

  const MessengerView({
    super.key,
    required this.user,
    this.onBack,
    this.onOpenDrawer,
    this.embedded = false,
    this.messengerService,
    this.dashboardService,
    this.onChatStateChanged,
  });

  @override
  State<MessengerView> createState() => _MessengerViewState();
}

class _MessengerViewState extends State<MessengerView> {
  late MessengerService _messengerService;
  late DashboardService _dashboardService;

  // Tab 0 = Chats (1:1 & Groups), Tab 1 = Team Channel (hidden for Super Admin central portal)
  int _activeTab = 0;
  bool _isLoading = true;
  bool _isSending = false;
  bool _socketConnected = MessengerSocketService.instance.isConnected;

  List<TeamMessageModel> _teamMessages = [];
  List<DmConversationModel> _conversations = [];
  List<MessengerContactModel> _contacts = [];
  String _searchQuery = '';
  int _chatFilterIndex = 0; // 0 = All, 1 = Unread, 2 = Group

  DmConversationModel? _activeConversation;
  List<DirectMessageModel> _directMessages = [];
  bool _isLoadingDm = false;
  SecretKey? _activeSharedKey;
  bool _e2eActive = false;

  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<StreamSubscription<dynamic>> _socketSubs = [];

  static const Color _chatCanvasBg = Color(0xFFEEF4F1);
  static const Color _searchFill = Color(0xFFEDF3F0);
  static const Color _subtleDivider = Color(0xFFE6EEEA);

  String get _myUserId =>
      widget.user.userId.isNotEmpty ? widget.user.userId : widget.user.id;

  bool get _showTeamChannelTab => !widget.user.isSuperAdmin;

  bool get _isInChatOrTeam =>
      _activeConversation != null || (_activeTab == 1 && _showTeamChannelTab);

  void _notifyChatState() {
    widget.onChatStateChanged?.call(_isInChatOrTeam);
  }

  @override
  void initState() {
    super.initState();
    _messengerService = widget.messengerService ?? MessengerService();
    _dashboardService = widget.dashboardService ?? DashboardService();
    WebRtcCallManager.instance.bindUser(widget.user);
    MessengerSocketService.instance.connect(user: widget.user);
    _activeTab = 0;
    _attachSocketListeners();
    _loadMessengerData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifyChatState();
    });
  }

  @override
  void didUpdateWidget(MessengerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifyChatState();
    });
    final userChanged = widget.user.userId != oldWidget.user.userId ||
        widget.user.id != oldWidget.user.id ||
        widget.user.role != oldWidget.user.role ||
        widget.user.companyId != oldWidget.user.companyId ||
        widget.user.token != oldWidget.user.token;
    if (userChanged) {
      _messengerService = widget.messengerService ?? MessengerService();
      _dashboardService = widget.dashboardService ?? DashboardService();
      WebRtcCallManager.instance.bindUser(widget.user);
      MessengerSocketService.instance.connect(user: widget.user);
      setState(() {
        _activeConversation = null;
        _directMessages = [];
        _conversations = [];
        _contacts = [];
        _teamMessages = [];
        _activeSharedKey = null;
        _e2eActive = false;
        _isLoading = true;
      });
      _loadMessengerData();
    }
  }

  @override
  void dispose() {
    for (final s in _socketSubs) {
      s.cancel();
    }
    _socketSubs.clear();
    _messageController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════
  // EMPLOYEE NAME RESOLUTION (ALWAYS SHOW NAME, NEVER RAW ID)
  // ═══════════════════════════════════════════════════════════════

  MessengerContactModel? _findContactById(String rawId) {
    final id = rawId.trim().toLowerCase();
    if (id.isEmpty) return null;
    for (final c in _contacts) {
      if (c.userId.trim().toLowerCase() == id ||
          c.id.trim().toLowerCase() == id ||
          c.username.trim().toLowerCase() == id) {
        return c;
      }
    }
    return null;
  }

  /// Resolves the actual other peer identifier for 1-to-1 chats,
  /// guaranteeing it never returns the current user themselves.
  String _resolvePeerId(DmConversationModel conv) {
    final mySet = <String>{
      _myUserId.trim().toLowerCase(),
      widget.user.userId.trim().toLowerCase(),
      widget.user.id.trim().toLowerCase(),
      widget.user.username.trim().toLowerCase(),
    }..removeWhere((s) => s.isEmpty);

    if (conv.otherUserId.trim().isNotEmpty &&
        !mySet.contains(conv.otherUserId.trim().toLowerCase())) {
      return conv.otherUserId.trim();
    }
    for (final p in conv.participants) {
      final pTrim = p.trim();
      if (pTrim.isNotEmpty && !mySet.contains(pTrim.toLowerCase())) {
        return pTrim;
      }
    }
    for (final d in conv.participantDetails) {
      final dId = d.userId.trim();
      if (dId.isNotEmpty && !mySet.contains(dId.toLowerCase())) {
        return dId;
      }
    }
    for (final c in _contacts) {
      final cId = c.userId.trim();
      if (cId.isNotEmpty && !mySet.contains(cId.toLowerCase())) {
        if (conv.participants.any((p) =>
            p.toLowerCase() == cId.toLowerCase() ||
            p.toLowerCase() == c.username.toLowerCase())) {
          return cId;
        }
      }
    }
    return conv.otherUserId;
  }

  /// Resolves a conversation's display title to the real Employee / Owner Name
  /// (never falling back to raw staff codes like `KRH-123` when the employee exists).
  String _resolveConversationName(DmConversationModel conv) {
    if (conv.isGroup) return conv.displayTitle;

    // 1. Check directory contacts first (always has real employee name)
    final contact = _findContactById(conv.otherUserId);
    if (contact != null && contact.displayName.isNotEmpty) {
      return contact.displayName;
    }

    // 2. Check participantDetails attached by backend
    for (final p in conv.participantDetails) {
      if (p.userId.trim().toLowerCase() == conv.otherUserId.trim().toLowerCase() &&
          p.name.trim().isNotEmpty) {
        return p.name.trim();
      }
    }

    // 3. Fallback to backend-supplied otherUserName
    return conv.otherUserName.isNotEmpty ? conv.otherUserName : 'Colleague';
  }

  bool _resolveConversationOnline(DmConversationModel conv) {
    if (conv.isGroup) return false;
    final contact = _findContactById(conv.otherUserId);
    if (contact != null) return contact.online;
    return conv.otherUserOnline;
  }

  String _resolveConversationRoleSubtitle(DmConversationModel conv) {
    if (conv.isGroup) {
      return '${conv.participants.length} members';
    }
    final contact = _findContactById(conv.otherUserId);
    if (contact != null) {
      if (contact.online) return 'Online';
      if (contact.company.isNotEmpty && widget.user.isSuperAdmin) {
        return '${contact.roleLabel} • ${contact.company}';
      }
      return contact.designation.isNotEmpty ? contact.designation : contact.roleLabel;
    }
    return conv.otherUserOnline ? 'Online' : 'Offline';
  }

  String _resolveSenderName(String senderId, String fallbackName) {
    if (senderId == _myUserId) {
      return widget.user.name.isNotEmpty ? widget.user.name : widget.user.username;
    }
    final contact = _findContactById(senderId);
    if (contact != null && contact.displayName.isNotEmpty) {
      return contact.displayName;
    }
    return fallbackName;
  }

  // ═══════════════════════════════════════════════════════════════
  // REAL-TIME SOCKET & DATA LOADING
  // ═══════════════════════════════════════════════════════════════

  void _attachSocketListeners() {
    final socket = MessengerSocketService.instance;
    _socketSubs.addAll([
      socket.onConnectionChange.listen((connected) {
        if (mounted) setState(() => _socketConnected = connected);
      }),
      socket.onMessageChange.listen((_) {
        if (_showTeamChannelTab) _refreshTeamMessages();
      }),
      socket.onDmChange.listen((payload) async {
        final convId = (payload['conversationId'] ?? '').toString();
        if (_activeConversation != null &&
            (convId.isEmpty || convId == _activeConversation!.conversationId)) {
          if (payload['publicKeys'] is Map) {
            final newKeys = <String, String>{};
            (payload['publicKeys'] as Map).forEach((k, v) {
              if (v != null) newKeys[k.toString()] = v.toString();
            });
            _messengerService.cacheKeys(_activeConversation!.conversationId, newKeys);
            final merged = Map<String, String>.from(_activeConversation!.publicKeys)..addAll(newKeys);
            _activeConversation = _activeConversation!.copyWith(publicKeys: merged);
          }
          await _setupE2eForConversation(_activeConversation!);

          // Real-time WhatsApp-like in-place read receipt updates (grey ticks -> blue ticks)
          if (payload['action'] == 'read') {
            final readUserId = (payload['userId'] ?? '').toString();
            if (readUserId.isNotEmpty && mounted) {
              setState(() {
                _directMessages = _directMessages.map<DirectMessageModel>((m) {
                  if (!m.readBy.contains(readUserId)) {
                    return m.copyWith(readBy: [...m.readBy, readUserId]);
                  }
                  return m;
                }).toList();
              });
            }
          }

          // Real-time instant decryption & append for zero latency
          final rawMsg = payload['message'];
          if (rawMsg is Map && payload['action'] == 'create') {
            final incomingMsg = DirectMessageModel.fromJson(Map<String, dynamic>.from(rawMsg));
            if (!_directMessages.any((m) => m.id == incomingMsg.id)) {
              DirectMessageModel decryptedMsg = incomingMsg;
              if (incomingMsg.encrypted && incomingMsg.iv.isNotEmpty) {
                SecretKey? keyToUse = _activeSharedKey;
                if (keyToUse == null) {
                  await _setupE2eForConversation(_activeConversation!);
                  keyToUse = _activeSharedKey;
                }
                if (keyToUse != null) {
                  final plain = await E2eCryptoService.decryptMessage(keyToUse, incomingMsg.content, incomingMsg.iv);
                  if (plain != '🔒 Unable to decrypt') {
                    decryptedMsg = incomingMsg.copyWith(decryptedContent: plain);
                  } else {
                    decryptedMsg = incomingMsg.copyWith(decryptedContent: '🔒 Encrypted message');
                  }
                } else {
                  decryptedMsg = incomingMsg.copyWith(decryptedContent: '🔒 Encrypted message');
                }
              }
              if (mounted) {
                setState(() => _directMessages.add(decryptedMsg));
                _scrollToBottom();
              }
            }
          }
          await _refreshActiveDmMessages();
        }
        _refreshConversations();
      }),
      socket.onDmKeyExchange.listen((payload) async {
        final convId = (payload['conversationId'] ?? '').toString();
        if (_activeConversation != null && convId == _activeConversation!.conversationId) {
          final newKeys = <String, String>{};
          if (payload['publicKeys'] is Map) {
            (payload['publicKeys'] as Map).forEach((k, v) {
              if (v != null) newKeys[k.toString()] = v.toString();
            });
          }
          if (payload['userId'] != null && payload['publicKey'] != null) {
            newKeys[payload['userId'].toString()] = payload['publicKey'].toString();
          }
          if (newKeys.isNotEmpty) {
            _messengerService.cacheKeys(convId, newKeys);
            final merged = Map<String, String>.from(_activeConversation!.publicKeys)..addAll(newKeys);
            _activeConversation = _activeConversation!.copyWith(publicKeys: merged);
          }
          await _setupE2eForConversation(_activeConversation!);
          await _refreshActiveDmMessages();
        }
        _refreshConversations();
      }),
      socket.onPresenceUpdate.listen((payload) {
        final uid = (payload['userId'] ?? '').toString();
        final online = payload['online'] == true;
        final lastActive = payload['lastActive']?.toString();
        if (uid.isEmpty || !mounted) return;
        setState(() {
          _contacts = _contacts
              .map((c) => c.userId == uid ? c.copyWith(online: online, lastActive: lastActive) : c)
              .toList();
          _conversations = _conversations
              .map((c) => (!c.isGroup && c.otherUserId == uid)
                  ? c.copyWith(otherUserOnline: online)
                  : c)
              .toList();
          if (_activeConversation != null &&
              !_activeConversation!.isGroup &&
              _activeConversation!.otherUserId == uid) {
            _activeConversation = _activeConversation!.copyWith(otherUserOnline: online);
          }
        });
      }),
    ]);
  }

  Future<void> _loadMessengerData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _showTeamChannelTab
            ? _messengerService.getTeamMessages(user: widget.user)
            : Future.value(<TeamMessageModel>[]),
        _messengerService.getConversations(user: widget.user),
        _loadAuthorizedContacts(),
      ]);
      if (!mounted) return;
      setState(() {
        _teamMessages = results[0] as List<TeamMessageModel>;
        _conversations = results[1] as List<DmConversationModel>;
        _contacts = results[2] as List<MessengerContactModel>;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<List<MessengerContactModel>> _loadAuthorizedContacts() async {
    final serverContacts = await _messengerService.getAuthorizedContacts(user: widget.user);
    if (serverContacts.isNotEmpty) {
      return serverContacts.where((c) => c.userId != _myUserId).toList();
    }

    try {
      final rawUsers = await _dashboardService.getUsers(isSuperAdmin: widget.user.isSuperAdmin);
      return rawUsers
          .where((u) {
            final uid = u.userId.isNotEmpty ? u.userId : u.id;
            if (uid.isEmpty || uid == _myUserId) return false;
            final role = u.role.toLowerCase();
            if (widget.user.isSuperAdmin) {
              return role == 'owner' || role == 'admin';
            }
            if (widget.user.companyId != null &&
                widget.user.companyId!.isNotEmpty &&
                u.companyId != null &&
                u.companyId!.isNotEmpty) {
              return u.companyId == widget.user.companyId;
            }
            return true;
          })
          .map(
            (u) => MessengerContactModel(
              id: u.id,
              userId: u.userId.isNotEmpty ? u.userId : u.id,
              username: u.username,
              name: u.name.isNotEmpty ? u.name : u.username,
              role: u.role,
              companyId: u.companyId,
              company: u.company ?? '',
              designation: u.designation ?? '',
              department: u.department ?? '',
              avatar: u.avatar ?? '',
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _refreshTeamMessages() async {
    final msgs = await _messengerService.getTeamMessages(user: widget.user);
    if (mounted) {
      setState(() => _teamMessages = msgs);
      _scrollToBottom();
    }
  }

  Future<void> _refreshConversations() async {
    final convos = await _messengerService.getConversations(user: widget.user);
    if (mounted) {
      setState(() => _conversations = convos);
    }
  }

  Future<void> _refreshActiveDmMessages() async {
    final conv = _activeConversation;
    if (conv == null) return;
    final freshKeys = _messengerService.getCachedKeys(conv.conversationId);
    if (freshKeys != null && freshKeys.isNotEmpty) {
      final merged = Map<String, String>.from(conv.publicKeys)..addAll(freshKeys);
      _activeConversation = conv.copyWith(publicKeys: merged);
      if (_activeSharedKey == null) {
        await _setupE2eForConversation(_activeConversation!);
      }
    }
    final raw = await _messengerService.getDirectMessages(
      user: widget.user,
      conversationId: conv.conversationId,
    );
    final decrypted = await _decryptMessageList(raw, _activeSharedKey);
    if (mounted) {
      setState(() => _directMessages = decrypted);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // E2E ENCRYPTION & MESSAGING ACTIONS
  // ═══════════════════════════════════════════════════════════════

  String? _findMyKeyOnServer(DmConversationModel conv) {
    final myCandidates = <String>{
      _myUserId.trim().toLowerCase(),
      widget.user.userId.trim().toLowerCase(),
      widget.user.username.trim().toLowerCase(),
      widget.user.id.trim().toLowerCase(),
    }..removeWhere((s) => s.isEmpty);

    for (final entry in conv.publicKeys.entries) {
      if (myCandidates.contains(entry.key.trim().toLowerCase()) && entry.value.trim().isNotEmpty) {
        return entry.value;
      }
    }
    return null;
  }

  String? _resolvePeerPublicKey(DmConversationModel conv) {
    final myCandidates = <String>{
      _myUserId.trim().toLowerCase(),
      widget.user.userId.trim().toLowerCase(),
      widget.user.username.trim().toLowerCase(),
      widget.user.id.trim().toLowerCase(),
    }..removeWhere((s) => s.isEmpty);

    final peerCandidates = <String>{
      conv.otherUserId.trim().toLowerCase(),
      conv.otherUserName.trim().toLowerCase(),
    }..removeWhere((s) => s.isEmpty);

    final contact = _findContactById(conv.otherUserId);
    if (contact != null) {
      if (contact.userId.trim().isNotEmpty) peerCandidates.add(contact.userId.trim().toLowerCase());
      if (contact.username.trim().isNotEmpty) peerCandidates.add(contact.username.trim().toLowerCase());
      if (contact.id.trim().isNotEmpty) peerCandidates.add(contact.id.trim().toLowerCase());
    }

    // 1. Direct match with peerCandidates
    for (final entry in conv.publicKeys.entries) {
      if (peerCandidates.contains(entry.key.trim().toLowerCase()) && entry.value.trim().isNotEmpty) {
        return entry.value;
      }
    }

    // 2. In 1-on-1 conversations, ANY key that is NOT mine is the peer's key!
    if (!conv.isGroup) {
      for (final entry in conv.publicKeys.entries) {
        if (!myCandidates.contains(entry.key.trim().toLowerCase()) && entry.value.trim().isNotEmpty) {
          return entry.value;
        }
      }
    }

    return null;
  }

  bool _keysMatch(String? a, String? b) {
    if (a == null || b == null) return false;
    if (a.trim() == b.trim()) return true;
    try {
      dynamic ma = jsonDecode(a);
      if (ma is String) ma = jsonDecode(ma);
      dynamic mb = jsonDecode(b);
      if (mb is String) mb = jsonDecode(mb);
      if (ma is Map && mb is Map) {
        return ma['x'] == mb['x'] && ma['y'] == mb['y'];
      }
    } catch (_) {}
    return false;
  }

  Future<void> _setupE2eForConversation(DmConversationModel conv) async {
    if (conv.isGroup) {
      if (mounted) {
        setState(() {
          _activeSharedKey = null;
          _e2eActive = false;
        });
      }
      return;
    }

    try {
      String? activeLocalPub;
      // 1. First check if server has our persistent keypair for this conversation
      final serverMyKey = await _messengerService.getUserConversationKey(
        user: widget.user,
        conversationId: conv.conversationId,
      );
      if (serverMyKey.privateKey != null && serverMyKey.privateKey!.isNotEmpty) {
        await E2eCryptoService.storeImportedPrivateKey(
          conv.conversationId,
          serverMyKey.privateKey!,
          userId: _myUserId,
        );
        activeLocalPub = serverMyKey.publicKey ??
            await E2eCryptoService.getStoredPublicKey(conv.conversationId, userId: _myUserId);
      } else {
        // Fall back to local keypair or generate a new persistent keypair
        final hasLocal = await E2eCryptoService.hasKeyPair(conv.conversationId, userId: _myUserId);
        if (hasLocal) {
          activeLocalPub = await E2eCryptoService.getStoredPublicKey(conv.conversationId, userId: _myUserId);
        } else {
          activeLocalPub = await E2eCryptoService.generateKeyPair(conv.conversationId, userId: _myUserId);
        }
        final priv = await E2eCryptoService.getStoredPrivateKey(conv.conversationId, userId: _myUserId);
        if (priv != null && activeLocalPub != null) {
          await _messengerService.storeUserConversationKey(
            user: widget.user,
            conversationId: conv.conversationId,
            privateKeyJwkJson: priv,
            publicKeyJwkJson: activeLocalPub,
          );
        }
      }

      final myKeyOnServer = _findMyKeyOnServer(conv);
      if (activeLocalPub != null && activeLocalPub.isNotEmpty) {
        // Always ensure server has our current active public key so peers never encrypt with outdated keys
        if (myKeyOnServer == null || !_keysMatch(myKeyOnServer, activeLocalPub)) {
          await _messengerService.storePublicKey(
            user: widget.user,
            conversationId: conv.conversationId,
            publicKeyJwkJson: activeLocalPub,
          );
          final updatedKeys = Map<String, String>.from(conv.publicKeys)..[_myUserId] = activeLocalPub;
          conv = conv.copyWith(publicKeys: updatedKeys);
          if (mounted && _activeConversation?.conversationId == conv.conversationId) {
            _activeConversation = conv;
          }
        }
      }

      var peerPub = _resolvePeerPublicKey(conv);
      if (peerPub == null || peerPub.isEmpty) {
        // Fetch fresh keys from server if not found in conversation model
        final freshKeys = await _messengerService.getConversationKeys(
          user: widget.user,
          conversationId: conv.conversationId,
        );
        if (freshKeys.isNotEmpty) {
          final merged = Map<String, String>.from(conv.publicKeys)..addAll(freshKeys);
          conv = conv.copyWith(publicKeys: merged);
          if (mounted && _activeConversation?.conversationId == conv.conversationId) {
            _activeConversation = conv;
          }
          peerPub = _resolvePeerPublicKey(conv);
        }
      }

      if (peerPub != null && peerPub.isNotEmpty) {
        final shared = await E2eCryptoService.deriveSharedKey(
          conv.conversationId,
          peerPub,
          userId: _myUserId,
        );
        if (mounted) {
          setState(() {
            _activeSharedKey = shared;
            _e2eActive = shared != null;
          });
          if (shared != null && _directMessages.isNotEmpty) {
            final decrypted = await _decryptMessageList(_directMessages, shared);
            if (mounted) setState(() => _directMessages = decrypted);
          }
        }
      } else if (mounted) {
        setState(() {
          _activeSharedKey = null;
          _e2eActive = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _activeSharedKey = null;
          _e2eActive = false;
        });
      }
    }
  }

  Future<List<DirectMessageModel>> _decryptMessageList(
    List<DirectMessageModel> list,
    SecretKey? key,
  ) async {
    final out = <DirectMessageModel>[];
    SecretKey? effectiveKey = key ?? _activeSharedKey;

    if (effectiveKey == null && _activeConversation != null && !_activeConversation!.isGroup) {
      var peerPub = _resolvePeerPublicKey(_activeConversation!);
      if (peerPub == null || peerPub.isEmpty) {
        final freshKeys = await _messengerService.getConversationKeys(
          user: widget.user,
          conversationId: _activeConversation!.conversationId,
        );
        if (freshKeys.isNotEmpty) {
          final merged = Map<String, String>.from(_activeConversation!.publicKeys)..addAll(freshKeys);
          _activeConversation = _activeConversation!.copyWith(publicKeys: merged);
          peerPub = _resolvePeerPublicKey(_activeConversation!);
        }
      }
      if (peerPub != null && peerPub.isNotEmpty) {
        effectiveKey = await E2eCryptoService.deriveSharedKey(
          _activeConversation!.conversationId,
          peerPub,
          userId: _myUserId,
        );
        if (effectiveKey != null && mounted) {
          _activeSharedKey = effectiveKey;
          _e2eActive = true;
        }
      }
    }

    bool didRetryKeyFetch = false;
    for (final m in list) {
      if (!m.encrypted || m.iv.isEmpty) {
        out.add(m);
        continue;
      }
      if (effectiveKey == null) {
        out.add(m.copyWith(decryptedContent: '🔒 Encrypted message'));
        continue;
      }
      var plain = await E2eCryptoService.decryptMessage(effectiveKey, m.content, m.iv);
      if (plain == '🔒 Unable to decrypt' && !didRetryKeyFetch && _activeConversation != null && !_activeConversation!.isGroup) {
        didRetryKeyFetch = true;
        final freshKeys = await _messengerService.getConversationKeys(
          user: widget.user,
          conversationId: _activeConversation!.conversationId,
        );
        if (freshKeys.isNotEmpty) {
          final merged = Map<String, String>.from(_activeConversation!.publicKeys)..addAll(freshKeys);
          _activeConversation = _activeConversation!.copyWith(publicKeys: merged);
          final freshPeerPub = _resolvePeerPublicKey(_activeConversation!);
          if (freshPeerPub != null && freshPeerPub.isNotEmpty) {
            final freshShared = await E2eCryptoService.deriveSharedKey(
              _activeConversation!.conversationId,
              freshPeerPub,
              userId: _myUserId,
            );
            if (freshShared != null) {
              effectiveKey = freshShared;
              if (mounted) {
                _activeSharedKey = freshShared;
                _e2eActive = true;
              }
              plain = await E2eCryptoService.decryptMessage(effectiveKey, m.content, m.iv);
            }
          }
        }
      }

      if (plain == '🔒 Unable to decrypt') {
        out.add(m.copyWith(decryptedContent: '🔒 Encrypted message'));
      } else {
        out.add(m.copyWith(decryptedContent: plain));
      }
    }
    return out;
  }

  void _closeActiveConversation() {
    if (_activeConversation != null) {
      MessengerSocketService.instance.emit('dm:leave-conversation', {
        'conversationId': _activeConversation!.conversationId,
      });
    }
    setState(() {
      _activeConversation = null;
      _activeSharedKey = null;
      _e2eActive = false;
    });
    _notifyChatState();
  }

  Future<void> _openConversation(DmConversationModel conv) async {
    final cached = _messengerService.getCachedKeys(conv.conversationId);
    if (cached != null && cached.isNotEmpty) {
      final merged = Map<String, String>.from(conv.publicKeys)..addAll(cached);
      conv = conv.copyWith(publicKeys: merged);
    }

    setState(() {
      _activeConversation = conv;
      _isLoadingDm = true;
      _activeSharedKey = null;
      _e2eActive = false;
    });
    MessengerSocketService.instance.emit('dm:join-conversation', {'conversationId': conv.conversationId});
    _notifyChatState();

    await _setupE2eForConversation(conv);
    final rawMsgs = await _messengerService.getDirectMessages(
      user: widget.user,
      conversationId: conv.conversationId,
    );

    final freshKeys = _messengerService.getCachedKeys(conv.conversationId);
    if (freshKeys != null && freshKeys.isNotEmpty) {
      final merged = Map<String, String>.from(conv.publicKeys)..addAll(freshKeys);
      conv = conv.copyWith(publicKeys: merged);
      if (mounted) setState(() => _activeConversation = conv);
      if (_activeSharedKey == null) {
        await _setupE2eForConversation(conv);
      }
    }

    final msgs = await _decryptMessageList(rawMsgs, _activeSharedKey);

    _messengerService.markConversationRead(
      user: widget.user,
      conversationId: conv.conversationId,
    );

    if (!mounted) return;
    setState(() {
      _directMessages = msgs;
      _isLoadingDm = false;
      _conversations = _conversations
          .map((c) => c.conversationId == conv.conversationId ? c.copyWith(unreadCount: 0) : c)
          .toList();
    });
    _scrollToBottom();
  }

  Future<void> _handleSendText({String? overrideText}) async {
    final text = (overrideText ?? _messageController.text).trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    try {
      if (_activeTab == 1 && _showTeamChannelTab) {
        final sent = await _messengerService.sendTeamMessage(
          user: widget.user,
          content: text,
        );
        if (mounted) {
          if (overrideText == null) _messageController.clear();
          setState(() {
            _teamMessages.add(
              sent ??
                  TeamMessageModel(
                    id: 'local-${DateTime.now().millisecondsSinceEpoch}',
                    messageId: 'local-${DateTime.now().millisecondsSinceEpoch}',
                    senderId: _myUserId,
                    senderName: widget.user.name.isNotEmpty
                        ? widget.user.name
                        : widget.user.username,
                    content: text,
                    timestamp: DateTime.now().toIso8601String(),
                  ),
            );
            _isSending = false;
          });
          _scrollToBottom();
        }
      } else if (_activeConversation != null) {
        String contentToSend = text;
        bool encrypted = false;
        String iv = '';

        if (_activeSharedKey != null && _e2eActive) {
          try {
            final enc = await E2eCryptoService.encryptMessage(_activeSharedKey!, text);
            contentToSend = enc.ciphertext;
            encrypted = true;
            iv = enc.iv;
          } catch (_) {
            contentToSend = text;
            encrypted = false;
            iv = '';
          }
        }

        final sent = await _messengerService.sendDirectMessage(
          user: widget.user,
          conversationId: _activeConversation!.conversationId,
          content: contentToSend,
          encrypted: encrypted,
          iv: iv,
        );
        if (mounted) {
          if (overrideText == null) _messageController.clear();
          final msgToDisplay = (sent ??
                  DirectMessageModel(
                    id: 'local-dm-${DateTime.now().millisecondsSinceEpoch}',
                    conversationId: _activeConversation!.conversationId,
                    senderId: _myUserId,
                    senderName: widget.user.name.isNotEmpty
                        ? widget.user.name
                        : widget.user.username,
                    content: contentToSend,
                    iv: iv,
                    encrypted: encrypted,
                    timestamp: DateTime.now().toIso8601String(),
                  ))
              .copyWith(decryptedContent: text);
          setState(() {
            _directMessages.add(msgToDisplay);
            _isSending = false;
          });
          _scrollToBottom();
        }
      } else {
        if (mounted) setState(() => _isSending = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _handleOpenVoiceRecorder() async {
    final result = await VoiceRecorderSheet.show(context);
    if (result == null || !mounted) return;

    switch (result.action) {
      case VoiceSendAction.discard:
        return;
      case VoiceSendAction.editInChat:
        _messageController.text = result.transcript;
        _messageController.selection = TextSelection.fromPosition(
          TextPosition(offset: _messageController.text.length),
        );
        return;
      case VoiceSendAction.sendText:
        await _handleSendText(overrideText: result.transcript);
        return;
      case VoiceSendAction.sendVoice:
        if (result.base64DataUri == null) return;
        await _sendVoiceAttachment(result);
        return;
    }
  }

  Future<void> _sendVoiceAttachment(VoiceCaptureResult voice) async {
    if (_isSending) return;
    setState(() => _isSending = true);

    final attachment = <String, dynamic>{
      'name': voice.fileName ?? 'voice-${DateTime.now().millisecondsSinceEpoch}.m4a',
      'type': voice.mimeType ?? 'audio/mp4',
      'size': voice.fileSize,
      'duration': voice.durationSeconds,
      if (voice.transcript.isNotEmpty) 'transcript': voice.transcript,
      'data': voice.base64DataUri,
      'path': voice.base64DataUri,
    };

    try {
      if (_activeTab == 1 && _showTeamChannelTab) {
        final sent = await _messengerService.sendTeamMessage(
          user: widget.user,
          content: '🎤 Voice message',
          attachments: [attachment],
        );
        if (mounted) {
          if (sent != null) setState(() => _teamMessages.add(sent));
          setState(() => _isSending = false);
          _scrollToBottom();
        }
      } else if (_activeConversation != null) {
        final sent = await _messengerService.sendDirectMessage(
          user: widget.user,
          conversationId: _activeConversation!.conversationId,
          content: '🎤 Voice message',
          isVoice: true,
          attachments: [attachment],
        );
        if (mounted) {
          if (sent != null) setState(() => _directMessages.add(sent));
          setState(() => _isSending = false);
          _scrollToBottom();
        }
      } else {
        if (mounted) setState(() => _isSending = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _handleOpenMediaPicker() async {
    final picked = await MessengerMediaPicker.showAttachPickerSheet(context);
    if (picked == null || !mounted) return;
    await _sendPickedMedia(picked);
  }

  Future<void> _handleRecordVideo() async {
    final recorded = await MessengerMediaPicker.recordVideo(context);
    if (recorded == null || !mounted) return;
    await _sendPickedMedia(recorded);
  }

  Future<void> _sendPickedMedia(PickedMediaAttachment media) async {
    if (_isSending) return;
    setState(() => _isSending = true);

    final attPayload = media.toBackendAttachment();
    final contentText = media.defaultMessageText;

    try {
      if (_activeTab == 1 && _showTeamChannelTab) {
        final sent = await _messengerService.sendTeamMessage(
          user: widget.user,
          content: contentText,
          attachments: [attPayload],
        );
        if (mounted) {
          if (sent != null) {
            setState(() => _teamMessages.add(sent));
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                backgroundColor: CeladonColors.error,
                content: Text('Failed to upload attachment. Please check your connection.'),
              ),
            );
          }
          setState(() => _isSending = false);
          _scrollToBottom();
        }
      } else if (_activeConversation != null) {
        final sent = await _messengerService.sendDirectMessage(
          user: widget.user,
          conversationId: _activeConversation!.conversationId,
          content: contentText,
          isVoice: false,
          attachments: [attPayload],
        );
        if (mounted) {
          if (sent != null) {
            setState(() => _directMessages.add(sent));
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                backgroundColor: CeladonColors.error,
                content: Text('Failed to upload attachment. Please check your connection.'),
              ),
            );
          }
          setState(() => _isSending = false);
          _scrollToBottom();
        }
      } else {
        if (mounted) setState(() => _isSending = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _startNewChatWith(MessengerContactModel contact) async {
    // 1. Instant open if conversation already exists in memory
    final existing = _conversations.where((c) {
      if (c.isGroup) return false;
      final peerId = _resolvePeerId(c).toLowerCase();
      final target = contact.userId.trim().toLowerCase();
      final alt = contact.username.trim().toLowerCase();
      final other = c.otherUserId.trim().toLowerCase();
      return peerId == target || peerId == alt || other == target || other == alt;
    }).firstOrNull;

    if (existing != null) {
      await _openConversation(existing);
      return;
    }

    final conv = await _messengerService.getOrCreateConversation(
      user: widget.user,
      recipientId: contact.userId,
    );
    if (!mounted) return;
    if (conv != null) {
      final hydrated = DmConversationModel(
        conversationId: conv.conversationId,
        participants: conv.participants,
        isGroup: conv.isGroup,
        name: conv.name,
        scope: conv.scope,
        createdBy: conv.createdBy,
        otherUserId: contact.userId,
        otherUserName: contact.displayName,
        otherUserRole: contact.role,
        otherUserOnline: contact.online,
        lastMessage: conv.lastMessage,
        lastTimestamp: conv.lastTimestamp,
        unreadCount: conv.unreadCount,
        publicKeys: conv.publicKeys,
        participantDetails: conv.participantDetails,
      );
      if (!_conversations.any((c) => c.conversationId == hydrated.conversationId)) {
        setState(() => _conversations.insert(0, hydrated));
      }
      await _openConversation(hydrated);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: CeladonColors.error,
          content: Text('Unable to start conversation. Access may be restricted by role.'),
        ),
      );
    }
  }


  // ═══════════════════════════════════════════════════════════════
  // MODALS: NEW CHAT, CREATE GROUP, GROUP MEMBERS, EDIT/DELETE
  // ═══════════════════════════════════════════════════════════════

  void _showStartDmSheet() {
    String modalSearch = '';
    List<MessengerContactModel> modalContacts = List.from(_contacts);
    bool isFetchingFresh = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: CeladonColors.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          if (isFetchingFresh) {
            _loadAuthorizedContacts().then((fresh) {
              if (ctx.mounted) {
                setModalState(() {
                  modalContacts = fresh;
                  isFetchingFresh = false;
                });
              }
              if (mounted) {
                setState(() => _contacts = fresh);
              }
            }).catchError((_) {
              if (ctx.mounted) {
                setModalState(() => isFetchingFresh = false);
              }
            });
          }

          final filtered = modalContacts.where((c) {
            if (modalSearch.trim().isEmpty) return true;
            final q = modalSearch.toLowerCase();
            return c.displayName.toLowerCase().contains(q) ||
                c.company.toLowerCase().contains(q) ||
                c.roleLabel.toLowerCase().contains(q) ||
                c.department.toLowerCase().contains(q) ||
                c.designation.toLowerCase().contains(q);
          }).toList();

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                14,
                20,
                18 + MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        widget.user.isSuperAdmin
                            ? 'Message Company Owner'
                            : 'New Conversation',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: CeladonColors.textPrimary,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showCreateGroupSheet();
                        },
                        icon: const Icon(Icons.group_add_rounded, size: 17),
                        label: const Text('New Group', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    onChanged: (v) => setModalState(() => modalSearch = v),
                    decoration: InputDecoration(
                      hintText: widget.user.isSuperAdmin
                          ? 'Search company owners or admins...'
                          : 'Search employees by name...',
                      hintStyle: const TextStyle(fontSize: 13.5, color: Color(0xFF64748B)),
                      prefixIcon: const Icon(Icons.search_rounded, size: 19, color: Color(0xFF64748B)),
                      isDense: true,
                      filled: true,
                      fillColor: _searchFill,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (filtered.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 28),
                      child: Center(
                        child: Text(
                          'No authorized contacts found.',
                          style: TextStyle(fontSize: 13.5, color: CeladonColors.textSecondary),
                        ),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 350),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, indent: 60, color: _subtleDivider),
                        itemBuilder: (_, i) {
                          final person = filtered[i];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                            leading: _buildAvatar(
                              name: person.displayName,
                              online: person.online,
                            ),
                            title: Text(
                              person.displayName,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: CeladonColors.textPrimary,
                              ),
                            ),
                            subtitle: Text(
                              person.company.isNotEmpty
                                  ? '${person.roleLabel} • ${person.company}'
                                  : person.roleLabel,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF64748B),
                              ),
                            ),
                            trailing: const Icon(
                              Icons.chevron_right_rounded,
                              size: 20,
                              color: Color(0xFF94A3B8),
                            ),
                            onTap: () {
                              Navigator.pop(ctx);
                              _startNewChatWith(person);
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showCreateGroupSheet() {
    final nameCtrl = TextEditingController();
    final selectedIds = <String>{};
    String search = '';
    List<MessengerContactModel> modalContacts = List.from(_contacts);
    bool isFetchingFresh = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: CeladonColors.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          if (isFetchingFresh) {
            _loadAuthorizedContacts().then((fresh) {
              if (ctx.mounted) {
                setModalState(() {
                  modalContacts = fresh;
                  isFetchingFresh = false;
                });
              }
              if (mounted) {
                setState(() => _contacts = fresh);
              }
            }).catchError((_) {
              if (ctx.mounted) {
                setModalState(() => isFetchingFresh = false);
              }
            });
          }

          final filtered = modalContacts.where((c) {
            if (search.trim().isEmpty) return true;
            final q = search.toLowerCase();
            return c.displayName.toLowerCase().contains(q) ||
                c.company.toLowerCase().contains(q) ||
                c.roleLabel.toLowerCase().contains(q);
          }).toList();

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                14,
                20,
                18 + MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        widget.user.isSuperAdmin
                            ? 'Create Owners Group'
                            : 'New Group Chat',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: CeladonColors.textPrimary,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Group Name',
                      hintText: widget.user.isSuperAdmin
                          ? 'e.g. Company Owners Council'
                          : 'e.g. Project Delivery Team',
                      isDense: true,
                      filled: true,
                      fillColor: _searchFill,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    onChanged: (v) => setModalState(() => search = v),
                    decoration: InputDecoration(
                      hintText: 'Search members (${selectedIds.length} selected)...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      isDense: true,
                      filled: true,
                      fillColor: _searchFill,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final person = filtered[i];
                        final checked = selectedIds.contains(person.userId);
                        return CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          activeColor: CeladonColors.primary,
                          value: checked,
                          title: Text(
                            person.displayName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: CeladonColors.textPrimary,
                            ),
                          ),
                          subtitle: Text(
                            person.company.isNotEmpty
                                ? '${person.roleLabel} • ${person.company}'
                                : person.roleLabel,
                            style: const TextStyle(fontSize: 11.5),
                          ),
                          onChanged: (val) {
                            setModalState(() {
                              if (val == true) {
                                selectedIds.add(person.userId);
                              } else {
                                selectedIds.remove(person.userId);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: CeladonColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () async {
                      final groupName = nameCtrl.text.trim();
                      if (groupName.isEmpty || selectedIds.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Enter a group name and select at least 1 member.'),
                          ),
                        );
                        return;
                      }
                      Navigator.pop(ctx);
                      final created = await _messengerService.createGroupConversation(
                        user: widget.user,
                        name: groupName,
                        participantIds: selectedIds.toList(),
                      );
                      if (!mounted) return;
                      if (created != null) {
                        await _refreshConversations();
                        final full = _conversations
                                .where((c) => c.conversationId == created.conversationId)
                                .firstOrNull ??
                            created;
                        await _openConversation(full);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            backgroundColor: CeladonColors.error,
                            content: Text('Could not create group conversation.'),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.group_add_rounded, size: 18),
                    label: const Text(
                      'Create Group',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showGroupMembersSheet(DmConversationModel conv) {
    showModalBottomSheet(
      context: context,
      backgroundColor: CeladonColors.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '${conv.displayTitle} (${conv.participants.length})',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: CeladonColors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: conv.participantDetails.isNotEmpty
                      ? conv.participantDetails.length
                      : conv.participants.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, indent: 56, color: _subtleDivider),
                  itemBuilder: (_, i) {
                    if (conv.participantDetails.isNotEmpty) {
                      final p = conv.participantDetails[i];
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: _buildAvatar(name: p.displayName, online: p.online),
                        title: Text(
                          p.userId == _myUserId ? '${p.displayName} (You)' : p.displayName,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                        subtitle: Text(
                          p.company.isNotEmpty ? '${p.roleLabel} • ${p.company}' : p.roleLabel,
                          style: const TextStyle(fontSize: 11.5),
                        ),
                      );
                    }
                    final pid = conv.participants[i];
                    final resolved = _resolveSenderName(pid, pid);
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: _buildAvatar(name: resolved, online: false),
                      title: Text(pid == _myUserId ? '$resolved (You)' : resolved),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMessageOptions({
    required bool isTeam,
    required String id,
    required String currentContent,
    required bool isMine,
  }) {
    if (!isMine && !widget.user.isCompanyAdmin && !widget.user.isSuperAdmin) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: CeladonColors.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isMine && !currentContent.startsWith('🎤'))
              ListTile(
                leading: const Icon(Icons.edit_rounded, color: CeladonColors.primary),
                title: const Text('Edit Message', style: TextStyle(fontWeight: FontWeight.w700)),
                onTap: () {
                  Navigator.pop(ctx);
                  _promptEditMessage(isTeam: isTeam, id: id, initial: currentContent);
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: CeladonColors.error),
              title: const Text(
                'Delete Message',
                style: TextStyle(fontWeight: FontWeight.w700, color: CeladonColors.error),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                if (isTeam) {
                  final ok = await _messengerService.deleteTeamMessage(
                    user: widget.user,
                    messageId: id,
                  );
                  if (ok && mounted) {
                    setState(() => _teamMessages.removeWhere((m) => m.id == id || m.messageId == id));
                  }
                } else {
                  final ok = await _messengerService.deleteDirectMessage(
                    user: widget.user,
                    messageId: id,
                  );
                  if (ok && mounted) {
                    setState(() => _directMessages.removeWhere((m) => m.id == id));
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _promptEditMessage({
    required bool isTeam,
    required String id,
    required String initial,
  }) async {
    final ctrl = TextEditingController(text: initial);
    final updated = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Message'),
        content: TextField(controller: ctrl, maxLines: 3, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: CeladonColors.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (updated == null || updated.isEmpty || !mounted) return;

    if (isTeam) {
      final res = await _messengerService.editTeamMessage(
        user: widget.user,
        messageId: id,
        content: updated,
      );
      if (res != null && mounted) _refreshTeamMessages();
    } else {
      String payload = updated;
      bool enc = false;
      String iv = '';
      if (_activeConversation != null &&
          !_activeConversation!.isGroup &&
          _e2eActive &&
          _activeSharedKey != null) {
        final e = await E2eCryptoService.encryptMessage(_activeSharedKey!, updated);
        payload = e.ciphertext;
        iv = e.iv;
        enc = true;
      }
      final res = await _messengerService.editDirectMessage(
        user: widget.user,
        messageId: id,
        content: payload,
        encrypted: enc,
        iv: iv,
      );
      if (res != null && mounted) _refreshActiveDmMessages();
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // UI HELPERS & PROFESSIONAL VISUAL COMPONENTS
  // ═══════════════════════════════════════════════════════════════

  String _formatTime(String raw) {
    if (raw.isEmpty) return '';
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return '';
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final min = dt.minute.toString().padLeft(2, '0');
    final suffix = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$min $suffix';
  }

  String _initialsFromName(String name) {
    final cleaned = name.trim();
    if (cleaned.isEmpty) return 'U';
    final parts = cleaned.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return cleaned[0].toUpperCase();
  }

  Color _avatarTintForName(String name) {
    const palette = [
      Color(0xFF1B5E4B),
      Color(0xFF0F766E),
      Color(0xFF1E40AF),
      Color(0xFF6D28D9),
      Color(0xFF047857),
      Color(0xFFB45309),
    ];
    final hash = name.codeUnits.fold<int>(0, (acc, c) => acc + c);
    return palette[hash % palette.length];
  }

  Widget _buildAvatar({
    required String name,
    required bool online,
    bool isGroup = false,
    double radius = 23,
  }) {
    final tint = isGroup ? CeladonColors.primary : _avatarTintForName(name);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: radius * 2,
          height: radius * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                tint.withValues(alpha: 0.16),
                tint.withValues(alpha: 0.08),
              ],
            ),
            border: Border.all(color: tint.withValues(alpha: 0.2), width: 1),
          ),
          alignment: Alignment.center,
          child: isGroup
              ? Icon(Icons.groups_rounded, color: tint, size: radius * 0.95)
              : Text(
                  _initialsFromName(name),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: tint,
                    fontSize: radius * 0.66,
                    letterSpacing: -0.2,
                  ),
                ),
        ),
        // Show clean emerald online dot ONLY when user is actively online
        if (!isGroup && online)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTopTabs() {
    final totalUnread = _conversations.fold<int>(0, (sum, c) => sum + c.unreadCount);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2ECE7)),
        ),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() => _activeTab = 0);
                  _notifyChatState();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: _activeTab == 0 ? CeladonColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 16,
                        color: _activeTab == 0 ? Colors.white : CeladonColors.textPrimary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        totalUnread > 0 ? 'Chats ($totalUnread)' : 'Chats',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _activeTab == 0 ? Colors.white : CeladonColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _activeTab = 1;
                    _activeConversation = null;
                  });
                  _notifyChatState();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: _activeTab == 1 ? CeladonColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.people_alt_rounded,
                        size: 16,
                        color: _activeTab == 1 ? Colors.white : CeladonColors.textPrimary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Team Channel',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _activeTab == 1 ? Colors.white : CeladonColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBodyContent() {
    // When inside an active 1:1 or Group conversation, give full vertical room to the chat thread
    if (_activeTab == 0 && _activeConversation != null) {
      return _buildActiveDmView(_activeConversation!);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Rounded Pill Segmented Tabs (Chats | Team Channel)
        if (_showTeamChannelTab) _buildTopTabs(),

        // Main Content
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: CeladonColors.primary),
                )
              : (_activeTab == 1 && _showTeamChannelTab)
                  ? _buildTeamChatView()
                  : _buildConversationsListView(),
        ),
      ],
    );
  }

  Widget _buildConversationsListView() {
    final q = _searchQuery.trim().toLowerCase();
    final filteredConvos = _conversations.where((c) {
      if (_chatFilterIndex == 1 && c.unreadCount <= 0) {
        return false;
      }
      if (_chatFilterIndex == 2 && !c.isGroup) {
        return false;
      }
      if (q.isNotEmpty) {
        final resolvedName = _resolveConversationName(c).toLowerCase();
        final matchesName = resolvedName.contains(q);
        final matchesMessage = c.lastMessage.toLowerCase().contains(q);
        if (!matchesName && !matchesMessage) return false;
      }
      return true;
    }).toList();

    return Container(
      color: CeladonColors.background,
      child: Column(
        children: [
          // Sleek Full-Width Search Bar: strictly searches already messaged people/chats and text
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFFE2ECE7)),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _searchQuery = v),
                style: const TextStyle(fontSize: 13.5, color: CeladonColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search chats or message text...',
                  hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                  prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Color(0xFF64748B)),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF64748B)),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                ),
              ),
            ),
          ),

          // 3 Filter Chips: All, Unread, Group
          _buildChatFilterChips(),

          Expanded(
            child: filteredConvos.isEmpty
                ? _buildEmptyConversationsState()
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(0, 4, 0, 80),
                    itemCount: filteredConvos.length,
                    itemBuilder: (context, i) => _buildConversationRow(filteredConvos[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatFilterChips() {
    final filters = ['All', 'Unread', 'Group'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Row(
        children: List.generate(filters.length, (idx) {
          final isSelected = _chatFilterIndex == idx;
          final label = filters[idx];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              onTap: () => setState(() => _chatFilterIndex = idx),
              borderRadius: BorderRadius.circular(18),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                decoration: BoxDecoration(
                  color: isSelected ? CeladonColors.primary : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isSelected ? CeladonColors.primary : const Color(0xFFD3E6DC),
                    width: 1,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: CeladonColors.primary.withValues(alpha: 0.22),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                    color: isSelected ? Colors.white : CeladonColors.textPrimary,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildEmptyConversationsState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: CeladonColors.softMint,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 32,
                color: CeladonColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.user.isSuperAdmin
                  ? 'No owner conversations yet'
                  : 'No conversations yet',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: CeladonColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.user.isSuperAdmin
                  ? 'Start a secure chat or call with any registered company owner.'
                  : 'Tap the green chat button above to message a colleague or create a group.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConversationRow(DmConversationModel conv) {
    final displayName = _resolveConversationName(conv);
    final isOnline = _resolveConversationOnline(conv);
    final hasUnread = conv.unreadCount > 0;
    final preview = conv.lastMessage.isNotEmpty
        ? conv.lastMessage
        : 'Tap to open conversation';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2ECE7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _openConversation(conv),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              _buildAvatar(
                name: displayName,
                online: isOnline,
                isGroup: conv.isGroup,
                radius: 24,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: hasUnread ? FontWeight.w800 : FontWeight.w700,
                              color: CeladonColors.textPrimary,
                              letterSpacing: -0.15,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatTime(conv.lastTimestamp),
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w500,
                            color: hasUnread ? CeladonColors.primary : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w400,
                              color: hasUnread
                                  ? const Color(0xFF1E293B)
                                  : const Color(0xFF64748B),
                            ),
                          ),
                        ),
                        if (hasUnread) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: CeladonColors.primary,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              '${conv.unreadCount}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ] else if (conv.isGroup) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _searchFill,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${conv.participants.length}',
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF475569),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}


  // ═══════════════════════════════════════════════════════════════
  // TEAM CHANNEL VIEW (CLEAN INTEGRATED HEADER + CHAT CANVAS)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildTeamChatView() {
    return Container(
      color: CeladonColors.background,
      child: Column(
        children: [
          // Clean rounded Team Channel Header card (matches user image 2)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2ECE7)),
            ),
            child: Row(
              children: [
                const Icon(Icons.campaign_rounded, color: CeladonColors.primary, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.user.company?.isNotEmpty == true
                        ? '${widget.user.company} Team'
                        : 'Company Team Channel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: CeladonColors.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.call_rounded, color: CeladonColors.primary, size: 21),
                  tooltip: 'Group Voice Call',
                  onPressed: () => WebRtcCallManager.instance.startGroupMeeting(
                    title: '${widget.user.company ?? 'Company'} Voice Meeting',
                    mediaType: 'voice',
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.videocam_rounded, color: CeladonColors.primary, size: 22),
                  tooltip: 'Group Video Call',
                  onPressed: () => WebRtcCallManager.instance.startGroupMeeting(
                    title: '${widget.user.company ?? 'Company'} Video Meeting',
                    mediaType: 'video',
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: _teamMessages.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.forum_outlined,
                            size: 48,
                            color: Color(0xFF64748B),
                          ),
                          SizedBox(height: 12),
                          Text(
                            'No team messages yet',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: CeladonColors.textPrimary,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Start a conversation, send a voice note, or start a team call.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.4,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                    itemCount: _teamMessages.length,
                    itemBuilder: (_, i) {
                      final msg = _teamMessages[i];
                      final isMine = msg.senderId == _myUserId;
                      final senderName = _resolveSenderName(msg.senderId, msg.senderName);
                      return GestureDetector(
                        onLongPress: () => _showMessageOptions(
                          isTeam: true,
                          id: msg.id,
                          currentContent: msg.content,
                          isMine: isMine,
                        ),
                        child: _buildMessageBubble(
                          senderName: senderName,
                          showSenderName: !isMine,
                          content: msg.content,
                          timestamp: _formatTime(msg.timestamp),
                          isMine: isMine,
                          edited: msg.editedAt != null,
                          attachments: msg.attachments,
                        ),
                      );
                    },
                  ),
          ),

          _buildComposer(hintText: 'Message team channel...'),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ACTIVE 1:1 / GROUP CONVERSATION VIEW
  // ═══════════════════════════════════════════════════════════════

  Widget _buildActiveDmView(DmConversationModel conv) {
    final displayName = _resolveConversationName(conv);
    final isOnline = _resolveConversationOnline(conv);
    final subtitle = _resolveConversationRoleSubtitle(conv);

    return Container(
      color: _chatCanvasBg,
      child: Column(
        children: [
          // Sleek Integrated Conversation Header Bar
          Container(
            padding: const EdgeInsets.fromLTRB(6, 8, 12, 8),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: _subtleDivider)),
            ),
            child: Row(
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    size: 22,
                    color: CeladonColors.textPrimary,
                  ),
                  onPressed: _closeActiveConversation,
                ),
                _buildAvatar(
                  name: displayName,
                  online: isOnline,
                  isGroup: conv.isGroup,
                  radius: 19,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: conv.isGroup ? () => _showGroupMembersSheet(conv) : null,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: CeladonColors.textPrimary,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                            if (!conv.isGroup && _e2eActive) ...[
                              const SizedBox(width: 5),
                              const Tooltip(
                                message: 'End-to-End Encrypted',
                                child: Icon(
                                  Icons.lock_rounded,
                                  size: 13,
                                  color: CeladonColors.primary,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 1),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: isOnline ? const Color(0xFF16A34A) : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _buildTonalCallButton(
                  tooltip: conv.isGroup ? 'Group Voice Call' : 'Voice Call',
                  icon: Icons.call_rounded,
                  onTap: () {
                    if (conv.isGroup) {
                      WebRtcCallManager.instance.startGroupMeeting(
                        title: displayName,
                        mediaType: 'voice',
                        conversationId: conv.conversationId,
                      );
                    } else {
                      final targetPeerId = _resolvePeerId(conv);
                      if (targetPeerId.isEmpty || _myUserId.toLowerCase() == targetPeerId.toLowerCase()) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Cannot initiate a call with yourself.')),
                        );
                        return;
                      }
                      WebRtcCallManager.instance.startCall(
                        recipientId: targetPeerId,
                        recipientName: displayName,
                        mediaType: 'voice',
                      );
                    }
                  },
                ),
                const SizedBox(width: 8),
                _buildTonalCallButton(
                  tooltip: conv.isGroup ? 'Group Video Call' : 'Video Call',
                  icon: Icons.videocam_rounded,
                  onTap: () {
                    if (conv.isGroup) {
                      WebRtcCallManager.instance.startGroupMeeting(
                        title: displayName,
                        mediaType: 'video',
                        conversationId: conv.conversationId,
                      );
                    } else {
                      final targetPeerId = _resolvePeerId(conv);
                      if (targetPeerId.isEmpty || _myUserId.toLowerCase() == targetPeerId.toLowerCase()) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Cannot initiate a call with yourself.')),
                        );
                        return;
                      }
                      WebRtcCallManager.instance.startCall(
                        recipientId: targetPeerId,
                        recipientName: displayName,
                        mediaType: 'video',
                      );
                    }
                  },
                ),
              ],
            ),
          ),

          // Message Stream
          Expanded(
            child: _isLoadingDm
                ? const Center(
                    child: CircularProgressIndicator(color: CeladonColors.primary),
                  )
                : _directMessages.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildAvatar(
                                name: displayName,
                                online: isOnline,
                                isGroup: conv.isGroup,
                                radius: 32,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                displayName,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: CeladonColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _e2eActive
                                    ? 'Messages are end-to-end encrypted. Say hello!'
                                    : 'Say hello to $displayName!',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                        itemCount: _directMessages.length,
                        itemBuilder: (_, i) {
                          final msg = _directMessages[i];
                          final isMine = msg.senderId == _myUserId;
                          final isRead = msg.readBy.any((uid) => uid != _myUserId);
                          final isDelivered = isRead || isOnline || !msg.id.startsWith('local');
                          final senderName = _resolveSenderName(msg.senderId, msg.senderName);
                          return GestureDetector(
                            onLongPress: () => _showMessageOptions(
                              isTeam: false,
                              id: msg.id,
                              currentContent: msg.displayContent,
                              isMine: isMine,
                            ),
                            child: _buildMessageBubble(
                              senderName: senderName,
                              showSenderName: !isMine && conv.isGroup,
                              content: msg.displayContent,
                              timestamp: _formatTime(msg.timestamp),
                              isMine: isMine,
                              edited: msg.editedAt != null,
                              isRead: isRead,
                              isDelivered: isDelivered,
                              showReadReceipt: isMine,
                              attachments: msg.attachments,
                            ),
                          );
                        },
                      ),
          ),

          _buildComposer(hintText: 'Message $displayName...'),
        ],
      ),
    );
  }

  Widget _buildTonalCallButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: CeladonColors.softMint,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8.5),
            child: Icon(icon, size: 19, color: CeladonColors.primary),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble({
    required String senderName,
    required bool showSenderName,
    required String content,
    required String timestamp,
    required bool isMine,
    bool edited = false,
    bool isRead = false,
    bool isDelivered = false,
    bool showReadReceipt = false,
    List<MessageAttachmentModel> attachments = const [],
  }) {
    final audioAtts = attachments.where((a) => a.isAudio).toList();
    final imageAtts = attachments.where((a) => a.isImage).toList();
    final videoAtts = attachments.where((a) => a.isVideo).toList();
    final docAtts = attachments
        .where((a) => !a.isAudio && !a.isImage && !a.isVideo && a.path.isNotEmpty)
        .toList();

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(13, 9, 13, 7),
        constraints: const BoxConstraints(maxWidth: 295),
        decoration: BoxDecoration(
          color: isMine ? CeladonColors.primary : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMine ? 18 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 18),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isMine ? 0.06 : 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showSenderName) ...[
              Text(
                senderName,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: _avatarTintForName(senderName),
                ),
              ),
              const SizedBox(height: 3),
            ],
            if (content.isNotEmpty)
              Text(
                content,
                style: TextStyle(
                  fontSize: 14,
                  color: isMine ? Colors.white : CeladonColors.textPrimary,
                  height: 1.38,
                ),
              ),
            for (final audio in audioAtts)
              VoiceMessagePlayer(
                audioUrl: audio.resolvedUrl,
                isMine: isMine,
                durationSeconds: audio.duration,
              ),
            for (final img in imageAtts)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: GestureDetector(
                  onTap: () {
                    if (img.resolvedUrl.isEmpty) return;
                    showDialog(
                      context: context,
                      builder: (_) => FullScreenImageViewer(imageUrl: img.resolvedUrl),
                    );
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      img.resolvedUrl,
                      height: 150,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            for (final vid in videoAtts)
              VideoMessageBubble(attachment: vid, isMine: isMine),
            for (final doc in docAtts)
              DocumentAttachmentCard(attachment: doc, isMine: isMine),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (edited)
                  Text(
                    'edited • ',
                    style: TextStyle(
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                      color: isMine
                          ? Colors.white.withValues(alpha: 0.72)
                          : const Color(0xFF94A3B8),
                    ),
                  ),
                if (timestamp.isNotEmpty)
                  Text(
                    timestamp,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: isMine
                          ? Colors.white.withValues(alpha: 0.78)
                          : const Color(0xFF94A3B8),
                    ),
                  ),
                if (showReadReceipt) ...[
                  const SizedBox(width: 4),
                  Icon(
                    (isRead || isDelivered) ? Icons.done_all_rounded : Icons.done_rounded,
                    size: 14,
                    color: isRead
                        ? const Color(0xFF38BDF8)
                        : Colors.white.withValues(alpha: 0.70),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // PROFESSIONAL COMPOSER BAR
  // Left: Spacious Expanded text box with Media icon inside
  // Right: [ Record Video ] [ Voice Message ] [ Send ]
  // ═══════════════════════════════════════════════════════════════

  Widget _buildComposer({required String hintText}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _subtleDivider)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // 1. LEFT SIDE: Spacious, professional message text input box (Expanded) with Media icon inside
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                decoration: BoxDecoration(
                  color: _searchFill,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: CeladonColors.border.withValues(alpha: 0.6)),
                ),
                padding: const EdgeInsets.only(left: 2, right: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Media icon inside the box!
                    IconButton(
                      icon: const Icon(Icons.attach_file_rounded, color: CeladonColors.primary, size: 18),
                      tooltip: 'Attach Photo, Video or Document',
                      onPressed: _isSending ? null : _handleOpenMediaPicker,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.all(6),
                      constraints: const BoxConstraints(),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        textInputAction: TextInputAction.send,
                        minLines: 1,
                        maxLines: 5,
                        onSubmitted: (_) => _handleSendText(),
                        style: const TextStyle(fontSize: 14.5, color: CeladonColors.textPrimary),
                        decoration: InputDecoration(
                          hintText: hintText,
                          hintStyle: const TextStyle(fontSize: 13.5, color: Color(0xFF64748B)),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 5),

            // 2. RIGHT SIDE ACTION ICONS:
            // (A) Video Record
            Tooltip(
              message: 'Record Video',
              child: Material(
                color: CeladonColors.softMint,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _isSending ? null : _handleRecordVideo,
                  child: const Padding(
                    padding: EdgeInsets.all(7.5),
                    child: Icon(Icons.videocam_rounded, color: CeladonColors.primary, size: 17.5),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),

            // (B) Voice Note Recorder Sheet
            Tooltip(
              message: 'Record Voice Message',
              child: Material(
                color: CeladonColors.softMint,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _handleOpenVoiceRecorder,
                  child: const Padding(
                    padding: EdgeInsets.all(7.5),
                    child: Icon(Icons.mic_rounded, color: CeladonColors.primary, size: 17.5),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),

            // (C) Primary Send button
            Material(
              color: CeladonColors.primary,
              shape: const CircleBorder(),
              elevation: 1,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _isSending ? null : _handleSendText,
                child: Padding(
                  padding: const EdgeInsets.all(7.5),
                  child: _isSending
                      ? const SizedBox(
                          width: 17.5,
                          height: 17.5,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded, color: Colors.white, size: 17.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      backgroundColor: CeladonColors.background,
      appBar: _activeConversation != null
          ? null
          : AppBar(
              backgroundColor: CeladonColors.background,
              foregroundColor: CeladonColors.textPrimary,
              elevation: 0,
              scrolledUnderElevation: 0,
              automaticallyImplyLeading: false,
              leading: IconButton(
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: CeladonColors.textPrimary,
                  size: 22,
                ),
                tooltip: 'Back',
                onPressed: widget.onBack ??
                    () {
                      if (Navigator.of(context).canPop()) {
                        Navigator.of(context).pop();
                      } else if (widget.onOpenDrawer != null) {
                        widget.onOpenDrawer!();
                      }
                    },
              ),
              titleSpacing: 0,
              title: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Messenger',
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                color: CeladonColors.textPrimary,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (_socketConnected)
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF22C55E),
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Direct & group encrypted communications',
                          style: TextStyle(
                            fontSize: 11,
                            color: CeladonColors.textMuted,
                            height: 1.25,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: 'New Group',
                  icon: const Icon(Icons.group_add_outlined, color: CeladonColors.primary, size: 22),
                  onPressed: _showCreateGroupSheet,
                ),
                IconButton(
                  tooltip: 'Refresh messages',
                  icon: const Icon(Icons.refresh_rounded, color: CeladonColors.primary, size: 21),
                  onPressed: _loadMessengerData,
                ),
              ],
            ),
      floatingActionButton: (_activeConversation == null && _activeTab == 0)
          ? FloatingActionButton.extended(
              tooltip: 'New Chat',
              backgroundColor: CeladonColors.primary,
              foregroundColor: Colors.white,
              elevation: 3,
              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 20),
              label: const Text('New Chat', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
              onPressed: _showStartDmSheet,
            )
          : null,
      body: SafeArea(
        top: _activeConversation != null,
        bottom: false,
        child: _buildBodyContent(),
      ),
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_activeConversation != null) {
          setState(() => _activeConversation = null);
          _notifyChatState();
        } else if (widget.onBack != null) {
          widget.onBack!();
        } else if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        } else if (widget.onOpenDrawer != null) {
          widget.onOpenDrawer!();
        }
      },
      child: CallOverlay(
        onOpenMessenger: () {},
        child: scaffold,
      ),
    );
  }
}
