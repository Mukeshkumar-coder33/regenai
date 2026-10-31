import 'package:flutter/material.dart';
import '../theme/celadon_colors.dart';

/// Premium Modern Office Background Canvas
///
/// Provides a sleek corporate gradient canvas with optional subtle AI-generated
/// office atmosphere overlay and geometric ambient accents.
/// Strictly free of botanical leaves or floral elements.
class BotanicalBackground extends StatelessWidget {
  final Widget child;
  final bool showLeaves; // Maintained for backwards compatibility
  final bool showOfficeBackdrop;
  final double officeOpacity;

  const BotanicalBackground({
    super.key,
    required this.child,
    this.showLeaves = true,
    this.showOfficeBackdrop = false,
    this.officeOpacity = 0.12,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            CeladonColors.backgroundGradientStart,
            CeladonColors.background,
            CeladonColors.backgroundGradientEnd,
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Optional AI-generated office atmosphere
          if (showOfficeBackdrop)
            Positioned.fill(
              child: Opacity(
                opacity: officeOpacity,
                child: Image.asset(
                  'assets/images/office_auth.png',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                ),
              ),
            ),

          if (showLeaves) ...[
            // Top-left subtle architectural geometric ambient accent
            Positioned(
              top: -60,
              left: -60,
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      CeladonColors.primaryLight.withValues(alpha: 0.12),
                      CeladonColors.primary.withValues(alpha: 0.04),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // Top-right delicate geometric grid watermark
            Positioned(
              top: 20,
              right: 16,
              child: CustomPaint(
                size: const Size(120, 120),
                painter: _CorporateGridPainter(
                  color: CeladonColors.primary.withValues(alpha: 0.04),
                ),
              ),
            ),

            // Bottom-right subtle executive corner glow
            Positioned(
              bottom: -40,
              right: -40,
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      CeladonColors.primary.withValues(alpha: 0.08),
                      CeladonColors.primaryDark.withValues(alpha: 0.03),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ],
          child,
        ],
      ),
    );
  }
}

/// Subtle corporate architectural grid accent (clean lines, no botanicals)
class _CorporateGridPainter extends CustomPainter {
  final Color color;

  _CorporateGridPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    const step = 20.0;
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
