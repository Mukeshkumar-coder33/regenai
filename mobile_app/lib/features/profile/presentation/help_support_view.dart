import 'package:flutter/material.dart';
import '../../../core/theme/celadon_colors.dart';

/// Screen: Help & Enterprise Support Screen
///
/// Features:
/// - Light mint background with modern corporate styling
/// - Contact options: HR Helpdesk, IT Support, FAQ
/// - Accordion FAQ items for employee policies, leave rules, and attendance
class HelpSupportView extends StatelessWidget {
  final VoidCallback? onBack;

  const HelpSupportView({super.key, this.onBack});

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
                      if (onBack != null) {
                        onBack!();
                      } else {
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                  const Text(
                    'Help & Support',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: CeladonColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 2. Quick Contact Cards
              Row(
                children: [
                  Expanded(
                    child: _buildContactCard(
                      context: context,
                      icon: Icons.support_agent_rounded,
                      title: 'HR Helpdesk',
                      subtitle: 'hr@regen.com',
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Opening email to hr@regen.com...'),
                            backgroundColor: CeladonColors.primary,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildContactCard(
                      context: context,
                      icon: Icons.computer_rounded,
                      title: 'IT Support',
                      subtitle: 'Ext: #404',
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Connecting to ReGen IT Helpdesk...'),
                            backgroundColor: CeladonColors.primary,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // 3. FAQ Section
              const Text(
                'Frequently Asked Questions',
                style: TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w800,
                  color: CeladonColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),

              _buildFaqItem(
                question: 'How do I check in and check out each day?',
                answer: 'Navigate to the Attendance tab in the bottom bar or drawer. Tap the "Check In" button when arriving at the office. Geofencing ensures you are within company boundaries.',
              ),
              const SizedBox(height: 10),
              _buildFaqItem(
                question: 'How many days in advance should I submit a leave request?',
                answer: 'Standard annual leave requests should be submitted at least 3 business days in advance through the Leave Request module in the side drawer.',
              ),
              const SizedBox(height: 10),
              _buildFaqItem(
                question: 'How do I view my assigned tasks and change their status?',
                answer: 'Select the Tasks tab from the bottom navigation bar. Tap on any task card to inspect details and tap "Mark as Completed" or "Complete Task".',
              ),
              const SizedBox(height: 10),
              _buildFaqItem(
                question: 'Who can switch between Super Admin and EMS workspace modes?',
                answer: 'Only authorized accounts with Owner or SuperAdmin privileges have access to workspace switcher in the Profile tab.',
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContactCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: CeladonColors.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: CeladonColors.primary, size: 22),
            ),
            const SizedBox(height: 12),
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
    );
  }

  Widget _buildFaqItem({required String question, required String answer}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CeladonColors.borderLight),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Text(
          question,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: CeladonColors.textPrimary,
          ),
        ),
        iconColor: CeladonColors.primary,
        collapsedIconColor: CeladonColors.textSecondary,
        children: [
          Text(
            answer,
            style: const TextStyle(
              fontSize: 13,
              height: 1.45,
              color: CeladonColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
