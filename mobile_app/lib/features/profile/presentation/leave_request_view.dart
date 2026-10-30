import 'package:flutter/material.dart';
import '../../../core/theme/celadon_colors.dart';

/// Screen: Leave Request Form & History Screen
///
/// Features:
/// - Light mint background with clean executive office styling
/// - Leave balance card (Annual, Sick, Casual)
/// - Leave application form: Type, Date range, Reason
/// - Past leave requests with status badges (Approved, Pending, Rejected)
class LeaveRequestView extends StatefulWidget {
  final VoidCallback? onBack;

  const LeaveRequestView({super.key, this.onBack});

  @override
  State<LeaveRequestView> createState() => _LeaveRequestViewState();
}

class _LeaveRequestViewState extends State<LeaveRequestView> {
  final _formKey = GlobalKey<FormState>();
  String _selectedLeaveType = 'Annual Leave';
  final TextEditingController _reasonController = TextEditingController();
  final TextEditingController _datesController = TextEditingController(text: '24 Oct 2026 - 26 Oct 2026');

  final List<Map<String, String>> _pastLeaves = [
    {
      'type': 'Casual Leave',
      'dates': '16 Oct 2026',
      'days': '1 Day',
      'status': 'Approved',
      'reason': 'Personal errand',
    },
    {
      'type': 'Sick Leave',
      'dates': '02 Sep 2026 - 03 Sep 2026',
      'days': '2 Days',
      'status': 'Approved',
      'reason': 'Viral fever recovery',
    },
    {
      'type': 'Annual Leave',
      'dates': '12 Jul 2026 - 15 Jul 2026',
      'days': '4 Days',
      'status': 'Approved',
      'reason': 'Family vacation',
    },
  ];

  @override
  void dispose() {
    _reasonController.dispose();
    _datesController.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _pastLeaves.insert(0, {
        'type': _selectedLeaveType,
        'dates': _datesController.text,
        'days': '2 Days',
        'status': 'Pending Approval',
        'reason': _reasonController.text.trim().isNotEmpty
            ? _reasonController.text.trim()
            : 'General leave request',
      });
      _reasonController.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Leave request submitted successfully for manager approval.'),
        backgroundColor: CeladonColors.primary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CeladonColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
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
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                  const Text(
                    'Leave Request',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: CeladonColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 2. Leave Balance Summary
              Container(
                padding: const EdgeInsets.all(18),
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
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildBalanceItem('Annual', '14', 'days left'),
                    _buildDivider(),
                    _buildBalanceItem('Sick', '08', 'days left'),
                    _buildDivider(),
                    _buildBalanceItem('Casual', '04', 'days left'),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 3. New Leave Request Form Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: CeladonColors.borderLight),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x062D6A4F),
                      blurRadius: 10,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Apply for Leave',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: CeladonColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Leave Type Dropdown
                      const Text(
                        'Leave Type',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: CeladonColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedLeaveType,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.category_outlined, color: CeladonColors.primary, size: 20),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: CeladonColors.border),
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'Annual Leave', child: Text('Annual Leave')),
                          DropdownMenuItem(value: 'Sick Leave', child: Text('Sick Leave')),
                          DropdownMenuItem(value: 'Casual Leave', child: Text('Casual Leave')),
                          DropdownMenuItem(value: 'Unpaid Leave', child: Text('Unpaid Leave')),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedLeaveType = val);
                        },
                      ),
                      const SizedBox(height: 14),

                      // Dates
                      const Text(
                        'Dates',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: CeladonColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _datesController,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.date_range_outlined, color: CeladonColors.primary, size: 20),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: CeladonColors.border),
                          ),
                        ),
                        validator: (v) => v == null || v.isEmpty ? 'Please specify dates' : null,
                      ),
                      const SizedBox(height: 14),

                      // Reason
                      const Text(
                        'Reason (Optional)',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: CeladonColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _reasonController,
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText: 'Brief explanation for management...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: CeladonColors.border),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _handleSubmit,
                          child: const Text('Submit Leave Request'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // 4. Past Requests Section
              const Text(
                'Recent Requests',
                style: TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w800,
                  color: CeladonColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),

              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _pastLeaves.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final req = _pastLeaves[index];
                  final isApproved = req['status'] == 'Approved';
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: CeladonColors.borderLight),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: CeladonColors.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.event_note_outlined, color: CeladonColors.primary, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                req['type']!,
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  color: CeladonColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${req['dates']} • ${req['days']}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: CeladonColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isApproved ? const Color(0xFFD8F3DC) : const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            req['status']!,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: isApproved ? CeladonColors.primary : const Color(0xFFD97706),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBalanceItem(String label, String count, String sub) {
    return Column(
      children: [
        Text(
          count,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: CeladonColors.primary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: CeladonColors.textPrimary,
          ),
        ),
        Text(
          sub,
          style: const TextStyle(
            fontSize: 11,
            color: CeladonColors.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 40,
      color: CeladonColors.divider,
    );
  }
}
