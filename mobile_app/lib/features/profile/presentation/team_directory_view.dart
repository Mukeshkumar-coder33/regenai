import 'package:flutter/material.dart';
import '../../../core/theme/celadon_colors.dart';

/// Screen 8 (from Reference Design): Team Directory Screen
///
/// Features:
/// - Light mint background with modern corporate aesthetic
/// - Search bar & filter trigger in top bar
/// - Clean white cards with employee initials, name, designation, and direct call action
class TeamDirectoryView extends StatefulWidget {
  final VoidCallback? onBack;

  const TeamDirectoryView({super.key, this.onBack});

  @override
  State<TeamDirectoryView> createState() => _TeamDirectoryViewState();
}

class _TeamDirectoryViewState extends State<TeamDirectoryView> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  final List<_TeamMember> _allMembers = const [
    _TeamMember(
      name: 'Rohith Kumar',
      role: 'Project Manager',
      department: 'Management',
      phone: '+91 98765 43210',
      email: 'rohith.k@regen.com',
      avatarLetter: 'R',
    ),
    _TeamMember(
      name: 'Sneha R',
      role: 'UI/UX Designer',
      department: 'Product Design',
      phone: '+91 98765 43211',
      email: 'sneha.r@regen.com',
      avatarLetter: 'S',
    ),
    _TeamMember(
      name: 'Vikram S',
      role: 'Frontend Developer',
      department: 'Engineering',
      phone: '+91 98765 43212',
      email: 'vikram.s@regen.com',
      avatarLetter: 'V',
    ),
    _TeamMember(
      name: 'Priya M',
      role: 'Backend Developer',
      department: 'Engineering',
      phone: '+91 98765 43213',
      email: 'priya.m@regen.com',
      avatarLetter: 'P',
    ),
    _TeamMember(
      name: 'Arjun K',
      role: 'QA Engineer',
      department: 'Quality Assurance',
      phone: '+91 98765 43214',
      email: 'arjun.k@regen.com',
      avatarLetter: 'A',
    ),
    _TeamMember(
      name: 'Kavya S',
      role: 'Product Designer',
      department: 'Product Design',
      phone: '+91 98765 43215',
      email: 'kavya.s@regen.com',
      avatarLetter: 'K',
    ),
    _TeamMember(
      name: 'Aafrin Shajathi',
      role: 'Full Stack Engineer',
      department: 'Engineering',
      phone: '+91 98765 43216',
      email: 'aafrin@regen.com',
      avatarLetter: 'A',
    ),
    _TeamMember(
      name: 'Deepak Raj',
      role: 'DevOps Specialist',
      department: 'Infrastructure',
      phone: '+91 98765 43217',
      email: 'deepak.r@regen.com',
      avatarLetter: 'D',
    ),
  ];

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
            // 1. Top App Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  if (widget.onBack != null || Navigator.of(context).canPop())
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 20,
                        color: CeladonColors.textPrimary,
                      ),
                      onPressed: () {
                        if (widget.onBack != null) {
                          widget.onBack!();
                        } else {
                          Navigator.of(context).pop();
                        }
                      },
                    )
                  else
                    const SizedBox(width: 4),
                  const Text(
                    'Team',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: CeladonColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(
                      Icons.search_rounded,
                      color: CeladonColors.textPrimary,
                      size: 24,
                    ),
                    onPressed: () {
                      _showSearchModal(context);
                    },
                  ),
                ],
              ),
            ),

            // 2. Member Cards List
            Expanded(
              child: filteredMembers.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.groups_outlined,
                            size: 48,
                            color: CeladonColors.textMuted.withValues(alpha: 0.6),
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
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      itemCount: filteredMembers.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final member = filteredMembers[index];
                        return _buildMemberCard(context, member);
                      },
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
              _buildDetailItem(Icons.corporate_fare_rounded, 'Department', member.department),
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
      backgroundColor: Colors.white,
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
              TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search by name or department...',
                  prefixIcon: const Icon(Icons.search_rounded, color: CeladonColors.primary),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear_rounded),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                      Navigator.pop(context);
                    },
                  ),
                ),
                onChanged: (val) {
                  setState(() => _searchQuery = val);
                },
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
