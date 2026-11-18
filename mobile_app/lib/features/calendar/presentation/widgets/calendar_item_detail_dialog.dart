import 'package:flutter/material.dart';
import '../../../../core/theme/celadon_colors.dart';

/// Professional enterprise modal displaying full details of a pinned
/// Company Event (Violet) or Official Holiday (Dark Grey) across both
/// Company and Employee calendars.
class CalendarItemDetailDialog {
  static const Color eventColor = Color(0xFF7C3AED);
  static const Color eventLightBg = Color(0xFFF3E8FF);
  static const Color eventBorder = Color(0xFFD8B4FE);

  static const Color holidayColor = CeladonColors.holidayDark; // #334155
  static const Color holidayLightBg = CeladonColors.holidayLight; // #F1F5F9
  static const Color holidayBorder = CeladonColors.holidayBorder; // #CBD5E1

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  static const List<String> _weekdays = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];

  static String formatReadableDate(String dateStr) {
    final clean = dateStr.contains('T') ? dateStr.split('T').first : dateStr;
    final parsed = DateTime.tryParse(clean);
    if (parsed == null) return clean;
    final wd = _weekdays[(parsed.weekday - 1).clamp(0, 6)];
    final mo = _months[(parsed.month - 1).clamp(0, 11)];
    return '$wd, ${parsed.day} $mo ${parsed.year}';
  }

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String date,
    required bool isEvent,
    String? description,
    bool salaryDeduction = false,
    VoidCallback? onDelete,
  }) {
    final accent = isEvent ? eventColor : holidayColor;
    final lightBg = isEvent ? eventLightBg : holidayLightBg;
    final borderClr = isEvent ? eventBorder : holidayBorder;
    final readableDate = formatReadableDate(date);
    final cleanDesc = (description ?? '').trim();
    final effectiveDesc = cleanDesc.isNotEmpty
        ? cleanDesc
        : (isEvent
            ? 'Official company event scheduled on this date. Attendance and regular shift hours apply as a normal working day.'
            : 'Official company holiday. No employee attendance or check-in is required on this date.');

    return showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: borderClr, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.16),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Colored Accent Header Band
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 18, 14, 16),
                  decoration: BoxDecoration(
                    color: lightBg,
                    border: Border(
                      bottom: BorderSide(color: borderClr, width: 1.0),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(13),
                          boxShadow: [
                            BoxShadow(
                              color: accent.withValues(alpha: 0.30),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Icon(
                          isEvent
                              ? Icons.event_available_rounded
                              : Icons.beach_access_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                isEvent ? 'COMPANY EVENT ★' : 'OFFICIAL HOLIDAY',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.7,
                                  color: accent,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: CeladonColors.textPrimary,
                                letterSpacing: -0.2,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 20,
                          color: Color(0xFF475569),
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                      ),
                    ],
                  ),
                ),

                // 2. Body Content
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Date & Status Info Card
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAF9),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: CeladonColors.border),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.calendar_today_rounded,
                                  size: 15,
                                  color: accent,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Date',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF475569),
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  readableDate,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                    color: CeladonColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Divider(
                                height: 1,
                                color: CeladonColors.divider,
                              ),
                            ),
                            Row(
                              children: [
                                Icon(
                                  isEvent
                                      ? Icons.work_outline_rounded
                                      : Icons.event_busy_rounded,
                                  size: 15,
                                  color: accent,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Schedule',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF475569),
                                  ),
                                ),
                                const Spacer(),
                                Flexible(
                                  child: Text(
                                    isEvent
                                        ? 'Normal Working Day'
                                        : 'Company-Wide Day Off',
                                    textAlign: TextAlign.end,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: accent,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (isEvent) ...[
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Divider(
                                  height: 1,
                                  color: CeladonColors.divider,
                                ),
                              ),
                              Row(
                                children: [
                                  Icon(
                                    salaryDeduction
                                        ? Icons.money_off_rounded
                                        : Icons.payments_outlined,
                                    size: 15,
                                    color: salaryDeduction
                                        ? CeladonColors.error
                                        : CeladonColors.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Salary Deduction',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF475569),
                                    ),
                                  ),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: salaryDeduction
                                          ? const Color(0xFFFEE2E2)
                                          : const Color(0xFFE8F3EC),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      salaryDeduction ? 'Yes' : 'No',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w800,
                                        color: salaryDeduction
                                            ? CeladonColors.error
                                            : CeladonColors.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Description Section
                      const Text(
                        'DESCRIPTION',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.9,
                          color: Color(0xFF475569),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: CeladonColors.border),
                        ),
                        child: Text(
                          effectiveDesc,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF334155),
                            height: 1.48,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Action Row
                      Row(
                        children: [
                          if (onDelete != null) ...[
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  onDelete();
                                },
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 16,
                                  color: CeladonColors.error,
                                ),
                                label: const Text(
                                  'Delete',
                                  style: TextStyle(
                                    color: CeladonColors.error,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                    color: Color(0xFFFECACA),
                                  ),
                                  backgroundColor: const Color(0xFFFEF2F2),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => Navigator.pop(ctx),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: accent,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'Close',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
