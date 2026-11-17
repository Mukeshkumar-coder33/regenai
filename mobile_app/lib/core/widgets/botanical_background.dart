import 'package:flutter/material.dart';
import '../theme/celadon_colors.dart';

/// ReGen Background Canvas
///
/// Provides a sleek, distraction-free corporate background canvas
/// adhering to the global White + Charcoal + Emerald Green theme.
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
    this.officeOpacity = 0.04,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: CeladonColors.background,
      child: child,
    );
  }
}
