import 'package:flutter/material.dart';
import '../theme/celadon_colors.dart';

/// ReGen Brand Logo Emblem Widget
///
/// Displays the official ReGen badge with crisp emerald styling,
/// matching the official ReGen visual design specification.
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
        gradient: backgroundColor != null
            ? null
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: CeladonColors.primaryGradient,
              ),
        color: backgroundColor,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22075438),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            'R',
            style: TextStyle(
              fontSize: size * 0.54,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              fontFamily: 'serif',
              letterSpacing: -0.5,
            ),
          ),
          Positioned(
            bottom: size * 0.22,
            child: Container(
              width: size * 0.36,
              height: (size * 0.04).clamp(1.5, 3.0),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
