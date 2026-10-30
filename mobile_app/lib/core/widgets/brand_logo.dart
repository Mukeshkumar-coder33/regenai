import 'package:flutter/material.dart';

/// ReGen Brand Logo Emblem Widget
///
/// Displays the official ReGen badge with stylized emerald 'R',
/// matching the brand design language.
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
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0F3A2E),
            Color(0xFF06231B),
          ],
        ),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: const Color(0xFF34D399).withValues(alpha: 0.35),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
          const BoxShadow(
            color: Color(0x60000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF6EE7B7),
              Color(0xFF10B981),
              Color(0xFF059669),
            ],
          ).createShader(bounds),
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
      ),
    );
  }
}
