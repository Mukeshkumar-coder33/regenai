import 'package:flutter/material.dart';
import '../theme/celadon_colors.dart';

/// ReGen Brand Logo Emblem Widget
///
/// Displays the official ReGen badge with crisp emerald styling,
/// matching the global ReGen White + Charcoal + Emerald Green theme.
class BrandLogo extends StatelessWidget {
  final double size;
  final double borderRadius;
  final bool showBackground;
  final Color? backgroundColor;

  const BrandLogo({
    super.key,
    this.size = 64,
    this.borderRadius = 18,
    this.showBackground = true,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor ?? CeladonColors.primary,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: CeladonColors.border,
          width: 1.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1015803D),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          'R',
          style: TextStyle(
            fontSize: size * 0.52,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: -1,
          ),
        ),
      ),
    );
  }
}
