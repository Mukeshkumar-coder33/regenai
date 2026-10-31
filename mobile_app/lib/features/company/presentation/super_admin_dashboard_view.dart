import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../core/theme/celadon_colors.dart';
import '../../../core/widgets/brand_logo.dart';
import '../../auth/data/user_model.dart';

/// Super Admin Console Dashboard (Unified ReGen Office Theme)
///
/// Designed for Super Administrator (`role == 'param'`):
/// - Reuses exact Dashboard office background (`assets/images/office_dashboard_header.png`)
/// - Authenticated Super Admin profile avatar and role badge
/// - Platform-wide KPI tiles (Active Tenants, Total Users, Cloud Health, Security Logs)
/// - Administration operation cards (Tenant Management, App Modules, Security Controls, API Config)
class SuperAdminDashboardView extends StatelessWidget {
  final UserModel user;
  final VoidCallback? onBack;
  final void Function(int tabIndex)? onNavigateToTab;

  const SuperAdminDashboardView({
    super.key,
    required this.user,
    this.onBack,
    this.onNavigateToTab,
  });

  @override
  Widget build(BuildContext context) {
    final displayName = user.name.isNotEmpty
        ? user.name
        : (user.username.isNotEmpty ? user.username : 'Super Admin');

    return Scaffold(
      backgroundColor: CeladonColors.background,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Executive Corporate Header matching ReGen Theme
            _buildSuperAdminHeader(context, displayName),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 2. Platform Summary Card: "16 Enterprise Tenants" & "2,480 Active Users"
                  _buildPlatformStatsCard(),
                  const SizedBox(height: 14),

                  // 3. 2x2 Infrastructure Metric Cards
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricTile(
                          icon: Icons.cloud_done_rounded,
                          iconBg: const Color(0xFFDCFCE7),
                          iconColor: const Color(0xFF15803D),
                          count: '99.98%',
                          label: 'API Uptime',
                          onTap: () => _showNotice(context, 'Core microservices operational'),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _buildMetricTile(
                          icon: Icons.shield_outlined,
                          iconBg: const Color(0xFFE0F2FE),
                          iconColor: const Color(0xFF0284C7),
                          count: '0',
                          label: 'Security Alerts',
                          onTap: () => _showNotice(context, 'Zero intrusion attempts detected'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // 4. Section Title: "System Administration"
                  const Text(
                    'System Administration',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: CeladonColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 5. Administration Modules List
                  _buildAdminMenuItem(
                    context: context,
                    icon: Icons.domain_rounded,
                    iconBg: const Color(0xFFE0F2FE),
                    iconColor: const Color(0xFF0284C7),
                    title: 'Tenant Companies',
                    subtitle: 'Provision, configure, and monitor enterprise instances',
                    onTap: () => _showNotice(context, 'Enterprise Tenant Manager'),
                  ),
                  _buildAdminMenuItem(
                    context: context,
                    icon: Icons.manage_accounts_rounded,
                    iconBg: CeladonColors.primaryContainer,
                    iconColor: CeladonColors.primary,
                    title: 'Global User Directory',
                    subtitle: 'RBAC permissions, password policies, and tokens',
                    onTap: () => _showNotice(context, 'Global User Directory'),
                  ),
                  _buildAdminMenuItem(
                    context: context,
                    icon: Icons.storage_rounded,
                    iconBg: const Color(0xFFFEF3C7),
                    iconColor: const Color(0xFFD97706),
                    title: 'Database Synchronization',
                    subtitle: 'PostgreSQL dual auth and MongoDB collections',
                    onTap: () => _showNotice(context, 'PostgreSQL port 3004 / MongoDB active'),
                  ),
                  _buildAdminMenuItem(
                    context: context,
                    icon: Icons.security_rounded,
                    iconBg: const Color(0xFFFEE2E2),
                    iconColor: const Color(0xFFEF4444),
                    title: 'Audit & Compliance Logs',
                    subtitle: 'Immutable authentication and administrative audit trails',
                    onTap: () => _showNotice(context, 'Audit & Compliance Logs'),
                  ),
                  _buildAdminMenuItem(
                    context: context,
                    icon: Icons.settings_suggest_rounded,
                    iconBg: const Color(0xFFF3E8FF),
                    iconColor: const Color(0xFFA855F7),
                    title: 'Platform Configurations',
                    subtitle: 'Global rate limits, email relays, and webhook endpoints',
                    onTap: () => _showNotice(context, 'Platform Settings'),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Unified Executive Corporate Header for Super Admin
  Widget _buildSuperAdminHeader(BuildContext context, String displayName) {
    return Container(
      decoration: const BoxDecoration(
        color: CeladonColors.primaryDark,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
        child: Stack(
          children: [
            // Exact Dashboard background image
            Positioned.fill(
              child: Image.asset(
                'assets/images/office_dashboard_header.png',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
              ),
            ),

            // Subtle dark emerald overlay gradient
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFF0F3A2E).withValues(alpha: 0.58),
                      const Color(0xFF1B4332).withValues(alpha: 0.40),
                      const Color(0xFF0F3A2E).withValues(alpha: 0.65),
                    ],
                  ),
                ),
              ),
            ),

            // Header Content
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 26),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Bar: Brand Logo & Title & Notification Bell
                    Row(
                      children: [
                        if (onBack != null)
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
                                Icons.arrow_back_ios_new_rounded,
                                size: 18,
                                color: Colors.white,
                              ),
                              onPressed: onBack,
                            ),
                          )
                        else
                          const BrandLogo(
                            size: 40,
                            borderRadius: 12,
                          ),
                        const SizedBox(width: 12),

                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'ReGen Central',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 17.5,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Super Admin Console',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFB5D6C3),
                                ),
                              ),
                            ],
                          ),
                        ),

                        IconButton(
                          icon: const Icon(
                            Icons.notifications_none_rounded,
                            size: 22,
                            color: Colors.white,
                          ),
                          onPressed: () => _showNotice(context, 'System health normal'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Super Admin Greeting & Avatar Row
                    Row(
                      children: [
                        // Authenticated Super Admin Avatar
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5),
                            color: CeladonColors.primaryContainer,
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x28000000),
                                blurRadius: 10,
                                offset: Offset(0, 3),
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: user.avatar != null && user.avatar!.isNotEmpty
                                ? _buildAvatarImage(user.avatar!, displayName)
                                : Center(
                                    child: Text(
                                      displayName.isNotEmpty
                                          ? displayName.substring(0, 1).toUpperCase()
                                          : 'S',
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                                        color: CeladonColors.primaryDark,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),

                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Platform Master',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFD8F3DC),
                                ),
                              ),
                              Text(
                                displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Super Admin Security Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.admin_panel_settings_rounded, size: 14, color: Color(0xFF34D399)),
                              SizedBox(width: 5),
                              Text(
                                'Param Root',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
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

  Widget _buildAvatarImage(String avatarUrl, String displayName) {
    if (avatarUrl.startsWith('data:image')) {
      try {
        final base64Str = avatarUrl.split(',').last;
        return Image.memory(base64Decode(base64Str), fit: BoxFit.cover);
      } catch (_) {}
    }
    return Image.network(
      avatarUrl,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => Center(
        child: Text(
          displayName.isNotEmpty ? displayName.substring(0, 1).toUpperCase() : 'S',
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: CeladonColors.primaryDark,
          ),
        ),
      ),
    );
  }

  /// Platform Summary Card
  Widget _buildPlatformStatsCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: CeladonColors.borderLight),
        boxShadow: const [
          BoxShadow(
            color: Color(0x082D6A4F),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  '16',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: CeladonColors.textPrimary,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Companies',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: CeladonColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: CeladonColors.divider,
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  '2,480',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: CeladonColors.textPrimary,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Platform Users',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: CeladonColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String count,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
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
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    count,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: CeladonColors.textPrimary,
                    ),
                  ),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: CeladonColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminMenuItem({
    required BuildContext context,
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: CeladonColors.borderLight),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: iconColor, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: CeladonColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: CeladonColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: CeladonColors.textMuted,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showNotice(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: CeladonColors.primary,
      ),
    );
  }
}

