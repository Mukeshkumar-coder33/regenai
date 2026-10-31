import '../../auth/presentation/login_screen.dart';
import 'package:flutter/material.dart';
import '../../../core/storage/session_storage.dart';
import '../../../core/theme/celadon_colors.dart';
import '../../attendance/presentation/attendance_view.dart';
import '../../auth/data/user_model.dart';
import '../../calendar/presentation/calendar_view.dart';
import '../../company/presentation/company_dashboard_view.dart';
import '../../profile/presentation/app_drawer.dart';
import '../../profile/presentation/profile_view.dart';
import '../../superadmin/presentation/superadmin_dashboard_view.dart';
import '../../tasks/presentation/tasks_view.dart';
import 'employee_dashboard_view.dart';

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

class _DashboardScreenState extends State<DashboardScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _currentTabIndex = 0;
  late UserModel _currentUser;
  bool _showAttendanceSubScreen = false;

  @override
  void initState() {
    super.initState();
    _currentUser = widget.user;
  }

  void _navigateToTab(int index) {
    setState(() {
      _currentTabIndex = index;
      _showAttendanceSubScreen = false;
    });
  }

  void _openAttendance() {
    setState(() {
      _currentTabIndex = 2;
      _showAttendanceSubScreen = true;
    });
  }

  void _openDrawer() {
    _scaffoldKey.currentState?.openDrawer();
  }

  Future<void> _handleLogout() async {
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
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: CeladonColors.background,
      drawer: AppDrawer(
        user: _currentUser,
        onLogout: _handleLogout,
        onNavigateToTab: _navigateToTab,
        onOpenAttendance: _openAttendance,
        currentTabIndex: _currentTabIndex,
      ),
      body: IndexedStack(
        index: _currentTabIndex,
        children: [
          // Tab 0: Home View (Role-based: Employee, Company, or Super Admin)
          _buildHomeView(),

          // Tab 1: Tasks View (Screen 6)
          TasksView(
            onOpenDrawer: _openDrawer,
            onBack: () => _navigateToTab(0),
          ),

          // Tab 2: Calendar & Attendance View (Screen 5 & Screen 4)
          _buildCalendarAndAttendanceTab(),

          // Tab 3: Profile / Sidebar View (Screen 7)
          ProfileView(
            user: _currentUser,
            onLogout: _handleLogout,
            onNavigateToTab: _navigateToTab,
            onOpenAttendance: _openAttendance,
            onUserUpdated: (updatedUser) {
              setState(() => _currentUser = updatedUser);
            },
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: CeladonColors.borderLight, width: 1.2),
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0x0A2D6A4F),
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
              children: [
                _buildNavItem(
                  index: 0,
                  label: 'Home',
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home_rounded,
                ),
                _buildNavItem(
                  index: 1,
                  label: 'Tasks',
                  icon: Icons.assignment_outlined,
                  activeIcon: Icons.assignment_rounded,
                ),
                _buildNavItem(
                  index: 2,
                  label: 'Calendar',
                  icon: Icons.calendar_today_outlined,
                  activeIcon: Icons.calendar_today_rounded,
                ),
                _buildNavItem(
                  index: 3,
                  label: 'Profile',
                  icon: Icons.person_outline_rounded,
                  activeIcon: Icons.person_rounded,
                ),
              ],
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
        },
      );
    }

    // 3. Employee / Staff Dashboard (staff, intern)
    return EmployeeDashboardView(
      user: _currentUser,
      onOpenDrawer: _openDrawer,
      onLogout: _handleLogout,
      onOpenAttendance: _openAttendance,
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
              border: Border.all(color: CeladonColors.borderLight, width: 1.2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x082D6A4F),
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
                        color: !_showAttendanceSubScreen ? CeladonColors.primaryDark : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: !_showAttendanceSubScreen
                            ? [
                                BoxShadow(
                                  color: CeladonColors.primaryDark.withValues(alpha: 0.25),
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
                            color: !_showAttendanceSubScreen ? Colors.white : CeladonColors.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Calendar',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: !_showAttendanceSubScreen ? Colors.white : CeladonColors.textSecondary,
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
                        color: _showAttendanceSubScreen ? CeladonColors.primaryDark : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: _showAttendanceSubScreen
                            ? [
                                BoxShadow(
                                  color: CeladonColors.primaryDark.withValues(alpha: 0.25),
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
                            color: _showAttendanceSubScreen ? Colors.white : CeladonColors.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Attendance (5m GPS)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _showAttendanceSubScreen ? Colors.white : CeladonColors.textSecondary,
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
    final isSelected = _currentTabIndex == index;

    if (isSelected) {
      return InkWell(
        onTap: () => _navigateToTab(index),
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: CeladonColors.primaryDark,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(activeIcon, size: 20, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
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
      onTap: () => _navigateToTab(index),
      borderRadius: BorderRadius.circular(24),
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
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: CeladonColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
