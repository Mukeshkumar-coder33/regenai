import 'package:flutter/material.dart';
import '../theme/celadon_colors.dart';

/// ReGen Brand Logo Emblem Widget
///
/// Displays the official ReGen glowing logo inside a rounded celadon badge,
/// matching Screen 1, Screen 2, and Screen 8 of the UI specification.
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
    final effectiveBg = backgroundColor ??
        (showBackground ? const Color(0xFF0F3A2E) : Colors.transparent);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: effectiveBg,
        borderRadius: BorderRadius.circular(borderRadius),
        border: showBackground
            ? Border.all(color: CeladonColors.border.withValues(alpha: 0.6), width: 1.2)
            : null,
        boxShadow: showBackground
            ? [
                BoxShadow(
                  color: const Color(0xFF0F3A2E).withValues(alpha: 0.16),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      padding: EdgeInsets.all(size * 0.12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius * 0.75),
        child: Image.asset(
          'assets/images/logo.png',
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            // Elegant fallback emblem if asset is loading or missing
            return Center(
              child: Text(
                'R',
                style: TextStyle(
                  fontSize: size * 0.5,
                  fontWeight: FontWeight.w900,
                  color: CeladonColors.primaryLight,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

