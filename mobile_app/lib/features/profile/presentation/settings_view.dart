import 'package:flutter/material.dart';
import '../../../app/app_config.dart';
import '../../../core/navigation/bottom_nav_customizer.dart';
import '../../../core/navigation/role_menu_registry.dart';
import '../../../core/theme/celadon_colors.dart';
import '../../../core/widgets/regen_page_header.dart';
import '../../../core/widgets/server_connection_dialog.dart';
import '../../auth/data/user_model.dart';
import '../../messenger/data/communication_diagnostics.dart';

/// Screen: App & Profile Settings Screen
///
/// Features:
/// - Light mint background with modern corporate styling
/// - Appearance & Navigation Bar Customizer
/// - Notification preferences toggle
/// - Security & biometrics toggle
/// - Language & theme display
/// - Account info & version details
class SettingsView extends StatefulWidget {
  final VoidCallback? onBack;
  final UserModel? user;
  final List<String>? currentSlots;
  final void Function(List<String> updatedSlots)? onNavSlotsChanged;
  final Future<void> Function()? onSwitchServerLogout;

  const SettingsView({
    super.key,
    this.onBack,
    this.user,
    this.currentSlots,
    this.onNavSlotsChanged,
    this.onSwitchServerLogout,
  });

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  bool _pushNotifications = true;
  bool _soundAlerts = true;
  bool _emailAlerts = true;
  bool _biometricLogin = false;
  bool _taskReminders = true;
  late List<String> _activeSlots;

  List<String> get _defaultSlots => RoleMenuRegistry.getDefaultSlotsForRole(widget.user);

  String get _roleKey => RoleMenuRegistry.getRoleStorageKey(widget.user);

  List<NavShortcutItem> get _catalog => RoleMenuRegistry.getNavCatalogForRole(widget.user);

  @override
  void initState() {
    super.initState();
    _activeSlots = widget.currentSlots != null
        ? List<String>.from(widget.currentSlots!)
        : List<String>.from(_defaultSlots);
    _loadSlots();
    _loadNotificationPrefs();
  }

  Future<void> _loadNotificationPrefs() async {
    final prefs = NotificationPreferences.instance;
    await prefs.ensureLoaded();
    if (!mounted) return;
    setState(() {
      _pushNotifications = prefs.isPushEnabled;
      _soundAlerts = prefs.isSoundEnabled;
      _emailAlerts = prefs.isEmailAlertsEnabled;
      _taskReminders = prefs.isTaskRemindersEnabled;
    });
  }

  @override
  void didUpdateWidget(covariant SettingsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user?.role != widget.user?.role ||
        oldWidget.user?.userId != widget.user?.userId ||
        oldWidget.currentSlots != widget.currentSlots) {
      _activeSlots = widget.currentSlots != null
          ? List<String>.from(widget.currentSlots!)
          : List<String>.from(_defaultSlots);
      _loadSlots();
    }
  }

  Future<void> _loadSlots() async {
    final validIds = _catalog.map((e) => e.id).toSet();
    final loaded = await BottomNavCustomizer.loadSlots(
      roleKey: _roleKey,
      defaults: _defaultSlots,
      validIds: validIds,
      serverSlots: widget.user?.navSlots,
    );
    if (mounted) {
      setState(() {
        _activeSlots = loaded;
      });
    }
  }

  void _openNavCustomizer() {
    BottomNavCustomizer.showAppearanceCustomizerSheet(
      context: context,
      roleKey: _roleKey,
      catalog: _catalog,
      currentSlots: _activeSlots,
      defaultSlots: _defaultSlots,
      user: widget.user,
      onSlotsChanged: (updated) {
        setState(() {
          _activeSlots = List<String>.from(updated);
        });
        widget.onNavSlotsChanged?.call(updated);
      },
    );
  }

  String get _currentSlotsSummary {
    return _activeSlots.map((id) {
      final match = _catalog.where((c) => c.id == id);
      return match.isNotEmpty ? match.first.label : id;
    }).join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CeladonColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Top Bar matching Company Calendar
              ReGenPageHeader(
                title: 'Settings',
                subtitle: 'Manage account preferences and system settings.',
                onBack: () {
                  if (widget.onBack != null) {
                    widget.onBack!();
                  } else {
                    Navigator.of(context).pop();
                  }
                },
              ),
              const SizedBox(height: 16),

              // 2. Appearance & Navigation Group
              _buildSectionTitle('Appearance & Navigation'),
              _buildSettingsCard([
                _buildActionTile(
                  icon: Icons.palette_outlined,
                  title: 'Bottom Navigation Shortcuts',
                  subtitle: _currentSlotsSummary,
                  onTap: _openNavCustomizer,
                ),
                const Divider(color: CeladonColors.divider),
                _buildInfoTile(
                  icon: Icons.color_lens_outlined,
                  title: 'App Theme',
                  value: 'Premium Office (Celadon)',
                ),
              ]),
              const SizedBox(height: 20),

              // 3. Server Connection Group (Auto / Company Server / Local Server)
              _buildSectionTitle('Server Connection'),
              _buildSettingsCard([
                _buildActionTile(
                  icon: Icons.auto_awesome_rounded,
                  title: 'Auto (Recommended)',
                  subtitle: 'Local Wi-Fi when reachable → ${AppConfig.companyServerUrl}',
                  onTap: () => _handleServerQuickSelect(ServerEnvironment.auto),
                  trailing: _buildSelectionIndicator(AppConfig.isAutoMode),
                ),
                const Divider(color: CeladonColors.divider),
                _buildActionTile(
                  icon: Icons.cloud_done_outlined,
                  title: 'Company Server',
                  subtitle: AppConfig.companyServerUrl,
                  onTap: () => _handleServerQuickSelect(ServerEnvironment.company),
                  trailing: _buildSelectionIndicator(AppConfig.isCompanyServer),
                ),
                const Divider(color: CeladonColors.divider),
                _buildActionTile(
                  icon: Icons.lan_outlined,
                  title: 'Local Server',
                  subtitle: AppConfig.localServerUrl,
                  onTap: () => _handleServerQuickSelect(ServerEnvironment.local),
                  trailing: _buildSelectionIndicator(AppConfig.isLocalServer),
                ),
                const Divider(color: CeladonColors.divider),
                _buildActionTile(
                  icon: Icons.settings_ethernet_rounded,
                  title: 'Configure Local IP & Test',
                  subtitle: 'Active: ${AppConfig.serverDisplayName} (${AppConfig.activeBaseUrl})',
                  onTap: _openServerConnectionDialog,
                ),
              ]),
              const SizedBox(height: 20),

              // 4. Notifications Group
              _buildSectionTitle('Notifications'),
              _buildSettingsCard([
                _buildSwitchTile(
                  icon: Icons.notifications_active_outlined,
                  title: 'Push Notifications',
                  subtitle: 'Receive real-time alerts for calls, messages and tasks',
                  value: _pushNotifications,
                  onChanged: (val) async {
                    setState(() => _pushNotifications = val);
                    await NotificationPreferences.instance.setPushEnabled(val);
                  },
                ),
                const Divider(color: CeladonColors.divider),
                _buildSwitchTile(
                  icon: Icons.volume_up_outlined,
                  title: 'Message & Call Sounds',
                  subtitle: 'Play notification tones for incoming messages',
                  value: _soundAlerts,
                  onChanged: (val) async {
                    setState(() => _soundAlerts = val);
                    await NotificationPreferences.instance.setSoundEnabled(val);
                  },
                ),
                const Divider(color: CeladonColors.divider),
                _buildSwitchTile(
                  icon: Icons.mark_email_read_outlined,
                  title: 'Email Alerts',
                  subtitle: 'Receive daily summaries and leave approvals',
                  value: _emailAlerts,
                  onChanged: (val) async {
                    setState(() => _emailAlerts = val);
                    await NotificationPreferences.instance.setEmailAlertsEnabled(val);
                  },
                ),
                const Divider(color: CeladonColors.divider),
                _buildSwitchTile(
                  icon: Icons.alarm_outlined,
                  title: 'Task Reminders',
                  subtitle: 'Get notified 15 minutes before scheduled meetings',
                  value: _taskReminders,
                  onChanged: (val) async {
                    setState(() => _taskReminders = val);
                    await NotificationPreferences.instance.setTaskRemindersEnabled(val);
                  },
                ),
              ]),
              const SizedBox(height: 20),

              // 3. Security Group
              _buildSectionTitle('Security & Authentication'),
              _buildSettingsCard([
                _buildSwitchTile(
                  icon: Icons.fingerprint_rounded,
                  title: 'Biometric Login',
                  subtitle: 'Use fingerprint or FaceID for fast access',
                  value: _biometricLogin,
                  onChanged: (val) => setState(() => _biometricLogin = val),
                ),
                const Divider(color: CeladonColors.divider),
                _buildActionTile(
                  icon: Icons.lock_outline_rounded,
                  title: 'Change Password',
                  subtitle: 'Update your corporate account password',
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Password reset instructions sent to your registered email.'),
                        backgroundColor: CeladonColors.primary,
                      ),
                    );
                  },
                ),
              ]),
              const SizedBox(height: 20),

              // 4. System & Information
              _buildSectionTitle('System & App Info'),
              _buildSettingsCard([
                _buildInfoTile(
                  icon: Icons.palette_outlined,
                  title: 'App Theme',
                  value: 'Premium Office (Celadon)',
                ),
                const Divider(color: CeladonColors.divider),
                _buildInfoTile(
                  icon: Icons.info_outline_rounded,
                  title: 'App Version',
                  value: 'v1.0.0+1 (Build 2026)',
                ),
                const Divider(color: CeladonColors.divider),
                _buildInfoTile(
                  icon: Icons.security_rounded,
                  title: 'Data Encryption',
                  value: 'AES-256 Enabled',
                ),
              ]),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: CeladonColors.textSecondary,
        ),
      ),
    );
  }

  Widget _buildSettingsCard(List<Widget> children) {
    return Container(
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
        children: children,
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: CeladonColors.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: CeladonColors.primary, size: 20),
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
                    fontSize: 11.5,
                    color: CeladonColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: CeladonColors.primary,
            activeTrackColor: CeladonColors.primaryLight.withValues(alpha: 0.4),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Future<void> _openServerConnectionDialog() async {
    final changed = await showServerConnectionDialog(
      context,
      isAuthenticatedSession: widget.user != null,
      onSessionResetRequired: widget.onSwitchServerLogout != null
          ? () {
              widget.onSwitchServerLogout!.call();
            }
          : null,
    );
    if (changed && mounted) {
      setState(() {});
    }
  }

  Future<void> _handleServerQuickSelect(ServerEnvironment target) async {
    if (target == AppConfig.serverEnvironment || target == ServerEnvironment.local) {
      await _openServerConnectionDialog();
      return;
    }

    final previousUrl = AppConfig.activeBaseUrl;
    if (target == ServerEnvironment.auto) {
      await AppConfig.useAutoMode();
    } else {
      await AppConfig.useCompanyServer();
    }
    final urlChanged = AppConfig.activeBaseUrl != previousUrl;
    if (!mounted) return;

    setState(() {});
    if (urlChanged && widget.user != null) {
      if (widget.onSwitchServerLogout != null) {
        await widget.onSwitchServerLogout!();
      } else {
        await resetSessionForServerSwitch(context);
      }
    }
  }

  Widget _buildSelectionIndicator(bool selected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: selected ? CeladonColors.primary : CeladonColors.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        selected ? 'Active' : 'Select',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: selected ? Colors.white : CeladonColors.primary,
        ),
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: CeladonColors.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: CeladonColors.primary, size: 20),
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
                      fontSize: 11.5,
                      color: CeladonColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            trailing ??
                const Icon(
                  Icons.chevron_right_rounded,
                  color: CeladonColors.textMuted,
                  size: 20,
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: CeladonColors.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: CeladonColors.primary, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: CeladonColors.textPrimary,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: CeladonColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}
