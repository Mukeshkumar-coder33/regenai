import 'package:flutter/material.dart';
import '../../../core/theme/celadon_colors.dart';
import '../../auth/data/user_model.dart';
import '../../dashboard/data/dashboard_service.dart';
import '../data/messenger_model.dart';
import '../data/messenger_service.dart';

/// Unified Role-Aware Messenger Screen
///
/// Reused across all three roles (Company Admin, Employee, Super Admin):
/// - Team Chat connected to `/api/messages`
/// - Direct Messages connected to `/api/dm/conversations`
/// - Respects backend role-based access & company scoping
class MessengerView extends StatefulWidget {
  final UserModel user;
  final VoidCallback? onBack;
  final VoidCallback? onOpenDrawer;
  final bool embedded;
  final MessengerService? messengerService;
  final DashboardService? dashboardService;

  const MessengerView({
    super.key,
    required this.user,
    this.onBack,
    this.onOpenDrawer,
    this.embedded = false,
    this.messengerService,
    this.dashboardService,
  });

  @override
  State<MessengerView> createState() => _MessengerViewState();
}

class _MessengerViewState extends State<MessengerView> {
  late final MessengerService _messengerService;
  late final DashboardService _dashboardService;

  int _activeTab = 0; // 0: Team Chat, 1: Direct Messages
  bool _isLoading = true;
  bool _isSending = false;

  List<TeamMessageModel> _teamMessages = [];
  List<DmConversationModel> _conversations = [];
  List<UserModel> _colleagues = [];

  DmConversationModel? _activeConversation;
  List<DirectMessageModel> _directMessages = [];
  bool _isLoadingDm = false;

  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String get _myUserId =>
      widget.user.userId.isNotEmpty ? widget.user.userId : widget.user.id;

  @override
  void initState() {
    super.initState();
    _messengerService = widget.messengerService ?? MessengerService();
    _dashboardService = widget.dashboardService ?? DashboardService();
    _loadMessengerData();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessengerData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _messengerService.getTeamMessages(user: widget.user),
        _messengerService.getConversations(user: widget.user),
        _dashboardService
            .getUsers(isSuperAdmin: widget.user.isSuperAdmin)
            .catchError((_) => <UserModel>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _teamMessages = results[0] as List<TeamMessageModel>;
        _conversations = results[1] as List<DmConversationModel>;
        _colleagues = (results[2] as List<UserModel>)
            .where((u) => (u.userId.isNotEmpty ? u.userId : u.id) != _myUserId)
            .toList();
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openConversation(DmConversationModel conv) async {
    setState(() {
      _activeConversation = conv;
      _isLoadingDm = true;
    });
    final msgs = await _messengerService.getDirectMessages(
      user: widget.user,
      conversationId: conv.conversationId,
    );
    if (!mounted) return;
    setState(() {
      _directMessages = msgs;
      _isLoadingDm = false;
    });
  }

  Future<void> _handleSend() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    try {
      if (_activeTab == 0) {
        final sent = await _messengerService.sendTeamMessage(
          user: widget.user,
          content: text,
        );
        if (mounted) {
          _messageController.clear();
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
        }
      } else if (_activeConversation != null) {
        final sent = await _messengerService.sendDirectMessage(
          user: widget.user,
          conversationId: _activeConversation!.conversationId,
          content: text,
        );
        if (mounted) {
          _messageController.clear();
          setState(() {
            _directMessages.add(
              sent ??
                  DirectMessageModel(
                    id: 'local-dm-${DateTime.now().millisecondsSinceEpoch}',
                    conversationId: _activeConversation!.conversationId,
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
        }
      } else {
        if (mounted) setState(() => _isSending = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _startNewChatWith(UserModel colleague) async {
    final targetId = colleague.userId.isNotEmpty ? colleague.userId : colleague.id;
    final conv = await _messengerService.getOrCreateConversation(
      user: widget.user,
      recipientId: targetId,
    );
    if (!mounted) return;
    if (conv != null) {
      if (!_conversations.any((c) => c.conversationId == conv.conversationId)) {
        setState(() => _conversations.insert(0, conv));
      }
      await _openConversation(conv);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: CeladonColors.error,
          content: Text('Unable to start direct message with this user.'),
        ),
      );
    }
  }

  void _showStartDmSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: CeladonColors.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Start Direct Message',
                    style: TextStyle(
                      fontSize: 16,
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
              if (_colleagues.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                      'No colleagues available for direct messaging.',
                      style: TextStyle(fontSize: 13, color: CeladonColors.textSecondary),
                    ),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _colleagues.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, color: CeladonColors.divider),
                    itemBuilder: (_, i) {
                      final person = _colleagues[i];
                      final display = person.name.isNotEmpty ? person.name : person.username;
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor: CeladonColors.primaryContainer,
                          child: Text(
                            display.isNotEmpty ? display[0].toUpperCase() : 'U',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: CeladonColors.primary,
                            ),
                          ),
                        ),
                        title: Text(
                          display,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: CeladonColors.textPrimary,
                          ),
                        ),
                        subtitle: Text(
                          person.roleDisplayName,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: CeladonColors.textSecondary,
                          ),
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
      ),
    );
  }

  String _formatTime(String raw) {
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return '';
    final h = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }

  Widget _buildBodyContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.embedded)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Messenger',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: CeladonColors.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                    Text(
                      widget.user.isSuperAdmin
                          ? 'Platform & organization communications'
                          : 'Team chat & private direct messages',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: _loadMessengerData,
                  icon: const Icon(
                    Icons.refresh_rounded,
                    color: CeladonColors.primary,
                    size: 20,
                  ),
                  tooltip: 'Refresh',
                ),
              ],
            ),
          ),

        // Mode Switcher: Team Chat vs Direct Messages
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: CeladonColors.cardBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: CeladonColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() {
                      _activeTab = 0;
                      _activeConversation = null;
                    }),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: _activeTab == 0
                            ? CeladonColors.primary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.forum_outlined,
                            size: 16,
                            color: _activeTab == 0
                                ? Colors.white
                                : CeladonColors.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Team Chat',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: _activeTab == 0
                                  ? Colors.white
                                  : CeladonColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _activeTab = 1),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: _activeTab == 1
                            ? CeladonColors.primary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 16,
                            color: _activeTab == 1
                                ? Colors.white
                                : CeladonColors.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Direct Messages',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: _activeTab == 1
                                  ? Colors.white
                                  : CeladonColors.textSecondary,
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
        ),

        // Main Chat Area
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: CeladonColors.primary),
                )
              : (_activeTab == 0 ? _buildTeamChatArea() : _buildDmArea()),
        ),
      ],
    );
  }

  Widget _buildTeamChatArea() {
    return Column(
      children: [
        Expanded(
          child: _teamMessages.isEmpty
              ? const Center(
                  child: Text(
                    'No team messages yet. Start a conversation!',
                    style: TextStyle(
                      fontSize: 13,
                      color: CeladonColors.textSecondary,
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadMessengerData,
                  color: CeladonColors.primary,
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: _teamMessages.length,
                    itemBuilder: (_, idx) {
                      final msg = _teamMessages[idx];
                      final isMine = msg.senderId == _myUserId;
                      return _buildBubble(
                        senderName: msg.senderName,
                        content: msg.content,
                        time: _formatTime(msg.timestamp),
                        isMine: isMine,
                      );
                    },
                  ),
                ),
        ),
        _buildMessageComposer(hint: 'Write a team message...'),
      ],
    );
  }

  Widget _buildDmArea() {
    if (_activeConversation != null) {
      return Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: CeladonColors.cardBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: CeladonColors.border),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => setState(() => _activeConversation = null),
                  icon: const Icon(Icons.arrow_back_rounded, size: 19),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _activeConversation!.otherUserName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: CeladonColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoadingDm
                ? const Center(
                    child: CircularProgressIndicator(color: CeladonColors.primary),
                  )
                : _directMessages.isEmpty
                    ? const Center(
                        child: Text(
                          'No direct messages yet.',
                          style: TextStyle(
                            fontSize: 13,
                            color: CeladonColors.textSecondary,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        itemCount: _directMessages.length,
                        itemBuilder: (_, idx) {
                          final m = _directMessages[idx];
                          return _buildBubble(
                            senderName: m.senderName,
                            content: m.content,
                            time: _formatTime(m.timestamp),
                            isMine: m.senderId == _myUserId,
                          );
                        },
                      ),
          ),
          _buildMessageComposer(
            hint: 'Message ${_activeConversation!.otherUserName}...',
          ),
        ],
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _showStartDmSheet,
              icon: const Icon(Icons.add_comment_outlined, size: 17),
              label: const Text(
                'New Chat',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
              ),
            ),
          ),
        ),
        Expanded(
          child: _conversations.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 38,
                        color: CeladonColors.textMuted,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'No direct conversations yet',
                        style: TextStyle(
                          fontSize: 13,
                          color: CeladonColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton.icon(
                        onPressed: _showStartDmSheet,
                        icon: const Icon(Icons.add_rounded, size: 17),
                        label: const Text('Start a Conversation'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: CeladonColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  itemCount: _conversations.length,
                  itemBuilder: (_, idx) {
                    final conv = _conversations[idx];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: CeladonColors.cardBackground,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: CeladonColors.border),
                      ),
                      child: ListTile(
                        onTap: () => _openConversation(conv),
                        leading: CircleAvatar(
                          backgroundColor: CeladonColors.primaryContainer,
                          child: Text(
                            conv.otherUserName.isNotEmpty
                                ? conv.otherUserName[0].toUpperCase()
                                : 'C',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: CeladonColors.primary,
                            ),
                          ),
                        ),
                        title: Text(
                          conv.otherUserName,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: CeladonColors.textPrimary,
                          ),
                        ),
                        subtitle: Text(
                          conv.lastMessage.isNotEmpty
                              ? conv.lastMessage
                              : 'Tap to open conversation',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: CeladonColors.textSecondary,
                          ),
                        ),
                        trailing: const Icon(
                          Icons.chevron_right_rounded,
                          color: CeladonColors.textMuted,
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildBubble({
    required String senderName,
    required String content,
    required String time,
    required bool isMine,
  }) {
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 290),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          color: isMine ? CeladonColors.primary : CeladonColors.cardBackground,
          borderRadius: BorderRadius.circular(14),
          border: isMine ? null : Border.all(color: CeladonColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMine) ...[
              Text(
                senderName,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: CeladonColors.primary,
                ),
              ),
              const SizedBox(height: 3),
            ],
            Text(
              content,
              style: TextStyle(
                fontSize: 13,
                color: isMine ? Colors.white : CeladonColors.textPrimary,
                height: 1.35,
              ),
            ),
            if (time.isNotEmpty) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.bottomRight,
                child: Text(
                  time,
                  style: TextStyle(
                    fontSize: 9.5,
                    color: isMine
                        ? Colors.white.withValues(alpha: 0.8)
                        : CeladonColors.textMuted,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMessageComposer({required String hint}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      decoration: const BoxDecoration(
        color: CeladonColors.cardBackground,
        border: Border(top: BorderSide(color: CeladonColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _handleSend(),
              style: const TextStyle(
                fontSize: 13.5,
                color: CeladonColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(
                  fontSize: 13,
                  color: CeladonColors.textMuted,
                ),
                filled: true,
                fillColor: CeladonColors.inputBackground,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: CeladonColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: CeladonColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: CeladonColors.primary),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: CeladonColors.primary,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: _isSending ? null : _handleSend,
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 44,
                height: 44,
                child: _isSending
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.send_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return Container(
        color: CeladonColors.background,
        child: _buildBodyContent(),
      );
    }

    return Scaffold(
      backgroundColor: CeladonColors.background,
      appBar: AppBar(
        backgroundColor: CeladonColors.cardBackground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: CeladonColors.textPrimary,
          ),
          onPressed: widget.onBack ?? () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Messenger',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: CeladonColors.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.refresh_rounded,
              color: CeladonColors.primary,
            ),
            onPressed: _loadMessengerData,
          ),
        ],
      ),
      body: SafeArea(child: _buildBodyContent()),
    );
  }
}
