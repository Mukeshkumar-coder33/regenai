import 'package:flutter/material.dart';
import '../theme/celadon_colors.dart';

/// Premium Celadon Reusable Card
class CeladonCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Border? border;

  const CeladonCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = Container(
      decoration: BoxDecoration(
        color: color ?? CeladonColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: border ?? Border.all(color: CeladonColors.border, width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x081B5E4B),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      padding: padding,
      child: child,
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: content,
      );
    }

    return content;
  }
}
