import '../../auth/presentation/login_screen.dart';
import 'package:flutter/material.dart';
import '../../../core/storage/session_storage.dart';
import '../../../core/theme/celadon_colors.dart';
import '../../attendance/presentation/attendance_view.dart';
import '../../auth/data/user_model.dart';
import '../../calendar/presentation/calendar_view.dart';
import '../../company/presentation/company_dashboard_view.dart';
import '../../policies/data/policy_service.dart';
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

  final PolicyService _policyService = PolicyService();
  EmployeePolicyStatus? _policyStatus;
  bool _isLoadingPolicy = false;
  bool _isPolicySubmitting = false;

  @override
  void initState() {
    super.initState();
    _currentUser = widget.user;
    if (!_currentUser.isCompanyAdmin && !_currentUser.isSuperAdmin) {
      _checkPolicyStatus();
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
    // Dedicated high-end Company Workspace Experience matching ReGen Design Specification
    if (_currentUser.isCompanyAdmin) {
      return CompanyDashboardView(
        user: _currentUser,
        onOpenDrawer: _openDrawer,
        onLogout: _handleLogout,
        onUserUpdated: (updatedUser) {
          setState(() => _currentUser = updatedUser);
        },
      );
    }

    // Mandatory Employee Policy Barrier (Locked until acknowledged or owner allows)
    if (!_currentUser.isSuperAdmin &&
        _policyStatus != null &&
        (_policyStatus!.hasBlockedPolicy || _policyStatus!.pendingPolicies.isNotEmpty)) {
      return _buildPolicyBarrierScreen();
    }

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
            user: _currentUser,
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
      backgroundColor: const Color(0xFF03140E),
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
                      gradient: LinearGradient(
                        colors: isBlocked
                            ? [const Color(0xFFDC2626), const Color(0xFF991B1B)]
                            : [const Color(0xFF10B981), const Color(0xFF059669)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (isBlocked ? const Color(0xFFEF4444) : const Color(0xFF10B981))
                              .withValues(alpha: 0.35),
                          blurRadius: 18,
                        ),
                      ],
                    ),
                    child: Icon(
                      isBlocked ? Icons.lock_clock_rounded : Icons.gavel_rounded,
                      color: Colors.white,
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
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 8),

                Text(
                  isBlocked
                      ? 'Your work access is paused pending management review.'
                      : 'Please review and acknowledge the organizational policy to continue working.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Color(0xFFBACCC3), height: 1.4),
                ),
                const SizedBox(height: 24),

                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF072118),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isBlocked
                          ? const Color(0xFFEF4444).withValues(alpha: 0.4)
                          : const Color(0xFF10B981).withValues(alpha: 0.3),
                    ),
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
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                            ),
                          ),
                          if (effectiveDate.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF34D399).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                effectiveDate,
                                style: const TextStyle(color: Color(0xFF34D399), fontSize: 10.5, fontWeight: FontWeight.w600),
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
                              style: const TextStyle(fontSize: 12.5, color: Color(0xFFBACCC3), height: 1.45),
                            ),
                          ),
                        ),
                      ],
                      if (isBlocked && declineReason != null && declineReason.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1F0F12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Submitted Decline Reason:',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFF87171)),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '"$declineReason"',
                                style: const TextStyle(fontSize: 12, color: Color(0xFFFCA5A5), fontStyle: FontStyle.italic),
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
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _handleLogout,
                    icon: const Icon(Icons.logout_rounded, size: 18, color: Color(0xFF88A89A)),
                    label: const Text('Sign Out', style: TextStyle(color: Color(0xFF88A89A), fontSize: 13, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF1E3A2E)),
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
                                  const SnackBar(backgroundColor: Color(0xFF10B981), content: Text('Policy accepted. Workspace unlocked!')),
                                );
                                _checkPolicyStatus();
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(backgroundColor: Colors.red, content: Text('Failed to accept policy. Please try again.')),
                                );
                              }
                            }
                          },
                    icon: _isPolicySubmitting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_circle_outline_rounded, size: 18),
                    label: const Text('Allow & Continue to Work', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _isPolicySubmitting ? null : () => _showDeclineReasonDialog(policyId),
                    icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFFEF4444)),
                    label: const Text('Decline with Reason', style: TextStyle(color: Color(0xFFEF4444), fontSize: 13, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF7F1D1D)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: _handleLogout,
                    icon: const Icon(Icons.logout_rounded, size: 16, color: Color(0xFF88A89A)),
                    label: const Text('Sign Out', style: TextStyle(color: Color(0xFF88A89A), fontSize: 12.5)),
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
          backgroundColor: const Color(0xFF072118),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: const Color(0xFFEF4444).withValues(alpha: 0.4)),
          ),
          title: const Row(
            children: [
              Icon(Icons.report_problem_rounded, color: Color(0xFFEF4444), size: 22),
              SizedBox(width: 8),
              Text('Decline Policy Reason', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Please explain why you are declining this policy. Your reason will be submitted to the company owner for review, and your work access will be paused until approved.',
                style: TextStyle(fontSize: 12, color: Color(0xFFBACCC3)),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: reasonCtrl,
                maxLines: 4,
                cursorColor: const Color(0xFF34D399),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Enter your reason here...',
                  hintStyle: const TextStyle(color: Color(0xFF88A89A), fontSize: 12.5),
                  filled: true,
                  fillColor: const Color(0xFF04140F),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF1E3A2E)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF10B981)),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF88A89A))),
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
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white),
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
