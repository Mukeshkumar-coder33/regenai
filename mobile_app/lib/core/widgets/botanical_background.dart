import 'package:flutter/material.dart';
import '../theme/celadon_colors.dart';

/// Reusable Botanical Background Canvas
///
/// Draws the signature Premium Celadon gradient canvas with soft botanical
/// leaf curves in the corner margins, matching the UI reference designs.
class BotanicalBackground extends StatelessWidget {
  final Widget child;
  final bool showLeaves;

  const BotanicalBackground({
    super.key,
    required this.child,
    this.showLeaves = true,
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
          if (showLeaves) ...[
            // Top-left subtle botanical eucalyptus branch
            Positioned(
              top: -30,
              left: -30,
              child: CustomPaint(
                size: const Size(220, 220),
                painter: _BotanicalLeafPainter(
                  color: const Color(0xFF68A68A).withValues(alpha: 0.28),
                  angle: 0.45,
                ),
              ),
            ),
            // Bottom-right lush botanical eucalyptus branch
            Positioned(
              bottom: -20,
              right: -30,
              child: CustomPaint(
                size: const Size(250, 250),
                painter: _BotanicalLeafPainter(
                  color: const Color(0xFF2D6A4F).withValues(alpha: 0.24),
                  angle: 3.5,
                ),
              ),
            ),
            // Bottom-left subtle soft glow circle
            Positioned(
              bottom: 80,
              left: -70,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: CeladonColors.primaryContainer.withValues(alpha: 0.4),
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

class _BotanicalLeafPainter extends CustomPainter {
  final Color color;
  final double angle;

  _BotanicalLeafPainter({required this.color, required this.angle});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(angle);
    canvas.translate(-size.width / 2, -size.height / 2);

    final leafFill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final stemPaint = Paint()
      ..color = color.withValues(alpha: (color.a * 1.3).clamp(0.0, 1.0))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;

    final veinPaint = Paint()
      ..color = color.withValues(alpha: (color.a * 0.7).clamp(0.0, 1.0))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // 1. Curved Central Stem
    final stem = Path()
      ..moveTo(size.width * 0.05, size.height * 0.95)
      ..cubicTo(
        size.width * 0.25,
        size.height * 0.65,
        size.width * 0.55,
        size.height * 0.35,
        size.width * 0.92,
        size.height * 0.08,
      );
    canvas.drawPath(stem, stemPaint);

    // 2. Helper to draw an organic pointed botanical leaf
    void drawLeaf({
      required double startX,
      required double startY,
      required double tipX,
      required double tipY,
      required double width,
    }) {
      final dx = tipX - startX;
      final dy = tipY - startY;
      final midX = (startX + tipX) / 2;
      final midY = (startY + tipY) / 2;
      final perpX = -dy * 0.35;
      final perpY = dx * 0.35;

      final leafPath = Path()
        ..moveTo(startX, startY)
        ..quadraticBezierTo(midX + perpX, midY + perpY, tipX, tipY)
        ..quadraticBezierTo(midX - perpX, midY - perpY, startX, startY);

      canvas.drawPath(leafPath, leafFill);

      // Central vein
      final vein = Path()
        ..moveTo(startX, startY)
        ..lineTo(tipX, tipY);
      canvas.drawPath(vein, veinPaint);
    }

    // Terminal leaf at tip
    drawLeaf(
      startX: size.width * 0.85,
      startY: size.height * 0.14,
      tipX: size.width * 0.98,
      tipY: size.height * 0.02,
      width: 14,
    );

    // Pair 1 (Upper)
    drawLeaf(
      startX: size.width * 0.70,
      startY: size.height * 0.25,
      tipX: size.width * 0.88,
      tipY: size.height * 0.32,
      width: 18,
    );
    drawLeaf(
      startX: size.width * 0.62,
      startY: size.height * 0.32,
      tipX: size.width * 0.45,
      tipY: size.height * 0.18,
      width: 18,
    );

    // Pair 2 (Middle)
    drawLeaf(
      startX: size.width * 0.48,
      startY: size.height * 0.44,
      tipX: size.width * 0.72,
      tipY: size.height * 0.52,
      width: 22,
    );
    drawLeaf(
      startX: size.width * 0.40,
      startY: size.height * 0.52,
      tipX: size.width * 0.20,
      tipY: size.height * 0.38,
      width: 22,
    );

    // Pair 3 (Lower)
    drawLeaf(
      startX: size.width * 0.28,
      startY: size.height * 0.64,
      tipX: size.width * 0.54,
      tipY: size.height * 0.74,
      width: 24,
    );
    drawLeaf(
      startX: size.width * 0.20,
      startY: size.height * 0.75,
      tipX: size.width * 0.05,
      tipY: size.height * 0.60,
      width: 24,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

