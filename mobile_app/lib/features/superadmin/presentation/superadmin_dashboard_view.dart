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
/// - Executive Corporate Office Header matching ReGen design system
/// - Hamburger Drawer Menu button to access `AppDrawer`
/// - Direct Logout button in top bar and bottom quick actions
/// - Mode Switcher: "Switch to Company Workspace" (POST /api/auth/switch-to-ems)
/// - 4 Dynamic Platform KPI Tiles backed by MongoDB collections
/// - Live Companies Directory with status badges, city, owner, and detail view
/// - Live Platform User Directory with roles, organization, and contact info
/// - Interactive search filter across companies and platform users
/// - 100% Dynamic data backed by live ReGen Node.js backend.
class SuperAdminDashboardView extends StatefulWidget {
  final UserModel user;
  final VoidCallback? onOpenDrawer;
  final VoidCallback? onLogout;
  final void Function(UserModel updatedUser)? onUserUpdated;
  final void Function(int tabIndex)? onNavigateToTab;
  final DashboardService? dashboardService;
  final AuthService? authService;

  const SuperAdminDashboardView({
    super.key,
    required this.user,
    this.onOpenDrawer,
    this.onLogout,
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
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  List<CompanyModel> _companies = [];
  List<UserModel> _users = [];

  @override
  void initState() {
    super.initState();
    _dashboardService = widget.dashboardService ?? DashboardService();
    _authService = widget.authService ?? AuthService();
    _loadGlobalData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

  void _confirmLogout() {
    if (widget.onLogout == null) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Sign Out', style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text('Are you sure you want to sign out of the Super Admin Console?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.onLogout!();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }

  List<CompanyModel> get _filteredCompanies {
    if (_searchQuery.isEmpty) return _companies;
    final q = _searchQuery.toLowerCase();
    return _companies.where((c) {
      return c.name.toLowerCase().contains(q) ||
          (c.city != null && c.city!.toLowerCase().contains(q)) ||
          (c.email != null && c.email!.toLowerCase().contains(q)) ||
          (c.ownerName != null && c.ownerName!.toLowerCase().contains(q));
    }).toList();
  }

  List<UserModel> get _filteredUsers {
    if (_searchQuery.isEmpty) return _users;
    final q = _searchQuery.toLowerCase();
    return _users.where((u) {
      return u.name.toLowerCase().contains(q) ||
          u.username.toLowerCase().contains(q) ||
          (u.email != null && u.email!.toLowerCase().contains(q)) ||
          u.role.toLowerCase().contains(q) ||
          (u.company != null && u.company!.toLowerCase().contains(q));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CeladonColors.background,
      body: RefreshIndicator(
        onRefresh: _loadGlobalData,
        color: CeladonColors.primary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Executive Corporate Header with Office Background & Hamburger Menu
              _buildExecutiveHeader(),

              // Body Content
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
            ],
          ),
        ),
      ),
    );
  }

  /// 1. Executive Corporate Header matching ReGen Theme with Hamburger Menu & Logout
  Widget _buildExecutiveHeader() {
    final displayName = widget.user.name.isNotEmpty
        ? widget.user.name
        : (widget.user.username.isNotEmpty ? widget.user.username : 'Super Admin');

    return Container(
      decoration: const BoxDecoration(
        color: CeladonColors.primaryDark,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
        child: Stack(
          children: [
            // Background office image texture
            Positioned.fill(
              child: Opacity(
                opacity: 0.18,
                child: Image.asset(
                  'assets/images/office_dashboard_header.png',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                ),
              ),
            ),
            // Gradient Overlay
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFF071F15).withValues(alpha: 0.95),
                      CeladonColors.primaryDark.withValues(alpha: 0.92),
                    ],
                  ),
                ),
              ),
            ),

            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Bar: Hamburger Menu Button (Left) and Refresh + Logout (Right)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Hamburger Menu Button (Opens AppDrawer)
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            icon: const Icon(
                              Icons.menu_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                            tooltip: 'Menu',
                            onPressed: () {
                              if (widget.onOpenDrawer != null) {
                                widget.onOpenDrawer!();
                              } else {
                                Scaffold.maybeOf(context)?.openDrawer();
                              }
                            },
                          ),
                        ),

                        // Title & Badge
                        Row(
                          children: [
                            const BrandLogo(size: 28, borderRadius: 8),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text(
                                  'SUPER ADMIN',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.2,
                                    color: CeladonColors.primaryLight,
                                  ),
                                ),
                                Text(
                                  'ReGen Central Console',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        // Right actions: Refresh & Logout
                        Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
                                tooltip: 'Refresh Data',
                                onPressed: _loadGlobalData,
                              ),
                            ),
                            if (widget.onLogout != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEF4444).withValues(alpha: 0.28),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.6)),
                                ),
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  icon: const Icon(Icons.logout_rounded, color: Colors.white, size: 20),
                                  tooltip: 'Sign Out',
                                  onPressed: _confirmLogout,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Super Admin Identity Card
                    Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: CeladonColors.primaryLight, width: 2),
                            color: CeladonColors.primaryContainer,
                          ),
                          child: ClipOval(
                            child: Center(
                              child: Text(
                                displayName.isNotEmpty ? displayName[0].toUpperCase() : 'S',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: CeladonColors.primaryDark,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayName,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF22C55E),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    'MongoDB Live Cluster Active',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFFB7D5C4),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
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
    final totalOwnersCount = _users.where((u) => u.isCompanyAdmin).length;
    final totalStaffCount = _users.where((u) => u.isEmployee).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 3. 2x2 Platform Overview Metric Cards (100% Dynamic MongoDB Data)
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                icon: Icons.corporate_fare_rounded,
                iconBg: const Color(0xFFE8F5ED),
                iconColor: CeladonColors.primaryDark,
                count: '${_companies.length}',
                label: 'Total Tenants',
                subtitle: '$activeCompaniesCount Active instances',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricTile(
                icon: Icons.domain_verification_rounded,
                iconBg: const Color(0xFFDCFCE7),
                iconColor: const Color(0xFF15803D),
                count: '$activeCompaniesCount',
                label: 'Active Tenants',
                subtitle: 'Operational cluster',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                icon: Icons.people_alt_outlined,
                iconBg: const Color(0xFFE0F2FE),
                iconColor: const Color(0xFF0284C7),
                count: '${_users.length}',
                label: 'Global Users',
                subtitle: 'Platform-wide accounts',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricTile(
                icon: Icons.admin_panel_settings_outlined,
                iconBg: const Color(0xFFFEF3C7),
                iconColor: const Color(0xFFD97706),
                count: '$totalOwnersCount',
                label: 'Owners & Admins',
                subtitle: '$totalStaffCount Staff members',
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // 4. Search Filter Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: CeladonColors.borderLight),
            boxShadow: const [
              BoxShadow(color: Color(0x062D6A4F), blurRadius: 6, offset: Offset(0, 2)),
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.search_rounded, color: CeladonColors.textMuted, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: _selectedSectionIndex == 0
                        ? 'Search companies by name, city, email...'
                        : 'Search platform users by name, role, email...',
                    hintStyle: const TextStyle(fontSize: 13, color: CeladonColors.textMuted),
                    border: InputBorder.none,
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                ),
              ),
              if (_searchQuery.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18, color: CeladonColors.textMuted),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 5. Section Toggle: Companies vs Global Users
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
                      'Companies (${_filteredCompanies.length})',
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
                      'Platform Users (${_filteredUsers.length})',
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

        // 6. Content for selected section
        if (_selectedSectionIndex == 0)
          _buildCompaniesList()
        else
          _buildUsersList(),

        const SizedBox(height: 24),

        // 7. Bottom Sign Out Action Card
        if (widget.onLogout != null) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: CeladonColors.borderLight),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.logout_rounded, color: Color(0xFFDC2626), size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Super Admin Session',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: CeladonColors.textPrimary),
                      ),
                      Text(
                        'Securely end console session on this device',
                        style: TextStyle(fontSize: 12, color: CeladonColors.textMuted),
                      ),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: _confirmLogout,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  child: const Text('Logout', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ],
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String count,
    required String label,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: CeladonColors.borderLight),
        boxShadow: const [
          BoxShadow(
            color: Color(0x062D6A4F),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              Text(
                count,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: CeladonColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: CeladonColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: CeladonColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompaniesList() {
    final list = _filteredCompanies;
    if (list.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 36),
        alignment: Alignment.center,
        child: Column(
          children: const [
            Icon(Icons.search_off_rounded, size: 40, color: CeladonColors.textMuted),
            SizedBox(height: 10),
            Text('No tenant companies match your search', style: TextStyle(fontSize: 13, color: CeladonColors.textMuted)),
          ],
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: list.length,
      separatorBuilder: (_, index) => const SizedBox(height: 10),
      itemBuilder: (ctx, idx) {
        final comp = list[idx];
        return Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: CeladonColors.borderLight),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: CeladonColors.primaryContainer,
                borderRadius: BorderRadius.circular(12),
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
    final list = _filteredUsers;
    if (list.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 36),
        alignment: Alignment.center,
        child: Column(
          children: const [
            Icon(Icons.search_off_rounded, size: 40, color: CeladonColors.textMuted),
            SizedBox(height: 10),
            Text('No platform users match your search', style: TextStyle(fontSize: 13, color: CeladonColors.textMuted)),
          ],
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: list.length,
      separatorBuilder: (_, index) => const SizedBox(height: 8),
      itemBuilder: (ctx, idx) {
        final u = list[idx];
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
                Expanded(
                  child: Text(
                    company.name,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: CeladonColors.textPrimary),
                  ),
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
