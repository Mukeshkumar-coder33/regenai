import 'package:flutter/material.dart';
import '../../../core/storage/session_storage.dart';
import '../../../core/theme/celadon_colors.dart';
import '../../auth/data/user_model.dart';
import '../../calendar/data/leave_service.dart';
import '../../dashboard/data/leave_model.dart';

/// Screen: Leave Request Form & History Screen (Live MongoDB Integration)
class LeaveRequestView extends StatefulWidget {
  final VoidCallback? onBack;
  final UserModel? user;

  const LeaveRequestView({super.key, this.onBack, this.user});

  @override
  State<LeaveRequestView> createState() => _LeaveRequestViewState();
}

class _LeaveRequestViewState extends State<LeaveRequestView> {
  final _formKey = GlobalKey<FormState>();
  final LeaveService _leaveService = LeaveService();

  String _selectedLeaveType = 'casual';
  final TextEditingController _reasonController = TextEditingController();
  DateTime _startDate = DateTime.now().add(const Duration(days: 1));
  DateTime _endDate = DateTime.now().add(const Duration(days: 2));

  bool _isLoading = true;
  bool _isSubmitting = false;
  List<LeaveModel> _leaves = [];
  UserModel? _currentUser;

  @override
  void initState() {
    super.initState();
    _loadUserLeaves();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadUserLeaves() async {
    setState(() => _isLoading = true);
    final user = widget.user ?? await SessionStorage.getUserSession();
    _currentUser = user;

    if (user != null) {
      final list = await _leaveService.getUserLeaves(user.userId.isNotEmpty ? user.userId : user.id);
      if (mounted) {
        setState(() {
          _leaves = list;
          _isLoading = false;
        });
      }
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    final sStr = "${_startDate.year}-${_startDate.month.toString().padLeft(2, '0')}-${_startDate.day.toString().padLeft(2, '0')}";
    final eStr = "${_endDate.year}-${_endDate.month.toString().padLeft(2, '0')}-${_endDate.day.toString().padLeft(2, '0')}";

    try {
      final created = await _leaveService.applyLeave(
        type: _selectedLeaveType,
        startDate: sStr,
        endDate: eStr,
        reason: _reasonController.text.trim(),
        userId: _currentUser?.userId.isNotEmpty == true ? _currentUser!.userId : _currentUser?.id,
      );

      if (mounted) {
        setState(() {
          _leaves.insert(0, created);
          _isSubmitting = false;
          _reasonController.clear();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Leave request submitted successfully for manager approval.'),
            backgroundColor: CeladonColors.primary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit leave: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryGreen = Color(0xFF1B5E3F);

    return Scaffold(
      backgroundColor: CeladonColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadUserLeaves,
          color: primaryGreen,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Top Bar
                Row(
                  children: [
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
                          Navigator.maybePop(context);
                        }
                      },
                    ),
                    const Expanded(
                      child: Text(
                        'Leave Requests',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: CeladonColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 2. Application Form Card
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: CeladonColors.borderLight),
                    boxShadow: const [
                      BoxShadow(color: Color(0x06000000), blurRadius: 8, offset: Offset(0, 2)),
                    ],
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Apply for Leave',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1B5E3F)),
                        ),
                        const SizedBox(height: 14),

                        // Leave Type
                        DropdownButtonFormField<String>(
                          initialValue: _selectedLeaveType,
                          decoration: InputDecoration(
                            labelText: 'Leave Type',
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'casual', child: Text('Casual Leave')),
                            DropdownMenuItem(value: 'sick', child: Text('Sick Leave')),
                            DropdownMenuItem(value: 'earned', child: Text('Earned Leave')),
                            DropdownMenuItem(value: 'unpaid', child: Text('Unpaid Leave')),
                          ],
                          onChanged: (v) => setState(() => _selectedLeaveType = v ?? 'casual'),
                        ),
                        const SizedBox(height: 12),

                        // Date Pickers Row
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.calendar_today_rounded, size: 15),
                                label: Text(
                                  "${_startDate.year}-${_startDate.month.toString().padLeft(2, '0')}-${_startDate.day.toString().padLeft(2, '0')}",
                                  style: const TextStyle(fontSize: 11.5),
                                ),
                                onPressed: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: _startDate,
                                    firstDate: DateTime.now().subtract(const Duration(days: 7)),
                                    lastDate: DateTime.now().add(const Duration(days: 365)),
                                  );
                                  if (picked != null) setState(() => _startDate = picked);
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.calendar_today_rounded, size: 15),
                                label: Text(
                                  "${_endDate.year}-${_endDate.month.toString().padLeft(2, '0')}-${_endDate.day.toString().padLeft(2, '0')}",
                                  style: const TextStyle(fontSize: 11.5),
                                ),
                                onPressed: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: _endDate,
                                    firstDate: _startDate,
                                    lastDate: DateTime.now().add(const Duration(days: 365)),
                                  );
                                  if (picked != null) setState(() => _endDate = picked);
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Reason Field
                        TextFormField(
                          controller: _reasonController,
                          maxLines: 2,
                          decoration: InputDecoration(
                            labelText: 'Reason for Leave *',
                            hintText: 'Provide brief explanation...',
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) return 'Please specify a reason';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        ElevatedButton(
                          onPressed: _isSubmitting ? null : _handleSubmit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryGreen,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: _isSubmitting
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Text('Submit Request', style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // 3. Past Leave Requests Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Leave Request History',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: CeladonColors.textPrimary),
                    ),
                    Text(
                      '${_leaves.length} records',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: CeladonColors.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 4. Past Leave List
                if (_isLoading)
                  const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(color: primaryGreen)))
                else if (_leaves.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 36),
                    alignment: Alignment.center,
                    child: const Text('No leave requests submitted yet', style: TextStyle(color: CeladonColors.textMuted)),
                  )
                else
                  ..._leaves.map((l) => _buildLeaveHistoryCard(l)),

                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLeaveHistoryCard(LeaveModel leave) {
    Color statusColor = const Color(0xFFD97706);
    Color statusBg = const Color(0xFFFEF3C7);

    if (leave.isApproved) {
      statusColor = const Color(0xFF15803D);
      statusBg = const Color(0xFFDEF7EC);
    } else if (leave.isRejected) {
      statusColor = const Color(0xFFDC2626);
      statusBg = const Color(0xFFFEE2E2);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CeladonColors.borderLight),
        boxShadow: const [BoxShadow(color: Color(0x04000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${leave.type.toUpperCase()} LEAVE',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: CeladonColors.textPrimary),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(8)),
                child: Text(
                  leave.status.toUpperCase(),
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: statusColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.date_range_rounded, size: 14, color: CeladonColors.textMuted),
              const SizedBox(width: 6),
              Text(
                '${leave.startDate} to ${leave.endDate}',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: CeladonColors.textSecondary),
              ),
            ],
          ),
          if (leave.reason != null && leave.reason!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              leave.reason!,
              style: const TextStyle(fontSize: 12, color: CeladonColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}
