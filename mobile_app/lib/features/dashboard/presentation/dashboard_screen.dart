import 'package:flutter/material.dart';
import '../../../core/theme/celadon_colors.dart';
import '../../attendance/presentation/attendance_view.dart';
import '../../auth/data/user_model.dart';
import '../../calendar/presentation/calendar_view.dart';
import '../../company/presentation/company_dashboard_view.dart';
import '../../profile/presentation/profile_view.dart';
import '../../tasks/presentation/tasks_view.dart';
import 'employee_dashboard_view.dart';

/// Role-Based Main App Shell with Bottom Navigation
///
/// Unifies the screens from the "8. Premium Celadon" design specification:
/// - Tab 0: Home (Screen 3: Employee Dashboard or Screen 8: Company Dashboard)
/// - Tab 1: Tasks (Screen 6: Tasks Screen with priority filters & badges)
/// - Tab 2: Calendar & Attendance (Screen 5: Calendar & Screen 4: Attendance)
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CeladonColors.background,
      body: IndexedStack(
        index: _currentTabIndex,
        children: [
          // Tab 0: Home View
          _buildHomeView(),

          // Tab 1: Tasks View (Screen 6)
          TasksView(
            onBack: () => _navigateToTab(0),
          ),

          // Tab 2: Calendar & Attendance View (Screen 5 & Screen 4)
          _showAttendanceSubScreen
              ? AttendanceView(
                  onBack: () => setState(() => _showAttendanceSubScreen = false),
                )
              : CalendarView(
                  onBack: () => _navigateToTab(0),
                ),

          // Tab 3: Profile / Sidebar View (Screen 7)
          ProfileView(
            user: _currentUser,
            onLogout: widget.onLogout,
            onNavigateToTab: (index) {
              if (index == 2) {
                setState(() {
                  _currentTabIndex = 2;
                  _showAttendanceSubScreen = true;
                });
              } else {
                _navigateToTab(index);
              }
            },
            onUserUpdated: (updatedUser) {
              setState(() => _currentUser = updatedUser);
            },
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: const Border(
            top: BorderSide(color: CeladonColors.borderLight, width: 1.2),
          ),
          boxShadow: const [
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
    // If the user is a Company Owner/Admin or SuperAdmin, provide Company Dashboard
    // with toggle option to preview Employee Dashboard
    final isCompanyLeadership =
        _currentUser.role == 'owner' || _currentUser.role == 'admin';

    if (isCompanyLeadership) {
      return CompanyDashboardView(
        user: _currentUser,
        onNavigateToTab: _navigateToTab,
      );
    }

    return EmployeeDashboardView(
      user: _currentUser,
      onNavigateToTab: (index) {
        if (index == 2) {
          setState(() {
            _currentTabIndex = 2;
            _showAttendanceSubScreen = true;
          });
        } else {
          _navigateToTab(index);
        }
      },
    );
  }

  Widget _buildNavItem({
    required int index,
    required String label,
    required IconData icon,
    required IconData activeIcon,
  }) {
    final isSelected = _currentTabIndex == index;

    return InkWell(
      onTap: () => _navigateToTab(index),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? activeIcon : icon,
              size: 22,
              color: isSelected ? CeladonColors.primary : CeladonColors.textMuted,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? CeladonColors.primary : CeladonColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
