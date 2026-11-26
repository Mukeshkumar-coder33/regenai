import 'package:flutter/material.dart';
import '../theme/celadon_colors.dart';

/// Canonical page header matching the exact Company Calendar header & subheader
/// layout, alignment, and vertical spacing across all roles and views.
class ReGenPageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final String backTooltip;
  final Widget? trailing;
  final Widget? titleBadge;
  final Color? foregroundColor;
  final Color? subtitleColor;

  const ReGenPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.backTooltip = 'Back',
    this.trailing,
    this.titleBadge,
    this.foregroundColor,
    this.subtitleColor,
  });

  @override
  Widget build(BuildContext context) {
    final titleClr = foregroundColor ?? CeladonColors.textPrimary;
    final subClr = subtitleColor ?? CeladonColors.textMuted;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (onBack != null) ...[
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: Icon(
              Icons.arrow_back_rounded,
              color: titleClr,
              size: 22,
            ),
            tooltip: backTooltip,
            onPressed: onBack,
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: titleClr,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  if (titleBadge != null) ...[
                    const SizedBox(width: 8),
                    titleBadge!,
                  ],
                ],
              ),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: subClr,
                    height: 1.25,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing!,
        ],
      ],
    );
  }
}
