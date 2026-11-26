import 'package:flutter/material.dart';

import '../../../core/theme/celadon_colors.dart';
import '../../../core/widgets/regen_page_header.dart';
import '../../dashboard/data/dashboard_service.dart';

/// Team Directory Screen — 100% Dynamic Company Team Roster from MongoDB (`GET /api/users`)
class TeamDirectoryView extends StatefulWidget {
  final VoidCallback? onBack;
  final DashboardService? dashboardService;

  const TeamDirectoryView({super.key, this.onBack, this.dashboardService});

  @override
  State<TeamDirectoryView> createState() => _TeamDirectoryViewState();
}

class _TeamDirectoryViewState extends State<TeamDirectoryView> {
  late final DashboardService _dashboardService;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isLoading = true;
  List<_TeamMember> _allMembers = const [];

  @override
  void initState() {
    super.initState();
    _dashboardService = widget.dashboardService ?? DashboardService();
    _loadTeam();
  }

  Future<void> _loadTeam() async {
    setState(() => _isLoading = true);
    try {
      final users = await _dashboardService.getUsers();
      final members =
          users.map((u) {
            final displayName = u.name.isNotEmpty ? u.name : u.username;
            final initial = displayName.isNotEmpty
                ? displayName[0].toUpperCase()
                : '?';
            final roleLabel =
                (u.designation != null && u.designation!.trim().isNotEmpty)
                ? u.designation!.trim()
                : u.roleDisplayName;
            return _TeamMember(
              name: displayName,
              role: roleLabel,
              department:
                  (u.department != null && u.department!.trim().isNotEmpty)
                  ? u.department!.trim()
                  : (u.company ?? 'General'),
              phone: (u.phone != null && u.phone!.trim().isNotEmpty)
                  ? u.phone!.trim()
                  : 'Not provided',
              email: (u.email != null && u.email!.trim().isNotEmpty)
                  ? u.email!.trim()
                  : 'Not provided',
              avatarLetter: initial,
            );
          }).toList()..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
      if (!mounted) return;
      setState(() {
        _allMembers = members;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _allMembers = const [];
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredMembers = _allMembers.where((m) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return m.name.toLowerCase().contains(q) ||
          m.role.toLowerCase().contains(q) ||
          m.department.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: CeladonColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // 1. Top App Bar matching Company Calendar
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
              child: ReGenPageHeader(
                title: 'Directory',
                subtitle: 'Browse company members and team directory details.',
                onBack: () {
                  if (widget.onBack != null) {
                    widget.onBack!();
                  } else if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  }
                },
                backTooltip: 'Back to Home',
                trailing: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  icon: const Icon(
                    Icons.search_rounded,
                    color: CeladonColors.textPrimary,
                    size: 22,
                  ),
                  onPressed: () {
                      _showSearchModal(context);
                    },
                  ),
              ),
            ),

            // 2. Member Cards List
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: CeladonColors.primary,
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadTeam,
                      color: CeladonColors.primary,
                      child: filteredMembers.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                const SizedBox(height: 120),
                                Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.groups_outlined,
                                        size: 48,
                                        color: CeladonColors.textMuted
                                            .withValues(alpha: 0.6),
                                      ),
                                      const SizedBox(height: 12),
                                      const Text(
                                        'No team members found',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: CeladonColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            )
                          : ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 8,
                              ),
                              itemCount: filteredMembers.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final member = filteredMembers[index];
                                return _buildMemberCard(context, member);
                              },
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberCard(BuildContext context, _TeamMember member) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: CeladonColors.borderLight),
        boxShadow: const [
          BoxShadow(
            color: Color(0x062D6A4F),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          // Circle Avatar Initial
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: CeladonColors.primaryContainer,
              shape: BoxShape.circle,
              border: Border.all(
                color: CeladonColors.primary.withValues(alpha: 0.25),
                width: 1.2,
              ),
            ),
            child: Center(
              child: Text(
                member.avatarLetter,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: CeladonColors.primaryDark,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Name and Role
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: CeladonColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  member.role,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: CeladonColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          // Call Action Button
          InkWell(
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Contacting ${member.name} (${member.phone})'),
                  backgroundColor: CeladonColors.primary,
                ),
              );
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: CeladonColors.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.phone_outlined,
                size: 20,
                color: CeladonColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Chevron Details
          InkWell(
            onTap: () => _showMemberSheet(context, member),
            borderRadius: BorderRadius.circular(12),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: CeladonColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showMemberSheet(BuildContext context, _TeamMember member) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: const BoxDecoration(
                      color: CeladonColors.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        member.avatarLetter,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: CeladonColors.primaryDark,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          member.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: CeladonColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          member.role,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: CeladonColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(color: CeladonColors.divider),
              const SizedBox(height: 12),
              _buildDetailItem(
                Icons.corporate_fare_rounded,
                'Department',
                member.department,
              ),
              const SizedBox(height: 10),
              _buildDetailItem(Icons.phone_outlined, 'Phone', member.phone),
              const SizedBox(height: 10),
              _buildDetailItem(Icons.email_outlined, 'Email', member.email),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('Close'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CeladonColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailItem(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: CeladonColors.primary),
        const SizedBox(width: 10),
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: CeladonColors.textSecondary,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: CeladonColors.textPrimary,
          ),
        ),
      ],
    );
  }

  void _showSearchModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: CeladonColors.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 46,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: CeladonColors.inputBackground,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: CeladonColors.inputBorder,
                    width: 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.search_rounded,
                      size: 19,
                      color: CeladonColors.textMuted,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        autofocus: true,
                        cursorColor: CeladonColors.primary,
                        style: const TextStyle(
                          color: CeladonColors.textPrimary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          filled: true,
                          fillColor: Colors.transparent,
                          hintText: 'Search by name or department...',
                          hintStyle: TextStyle(
                            color: CeladonColors.textPlaceholder,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          focusedErrorBorder: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                        ),
                        onChanged: (val) {
                          setState(() => _searchQuery = val);
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: CeladonColors.textMuted,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                        Navigator.pop(context);
                      },
                    ),
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.filter_list_rounded,
                      size: 20,
                      color: CeladonColors.textMuted,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TeamMember {
  final String name;
  final String role;
  final String department;
  final String phone;
  final String email;
  final String avatarLetter;

  const _TeamMember({
    required this.name,
    required this.role,
    required this.department,
    required this.phone,
    required this.email,
    required this.avatarLetter,
  });
}
