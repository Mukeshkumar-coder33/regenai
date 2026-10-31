import 'package:flutter/material.dart';
import '../../../core/theme/celadon_colors.dart';
import '../../../core/widgets/brand_logo.dart';
import '../../auth/data/auth_service.dart';
import '../../auth/data/user_model.dart';
import '../../company/data/company_model.dart';
import '../../dashboard/data/dashboard_service.dart';

/// Situation D: Global Super Admin Dashboard
///
/// Dedicated high-level platform administration console for `role == 'param'`:
/// - Global Platform Metrics: Total platform companies (7), platform users (17), active tenants
/// - Mode Switcher: "Switch to Company Workspace" (POST /api/auth/switch-to-ems) to return to krish Tech Computer
/// - Companies Directory: Live directory of all 7 platform companies with status badges
/// - Global User Directory: Directory of all 17 users across all companies
/// - 100% Dynamic data backed by live ReGen Node.js backend.
class SuperAdminDashboardView extends StatefulWidget {
  final UserModel user;
  final void Function(UserModel updatedUser)? onUserUpdated;
  final void Function(int tabIndex)? onNavigateToTab;
  final DashboardService? dashboardService;
  final AuthService? authService;

  const SuperAdminDashboardView({
    super.key,
    required this.user,
    this.onUserUpdated,
    this.onNavigateToTab,
    this.dashboardService,
    this.authService,
  });

  @override
  State<SuperAdminDashboardView> createState() => _SuperAdminDashboardViewState();
}

class _SuperAdminDashboardViewState extends State<SuperAdminDashboardView> {
  late final DashboardService _dashboardService;
  late final AuthService _authService;

  bool _isLoading = true;
  String? _errorMessage;
  bool _isSwitchingToEms = false;
  int _selectedSectionIndex = 0; // 0 = Companies, 1 = Platform Users

  List<CompanyModel> _companies = [];
  List<UserModel> _users = [];

  @override
  void initState() {
    super.initState();
    _dashboardService = widget.dashboardService ?? DashboardService();
    _authService = widget.authService ?? AuthService();
    _loadGlobalData();
  }

  Future<void> _loadGlobalData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        _dashboardService.getCompanies(isSuperAdmin: true),
        _dashboardService.getUsers(isSuperAdmin: true),
      ]);

      if (mounted) {
        setState(() {
          _companies = results[0] as List<CompanyModel>;
          _users = results[1] as List<UserModel>;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleSwitchToEms() async {
    setState(() => _isSwitchingToEms = true);

    try {
      final updatedUser = await _authService.switchToEms();
      if (mounted) {
        setState(() => _isSwitchingToEms = false);
        widget.onUserUpdated?.call(updatedUser);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: CeladonColors.primary,
            content: Text('Switched to ${updatedUser.companyName ?? 'Company'} Workspace'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSwitchingToEms = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: CeladonColors.error,
            content: Text('Failed to switch to Company mode: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CeladonColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadGlobalData,
          color: CeladonColors.primary,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Header: ReGen Central Super Admin Console
                Row(
                  children: [
                    const BrandLogo(
                      size: 44,
                      borderRadius: 14,
                      backgroundColor: Color(0xFF0A2E20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'ReGen Central Console',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: CeladonColors.textPrimary,
                            ),
                          ),
                          Text(
                            'Global Super Administrator • Platform Control',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: CeladonColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: CeladonColors.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: CeladonColors.primaryLight),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: CeladonColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'LIVE',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: CeladonColors.primary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 2. Mode Switch Banner: "Switch to Company Workspace"
                _buildEmsSwitchBanner(),
                const SizedBox(height: 16),

                // Loading / Error / Content
                if (_isLoading)
                  _buildLoadingState()
                else if (_errorMessage != null)
                  _buildErrorState()
                else
                  _buildSuperAdminContent(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48),
      alignment: Alignment.center,
      child: Column(
        children: const [
          CircularProgressIndicator(color: CeladonColors.primary),
          SizedBox(height: 16),
          Text(
            'Querying platform cluster databases...',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: CeladonColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CeladonColors.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline_rounded, color: CeladonColors.error, size: 36),
          const SizedBox(height: 12),
          Text(
            _errorMessage ?? 'Unable to connect to Super Admin APIs',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: CeladonColors.textPrimary),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: _loadGlobalData,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Retry Connection'),
            style: ElevatedButton.styleFrom(
              backgroundColor: CeladonColors.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  /// Banner allowing Super Admin to switch back to their company workspace
  Widget _buildEmsSwitchBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0B291E),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x180B291E),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: const [
              Icon(Icons.business_rounded, color: CeladonColors.primaryLight, size: 20),
              SizedBox(width: 8),
              Text(
                'Company Workspace (krish Tech Computer)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Switch to your primary company environment to access staff attendance, company tasks, and local department configuration.',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFFB7D5C4),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _isSwitchingToEms ? null : _handleSwitchToEms,
            icon: _isSwitchingToEms
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.swap_horiz_rounded, size: 18),
            label: Text(
              _isSwitchingToEms ? 'Switching...' : 'Switch to Company Workspace',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: CeladonColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 11),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuperAdminContent() {
    final activeCompaniesCount = _companies.where((c) => c.isActive).length;
    final totalOwnersCount = _users.where((u) => u.role == 'owner').length;
    final totalStaffCount = _users.where((u) => u.isEmployee).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 3. Platform Overview Metric Cards
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: CeladonColors.borderLight),
            boxShadow: const [
              BoxShadow(
                color: Color(0x062D6A4F),
                blurRadius: 10,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildMetricItem(
                      label: 'Total Tenants',
                      value: '${_companies.length}',
                      subtitle: '$activeCompaniesCount Active in cluster',
                      icon: Icons.corporate_fare_rounded,
                      color: CeladonColors.primary,
                    ),
                  ),
                  Container(width: 1, height: 50, color: CeladonColors.divider),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildMetricItem(
                      label: 'Global Users',
                      value: '${_users.length}',
                      subtitle: '$totalOwnersCount Owners • $totalStaffCount Staff',
                      icon: Icons.people_alt_outlined,
                      color: const Color(0xFF059669),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Section Toggle: Companies vs Global Users
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFFE2EFE9),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _selectedSectionIndex = 0),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _selectedSectionIndex == 0 ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: _selectedSectionIndex == 0
                          ? const [BoxShadow(color: Color(0x0A000000), blurRadius: 4)]
                          : null,
                    ),
                    child: Text(
                      'Companies (${_companies.length})',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: _selectedSectionIndex == 0 ? FontWeight.w800 : FontWeight.w600,
                        color: _selectedSectionIndex == 0 ? CeladonColors.textPrimary : CeladonColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _selectedSectionIndex = 1),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _selectedSectionIndex == 1 ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: _selectedSectionIndex == 1
                          ? const [BoxShadow(color: Color(0x0A000000), blurRadius: 4)]
                          : null,
                    ),
                    child: Text(
                      'Platform Users (${_users.length})',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: _selectedSectionIndex == 1 ? FontWeight.w800 : FontWeight.w600,
                        color: _selectedSectionIndex == 1 ? CeladonColors.textPrimary : CeladonColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Content for selected section
        if (_selectedSectionIndex == 0)
          _buildCompaniesList()
        else
          _buildUsersList(),

        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildMetricItem({
    required String label,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: CeladonColors.textSecondary)),
          ],
        ),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: CeladonColors.textPrimary)),
        const SizedBox(height: 2),
        Text(subtitle, style: const TextStyle(fontSize: 11, color: CeladonColors.textMuted)),
      ],
    );
  }

  Widget _buildCompaniesList() {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _companies.length,
      separatorBuilder: (_, index) => const SizedBox(height: 10),
      itemBuilder: (ctx, idx) {
        final comp = _companies[idx];
        return Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: CeladonColors.borderLight),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: CeladonColors.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  comp.name.isNotEmpty ? comp.name[0].toUpperCase() : 'C',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: CeladonColors.primary),
                ),
              ),
            ),
            title: Text(
              comp.name,
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: CeladonColors.textPrimary),
            ),
            subtitle: Text(
              '${comp.city ?? 'Tamil Nadu'} • Owner: ${comp.ownerName ?? comp.ownerId ?? 'Admin'}',
              style: const TextStyle(fontSize: 12, color: CeladonColors.textSecondary),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: comp.isActive ? const Color(0xFFDEF7EC) : const Color(0xFFFDE8E8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                comp.status.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: comp.isActive ? const Color(0xFF03543F) : const Color(0xFF9B1C1C),
                ),
              ),
            ),
            onTap: () => _showCompanyDetailDialog(comp),
          ),
        );
      },
    );
  }

  Widget _buildUsersList() {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _users.length,
      separatorBuilder: (_, index) => const SizedBox(height: 8),
      itemBuilder: (ctx, idx) {
        final u = _users[idx];
        return Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: CeladonColors.borderLight),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: CircleAvatar(
              backgroundColor: CeladonColors.primaryContainer,
              child: Text(
                u.name.isNotEmpty ? u.name[0].toUpperCase() : 'U',
                style: const TextStyle(fontWeight: FontWeight.w700, color: CeladonColors.primary),
              ),
            ),
            title: Text(
              u.name,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              '${u.roleDisplayName} • ${u.company ?? 'ReGen Platform'}',
              style: const TextStyle(fontSize: 12, color: CeladonColors.textSecondary),
            ),
            trailing: Text(
              u.role.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: u.role == 'owner'
                    ? const Color(0xFFD97706)
                    : u.role == 'param'
                        ? CeladonColors.primary
                        : CeladonColors.textMuted,
              ),
            ),
          ),
        );
      },
    );
  }

  void _showCompanyDetailDialog(CompanyModel company) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  company.name,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: CeladonColors.textPrimary),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: company.isActive ? const Color(0xFFDEF7EC) : const Color(0xFFFDE8E8),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    company.status.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: company.isActive ? const Color(0xFF03543F) : const Color(0xFF9B1C1C),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildDetailRow('Owner', company.ownerName ?? company.ownerId ?? 'N/A'),
            _buildDetailRow('City / Location', company.city ?? 'N/A'),
            _buildDetailRow('Phone', company.phoneNumber ?? 'N/A'),
            _buildDetailRow('Email', company.email ?? 'N/A'),
            _buildDetailRow('Category', company.category?.toUpperCase() ?? 'GENERAL'),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: CeladonColors.textSecondary)),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: CeladonColors.textPrimary)),
        ],
      ),
    );
  }
}
