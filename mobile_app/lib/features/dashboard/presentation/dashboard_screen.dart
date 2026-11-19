import '../../auth/presentation/login_screen.dart';
import 'package:flutter/material.dart';
import '../../../core/navigation/bottom_nav_customizer.dart';
import '../../../core/storage/session_storage.dart';
import '../../../core/theme/celadon_colors.dart';
import '../../attendance/presentation/attendance_view.dart';
import '../../auth/data/user_model.dart';
import '../../calendar/presentation/calendar_view.dart';
import '../../company/presentation/company_dashboard_view.dart';
import '../../messenger/data/call_notification_service.dart';
import '../../messenger/data/messenger_socket_service.dart';
import '../../messenger/data/webrtc_call_manager.dart';
import '../../messenger/presentation/call_overlay.dart';
import '../../messenger/presentation/messenger_view.dart';
import '../../policies/data/policy_service.dart';
import '../../profile/presentation/app_drawer.dart';
import '../../profile/presentation/help_support_view.dart';
import '../../profile/presentation/leave_request_view.dart';
import '../../profile/presentation/profile_view.dart';
import '../../profile/presentation/settings_view.dart';
import '../../profile/presentation/team_directory_view.dart';
import '../../superadmin/presentation/superadmin_dashboard_view.dart';
import '../../tasks/presentation/tasks_view.dart';
import 'employee_dashboard_view.dart';
import 'employee_payroll_view.dart';

/// Role-Based Main App Shell with Bottom Navigation
///
/// Unifies the screens from the "8. Premium Celadon" design specification:
/// - Tab 0: Home (Screen 3: Employee Dashboard, Screen 8: Company Dashboard, or Super Admin Dashboard)
/// - Tab 1: Tasks (Screen 6: Tasks Screen with priority filters & badges)
/// - Tab 2: Calendar & Attendance (Screen 5: Calendar & Screen 4: Attendance with quick toggle)
/// - Tab 3: Profile (Screen 7: Sidebar / Profile with SuperAdmin switcher & Logout)
class DashboardScreen extends StatefulWidget {
  final UserModel user;
  final VoidCallback onLogout;

  const DashboardScreen({
    super.key,
    required this.user,
    required this.onLogout,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _currentTabIndex = 0;
  late UserModel _currentUser;
  bool _showAttendanceSubScreen = false;

  // Independent role-based bottom nav shortcut customization (Employee & Super Admin)
  static const List<String> _defaultSlotIds = ['home', 'tasks', 'calendar', 'profile'];
  List<String> _bottomNavSlots = List<String>.from(_defaultSlotIds);
  final List<GlobalKey> _bottomNavSlotKeys = List.generate(4, (_) => GlobalKey());
  String? _overridePageId;

  final PolicyService _policyService = PolicyService();
  EmployeePolicyStatus? _policyStatus;
  bool _isLoadingPolicy = false;
  bool _isPolicySubmitting = false;

  String get _roleStorageKey => _currentUser.isSuperAdmin ? 'superadmin' : 'employee';

  List<NavShortcutItem> get _roleNavCatalog {
    final items = <NavShortcutItem>[
      const NavShortcutItem(
        id: 'home',
        label: 'Home',
        icon: Icons.home_outlined,
        activeIcon: Icons.home_rounded,
      ),
      const NavShortcutItem(
        id: 'tasks',
        label: 'Tasks',
        icon: Icons.assignment_outlined,
        activeIcon: Icons.assignment_rounded,
      ),
      const NavShortcutItem(
        id: 'calendar',
        label: 'Calendar',
        icon: Icons.calendar_today_outlined,
        activeIcon: Icons.calendar_today_rounded,
      ),
      const NavShortcutItem(
        id: 'profile',
        label: 'Profile',
        icon: Icons.person_outline_rounded,
        activeIcon: Icons.person_rounded,
      ),
      const NavShortcutItem(
        id: 'messenger',
        label: 'Messenger',
        icon: Icons.chat_bubble_outline_rounded,
        activeIcon: Icons.chat_bubble_rounded,
      ),
      const NavShortcutItem(
        id: 'attendance',
        label: 'Attendance',
        icon: Icons.event_available_outlined,
        activeIcon: Icons.event_available_rounded,
      ),
      const NavShortcutItem(
        id: 'team',
        label: 'Team',
        icon: Icons.groups_outlined,
        activeIcon: Icons.groups_rounded,
      ),
      if (!_currentUser.isSuperAdmin)
        const NavShortcutItem(
          id: 'leave',
          label: 'Leave',
          icon: Icons.beach_access_outlined,
          activeIcon: Icons.beach_access_rounded,
        ),
      if (!_currentUser.isSuperAdmin)
        const NavShortcutItem(
          id: 'payroll',
          label: 'Payroll',
          icon: Icons.payments_outlined,
          activeIcon: Icons.payments_rounded,
        ),
      const NavShortcutItem(
        id: 'settings',
        label: 'Settings',
        icon: Icons.settings_outlined,
        activeIcon: Icons.settings_rounded,
      ),
      const NavShortcutItem(
        id: 'help',
        label: 'Support',
        icon: Icons.help_outline_rounded,
        activeIcon: Icons.help_rounded,
      ),
    ];
    return items;
  }

  NavShortcutItem _shortcutForId(String id) {
    final catalog = _roleNavCatalog;
    return catalog.firstWhere((e) => e.id == id, orElse: () => catalog.first);
  }

  String get _activePageId =>
      _overridePageId ?? _bottomNavSlots[_currentTabIndex.clamp(0, _bottomNavSlots.length - 1)];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentUser = widget.user;
    _loadRoleBottomNavSlots();
    _initRealtimeCommunication(_currentUser);
    if (!_currentUser.isCompanyAdmin && !_currentUser.isSuperAdmin) {
      _checkPolicyStatus();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    MessengerSocketService.instance.disconnect();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      MessengerSocketService.instance.ensureConnected();
    }
  }

  Future<void> _initRealtimeCommunication(UserModel user) async {
    WebRtcCallManager.instance.bindUser(user);
    await CallNotificationService.instance.initialize();
    await MessengerSocketService.instance.connect(user: user);
  }

  @override
  void didUpdateWidget(covariant DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.id != widget.user.id ||
        oldWidget.user.role != widget.user.role) {
      _currentUser = widget.user;
      _currentTabIndex = 0;
      _overridePageId = null;
      _showAttendanceSubScreen = false;
      _bottomNavSlots = List<String>.from(_defaultSlotIds);
      _loadRoleBottomNavSlots();
      _initRealtimeCommunication(_currentUser);
    }
  }

  Future<void> _loadRoleBottomNavSlots() async {
    if (_currentUser.isCompanyAdmin) return;
    final validIds = _roleNavCatalog.map((e) => e.id).toSet();
    final loaded = await BottomNavCustomizer.loadSlots(
      roleKey: _roleStorageKey,
      defaults: _defaultSlotIds,
      validIds: validIds,
    );
    if (mounted) {
      setState(() {
        _bottomNavSlots = loaded;
      });
    }
  }

  Future<void> _checkPolicyStatus() async {
    setState(() => _isLoadingPolicy = true);
    try {
      final status = await _policyService.getEmployeePolicyStatus();
      if (mounted) {
        setState(() {
          _policyStatus = status;
          _isLoadingPolicy = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingPolicy = false);
    }
  }

  void _navigateToTab(int index) {
    // Preserve semantic mapping for legacy numeric callers (0=home, 1=tasks, 2=calendar, 3=profile)
    const semanticIds = ['home', 'tasks', 'calendar', 'profile'];
    if (index >= 0 && index < semanticIds.length) {
      _navigateToPage(semanticIds[index]);
      return;
    }
    setState(() {
      _currentTabIndex = index.clamp(0, _bottomNavSlots.length - 1);
      _overridePageId = null;
      _showAttendanceSubScreen = false;
    });
  }

  void _navigateToPage(String pageId) {
    final slotIdx = _bottomNavSlots.indexOf(pageId);
    if (slotIdx != -1) {
      setState(() {
        _currentTabIndex = slotIdx;
        _overridePageId = null;
        if (pageId == 'calendar') _showAttendanceSubScreen = false;
      });
      return;
    }
    if (pageId == 'attendance') {
      _openAttendance();
      return;
    }
    setState(() {
      _overridePageId = pageId;
      if (pageId == 'calendar') _showAttendanceSubScreen = false;
    });
  }

  void _openAttendance() {
    final attIdx = _bottomNavSlots.indexOf('attendance');
    if (attIdx != -1) {
      setState(() {
        _currentTabIndex = attIdx;
        _overridePageId = null;
      });
      return;
    }
    final calIdx = _bottomNavSlots.indexOf('calendar');
    if (calIdx != -1) {
      setState(() {
        _currentTabIndex = calIdx;
        _overridePageId = null;
        _showAttendanceSubScreen = true;
      });
      return;
    }
    setState(() {
      _overridePageId = 'attendance';
    });
  }

  Widget _buildPageById(String pageId) {
    switch (pageId) {
      case 'home':
        return _buildHomeView();
      case 'tasks':
        return TasksView(
          user: _currentUser,
          onOpenDrawer: _openDrawer,
          onBack: () => _navigateToPage('home'),
        );
      case 'calendar':
        return _buildCalendarAndAttendanceTab();
      case 'profile':
        return ProfileView(
          user: _currentUser,
          onLogout: _handleLogout,
          onNavigateToTab: _navigateToTab,
          onOpenAttendance: _openAttendance,
          onUserUpdated: (updatedUser) {
            setState(() => _currentUser = updatedUser);
            _loadRoleBottomNavSlots();
          },
        );
      case 'messenger':
        return MessengerView(
          user: _currentUser,
          embedded: true,
          onOpenDrawer: _openDrawer,
          onBack: () => _navigateToPage('home'),
        );
      case 'attendance':
        return AttendanceView(
          onOpenDrawer: _openDrawer,
          onBack: () => _navigateToPage('home'),
        );
      case 'team':
        return TeamDirectoryView(
          onBack: () => _navigateToPage('home'),
        );
      case 'leave':
        return LeaveRequestView(
          user: _currentUser,
          onBack: () => _navigateToPage('home'),
        );
      case 'payroll':
        return EmployeePayrollView(
          user: _currentUser,
          embedded: true,
          onBack: () => _navigateToPage('home'),
        );
      case 'settings':
        return SettingsView(
          user: _currentUser,
          currentSlots: _bottomNavSlots,
          onNavSlotsChanged: (updated) {
            setState(() {
              _bottomNavSlots = updated;
            });
          },
          onBack: () => _navigateToPage('home'),
        );
      case 'help':
        return HelpSupportView(
          onBack: () => _navigateToPage('home'),
        );
      default:
        return _buildHomeView();
    }
  }

  void _openDrawer() {
    _scaffoldKey.currentState?.openDrawer();
  }

  Future<void> _handleLogout() async {
    await WebRtcCallManager.instance.resetOnLogout();
    MessengerSocketService.instance.disconnect();
    await SessionStorage.clearSession();
    try {
      widget.onLogout();
    } catch (_) {}
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Dedicated high-end Company Workspace Experience matching ReGen Design Specification
    if (_currentUser.isCompanyAdmin) {
      return CallOverlay(
        child: CompanyDashboardView(
          user: _currentUser,
          onOpenDrawer: _openDrawer,
          onLogout: _handleLogout,
          onUserUpdated: (updatedUser) {
            setState(() {
              _currentUser = updatedUser;
              _overridePageId = null;
            });
            _loadRoleBottomNavSlots();
            _initRealtimeCommunication(updatedUser);
          },
        ),
      );
    }

    // Mandatory Employee Policy Barrier (Locked until acknowledged or owner allows)
    if (!_currentUser.isSuperAdmin &&
        _policyStatus != null &&
        (_policyStatus!.hasBlockedPolicy || _policyStatus!.pendingPolicies.isNotEmpty)) {
      return _buildPolicyBarrierScreen();
    }

    return CallOverlay(
      onOpenMessenger: () => _navigateToPage('messenger'),
      child: Scaffold(
      key: _scaffoldKey,
      backgroundColor: CeladonColors.background,
      drawer: AppDrawer(
        user: _currentUser,
        onLogout: _handleLogout,
        onNavigateToTab: _navigateToTab,
        onNavigateToPage: _navigateToPage,
        onOpenAttendance: _openAttendance,
        currentTabIndex: _currentTabIndex,
        currentPageId: _activePageId,
      ),
      body: _overridePageId != null
          ? _buildPageById(_overridePageId!)
          : IndexedStack(
              index: _currentTabIndex.clamp(0, _bottomNavSlots.length - 1),
              children: _bottomNavSlots.map(_buildPageById).toList(),
            ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: Color(0xFFE1E8E4), width: 1.0),
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0x06000000),
              blurRadius: 10,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(_bottomNavSlots.length, (slotIndex) {
                final item = _shortcutForId(_bottomNavSlots[slotIndex]);
                return _buildNavItem(
                  index: slotIndex,
                  label: item.label,
                  icon: item.icon,
                  activeIcon: item.activeIcon,
                );
              }),
            ),
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildHomeView() {
    // 1. Super Admin Dashboard (param)
    if (_currentUser.isSuperAdmin) {
      return SuperAdminDashboardView(
        user: _currentUser,
        onOpenDrawer: _openDrawer,
        onLogout: _handleLogout,
        onNavigateToTab: _navigateToTab,
        onUserUpdated: (updatedUser) {
          setState(() => _currentUser = updatedUser);
          _initRealtimeCommunication(updatedUser);
        },
      );
    }

    // 2. Company Owner/Admin Dashboard (owner, admin)
    if (_currentUser.isCompanyAdmin) {
      return CompanyDashboardView(
        user: _currentUser,
        onOpenDrawer: _openDrawer,
        onLogout: _handleLogout,
        onNavigateToTab: _navigateToTab,
        onUserUpdated: (updatedUser) {
          setState(() => _currentUser = updatedUser);
          _initRealtimeCommunication(updatedUser);
        },
      );
    }

    // 3. Employee / Staff Dashboard (staff, intern)
    return EmployeeDashboardView(
      user: _currentUser,
      onOpenDrawer: _openDrawer,
      onLogout: _handleLogout,
      onOpenAttendance: _openAttendance,
      onNavigateToPage: _navigateToPage,
      onNavigateToTab: (index) {
        if (index == 2) {
          _openAttendance();
        } else {
          _navigateToTab(index);
        }
      },
    );
  }

  Widget _buildCalendarAndAttendanceTab() {
    return Column(
      children: [
        // Top Dual Navigation Bar (Toggle between Calendar & Attendance)
        SafeArea(
          bottom: false,
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE1E8E4), width: 1.0),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x06000000),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _showAttendanceSubScreen = false),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: !_showAttendanceSubScreen ? const Color(0xFF087A4B) : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: !_showAttendanceSubScreen
                            ? [
                                BoxShadow(
                                  color: const Color(0xFF087A4B).withValues(alpha: 0.25),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                )
                              ]
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.calendar_month_rounded,
                            size: 16,
                            color: !_showAttendanceSubScreen ? Colors.white : const Color(0xFF829089),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Calendar',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: !_showAttendanceSubScreen ? Colors.white : const Color(0xFF829089),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _showAttendanceSubScreen = true),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: _showAttendanceSubScreen ? const Color(0xFF087A4B) : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: _showAttendanceSubScreen
                            ? [
                                BoxShadow(
                                  color: const Color(0xFF087A4B).withValues(alpha: 0.25),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                )
                              ]
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.fingerprint_rounded,
                            size: 17,
                            color: _showAttendanceSubScreen ? Colors.white : const Color(0xFF829089),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Attendance (5m GPS)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _showAttendanceSubScreen ? Colors.white : const Color(0xFF829089),
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
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: _showAttendanceSubScreen
                ? AttendanceView(
                    onOpenDrawer: _openDrawer,
                    onBack: () => setState(() => _showAttendanceSubScreen = false),
                  )
                : CalendarView(
                    user: _currentUser,
                    onOpenDrawer: _openDrawer,
                    onBack: () => _navigateToTab(0),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildNavItem({
    required int index,
    required String label,
    required IconData icon,
    required IconData activeIcon,
  }) {
    final isSelected = _overridePageId == null && _currentTabIndex == index;
    void handleSingleTap() {
      setState(() {
        _currentTabIndex = index;
        _overridePageId = null;
        _showAttendanceSubScreen = false;
      });
    }

    if (isSelected) {
      return InkWell(
        key: _bottomNavSlotKeys[index],
        onTap: handleSingleTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: CeladonColors.primaryGradient,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: CeladonColors.primaryDark.withValues(alpha: 0.28),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(activeIcon, size: 20, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return InkWell(
      key: _bottomNavSlotKeys[index],
      onTap: handleSingleTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 22,
              color: CeladonColors.textSecondary,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                color: CeladonColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPolicyBarrierScreen() {
    final isBlocked = _policyStatus!.hasBlockedPolicy;
    final blockedItem = isBlocked && _policyStatus!.blockedPolicies.isNotEmpty
        ? _policyStatus!.blockedPolicies.first
        : null;
    final pendingItem = !isBlocked && _policyStatus!.pendingPolicies.isNotEmpty
        ? _policyStatus!.pendingPolicies.first
        : null;

    final policyTitle = isBlocked
        ? (blockedItem?['title'] ?? 'Company Policy')
        : (pendingItem?['title'] ?? 'Company Policy');
    final policyContent = isBlocked
        ? (blockedItem?['content'] ?? '')
        : (pendingItem?['content'] ?? '');
    final effectiveDate = isBlocked
        ? (blockedItem?['effectiveDate'] ?? '')
        : (pendingItem?['effectiveDate'] ?? '');
    final declineReason = blockedItem?['declineReason']?.toString();
    final policyId = (pendingItem?['policyId'] ?? blockedItem?['policyId'] ?? '').toString();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F6),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: isBlocked ? const Color(0xFFFEF2F2) : const Color(0xFFE8F3EC),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isBlocked ? const Color(0xFFDC4C4C) : const Color(0xFF087A4B),
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      isBlocked ? Icons.lock_clock_rounded : Icons.gavel_rounded,
                      color: isBlocked ? const Color(0xFFDC4C4C) : const Color(0xFF087A4B),
                      size: 34,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                Text(
                  isBlocked ? 'Work Access Paused' : 'Company Policy Required',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF17231F),
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 8),

                Text(
                  isBlocked
                      ? 'Your work access is paused pending management review.'
                      : 'Please review and acknowledge the organizational policy to continue working.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF829089), height: 1.4),
                ),
                const SizedBox(height: 24),

                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE1E8E4)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x06000000),
                        blurRadius: 10,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              policyTitle,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF17231F)),
                            ),
                          ),
                          if (effectiveDate.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8F3EC),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                effectiveDate,
                                style: const TextStyle(color: Color(0xFF087A4B), fontSize: 10.5, fontWeight: FontWeight.w600),
                              ),
                            ),
                        ],
                      ),
                      if (policyContent.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 180),
                          child: SingleChildScrollView(
                            child: Text(
                              policyContent,
                              style: const TextStyle(fontSize: 12.5, color: Color(0xFF52615B), height: 1.45),
                            ),
                          ),
                        ),
                      ],
                      if (isBlocked && declineReason != null && declineReason.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFDC4C4C)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Submitted Decline Reason:',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFDC4C4C)),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '"$declineReason"',
                                style: const TextStyle(fontSize: 12, color: Color(0xFF991B1B), fontStyle: FontStyle.italic),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                if (isBlocked) ...[
                  ElevatedButton.icon(
                    onPressed: _isLoadingPolicy ? null : _checkPolicyStatus,
                    icon: _isLoadingPolicy
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Check Approval Status', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF087A4B),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _handleLogout,
                    icon: const Icon(Icons.logout_rounded, size: 18, color: Color(0xFFDC4C4C)),
                    label: const Text('Sign Out', style: TextStyle(color: Color(0xFFDC4C4C), fontSize: 13, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFE1E8E4)),
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ] else ...[
                  ElevatedButton.icon(
                    onPressed: _isPolicySubmitting
                        ? null
                        : () async {
                            setState(() => _isPolicySubmitting = true);
                            final ok = await _policyService.acceptPolicy(policyId);
                            if (mounted) {
                              setState(() => _isPolicySubmitting = false);
                              if (ok) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(backgroundColor: Color(0xFF087A4B), content: Text('Policy accepted. Workspace unlocked!')),
                                );
                                _checkPolicyStatus();
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(backgroundColor: Color(0xFFDC4C4C), content: Text('Failed to accept policy. Please try again.')),
                                );
                              }
                            }
                          },
                    icon: _isPolicySubmitting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_circle_outline_rounded, size: 18),
                    label: const Text('Allow & Continue to Work', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF087A4B),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _isPolicySubmitting ? null : () => _showDeclineReasonDialog(policyId),
                    icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFFDC4C4C)),
                    label: const Text('Decline with Reason', style: TextStyle(color: Color(0xFFDC4C4C), fontSize: 13, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFE1E8E4)),
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: _handleLogout,
                    icon: const Icon(Icons.logout_rounded, size: 16, color: Color(0xFF829089)),
                    label: const Text('Sign Out', style: TextStyle(color: Color(0xFF829089), fontSize: 12.5)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDeclineReasonDialog(String policyId) {
    final reasonCtrl = TextEditingController();
    bool isSending = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFFE1E8E4)),
          ),
          title: const Row(
            children: [
              Icon(Icons.report_problem_rounded, color: Color(0xFFDC4C4C), size: 22),
              SizedBox(width: 8),
              Text('Decline Policy Reason', style: TextStyle(color: Color(0xFF17231F), fontWeight: FontWeight.w800, fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Please explain why you are declining this policy. Your reason will be submitted to the company owner for review, and your work access will be paused until approved.',
                style: TextStyle(fontSize: 12, color: Color(0xFF829089)),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: reasonCtrl,
                maxLines: 4,
                cursorColor: const Color(0xFF087A4B),
                style: const TextStyle(color: Color(0xFF17231F), fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Enter your reason here...',
                  hintStyle: const TextStyle(color: Color(0xFF829089), fontSize: 12.5),
                  filled: true,
                  fillColor: const Color(0xFFF8FAF9),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE1E8E4)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF087A4B)),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF829089))),
            ),
            ElevatedButton(
              onPressed: isSending
                  ? null
                  : () async {
                      final reason = reasonCtrl.text.trim();
                      if (reason.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(backgroundColor: Colors.red, content: Text('Please provide a reason.')),
                        );
                        return;
                      }
                      setDlgState(() => isSending = true);
                      final nav = Navigator.of(ctx);
                      final messenger = ScaffoldMessenger.of(context);
                      final ok = await _policyService.declinePolicy(policyId, reason);
                      nav.pop();
                      if (mounted) {
                        if (ok) {
                          messenger.showSnackBar(
                            const SnackBar(
                              backgroundColor: Color(0xFFEF4444),
                              content: Text('Reason submitted to company owner. Work access paused.'),
                            ),
                          );
                          _checkPolicyStatus();
                        } else {
                          messenger.showSnackBar(
                            const SnackBar(backgroundColor: Colors.red, content: Text('Failed to submit reason. Please try again.')),
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC4C4C), foregroundColor: Colors.white),
              child: isSending
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Submit Reason'),
            ),
          ],
        ),
      ),
    );
  }
}
