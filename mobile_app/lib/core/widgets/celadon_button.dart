import 'package:flutter/material.dart';
import '../theme/celadon_colors.dart';

/// ReGen Button Component
class CeladonButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isOutlined;
  final bool isSecondary;
  final IconData? icon;

  const CeladonButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
    this.isOutlined = false,
    this.isSecondary = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    if (isSecondary) {
      return OutlinedButton(
        onPressed: isLoading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: CeladonColors.textPrimary,
          side: const BorderSide(color: CeladonColors.border, width: 1.0),
          disabledBackgroundColor: CeladonColors.disabledBackground,
          disabledForegroundColor: CeladonColors.disabledText,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
        child: _buildContent(context, CeladonColors.textPrimary, iconColor: CeladonColors.primary),
      );
    }

    if (isOutlined) {
      return OutlinedButton(
        onPressed: isLoading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: CeladonColors.primary,
          side: const BorderSide(color: CeladonColors.primary, width: 1.2),
          disabledBackgroundColor: CeladonColors.disabledBackground,
          disabledForegroundColor: CeladonColors.disabledText,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
        child: _buildContent(context, CeladonColors.primary),
      );
    }

    return ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: CeladonColors.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: CeladonColors.disabledBackground,
        disabledForegroundColor: CeladonColors.disabledText,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      ),
      child: _buildContent(context, Colors.white),
    );
  }

  Widget _buildContent(BuildContext context, Color textColor, {Color? iconColor}) {
    if (isLoading) {
      return SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2.2,
          valueColor: AlwaysStoppedAnimation<Color>(textColor),
        ),
      );
    }

    if (icon != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: iconColor ?? textColor),
          const SizedBox(width: 8),
          Text(text, style: TextStyle(color: textColor, fontWeight: FontWeight.w700)),
        ],
      );
    }

    return Text(text, style: TextStyle(color: textColor, fontWeight: FontWeight.w700));
  }
}
