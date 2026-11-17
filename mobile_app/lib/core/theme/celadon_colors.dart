import 'package:flutter/material.dart';

/// ReGen Global Colour System (White + Charcoal + Emerald Green)
///
/// Palette Specification:
/// - Main background: #F5F7F8
/// - Card and surface background: #FFFFFF
/// - Primary green: #15803D
/// - Secondary green: #16A34A
/// - Light green: #E8F5EC
/// - Green hover: #166534
/// - Green pressed: #14532D
/// - Primary text: #17212B
/// - Secondary text: #475569
/// - Muted text: #64748B
/// - Borders and dividers: #E2E8F0
/// - Search and input background: #F8FAFC
/// - Placeholder text: #94A3B8
/// - Disabled background: #F1F5F9
/// - Disabled text: #94A3B8
/// - Success: #15803D (bg: #E8F5EC)
/// - Warning: #D97706 (bg: #FFFBEB)
/// - Error: #DC2626 (bg: #FEF2F2)
/// - Information: #2563EB (bg: #EFF6FF)
abstract final class CeladonColors {
  // Primary Greens
  static const Color primary = Color(0xFF15803D);
  static const Color primarySecondary = Color(0xFF16A34A);
  static const Color primaryDark = Color(0xFF14532D);
  static const Color primaryHover = Color(0xFF166534);
  static const Color primaryPressed = Color(0xFF14532D);
  static const Color primaryLight = Color(0xFFE8F5EC);
  static const Color primaryContainer = Color(0xFFE8F5EC);

  // Backgrounds & Canvas
  static const Color background = Color(0xFFF5F7F8);
  static const Color backgroundGradientStart = Color(0xFFF5F7F8);
  static const Color backgroundGradientEnd = Color(0xFFF5F7F8);

  // Surface & Cards
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF8FAFC);
  static const Color cardBackground = Color(0xFFFFFFFF);

  // Borders & Dividers
  static const Color border = Color(0xFFE2E8F0);
  static const Color borderLight = Color(0xFFE2E8F0);
  static const Color divider = Color(0xFFE2E8F0);

  // Typography
  static const Color textPrimary = Color(0xFF17212B);
  static const Color textSecondary = Color(0xFF475569);
  static const Color textMuted = Color(0xFF64748B);
  static const Color textPlaceholder = Color(0xFF94A3B8);
  static const Color textDisabled = Color(0xFF94A3B8);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // Inputs & Search Boxes
  static const Color inputBackground = Color(0xFFF8FAFC);
  static const Color searchBackground = Color(0xFFF8FAFC);
  static const Color inputFocusBackground = Color(0xFFFFFFFF);
  static const Color inputBorder = Color(0xFFE2E8F0);
  static const Color inputFocusBorder = Color(0xFF15803D);

  // Disabled State
  static const Color disabledBackground = Color(0xFFF1F5F9);
  static const Color disabledText = Color(0xFF94A3B8);

  // Semantic & Status Colours
  static const Color success = Color(0xFF15803D);
  static const Color successLight = Color(0xFFE8F5EC);
  static const Color lightGreen = Color(0xFFE8F5EC);
  static const Color secondary = Color(0xFF16A34A);

  static const Color warning = Color(0xFFD97706);
  static const Color warningLight = Color(0xFFFFFBEB);

  static const Color error = Color(0xFFDC2626);
  static const Color errorLight = Color(0xFFFEF2F2);

  static const Color info = Color(0xFF2563EB);
  static const Color infoLight = Color(0xFFEFF6FF);

  static const Color badgeBg = Color(0xFFE8F5EC);
  static const Color badgeText = Color(0xFF15803D);

  // Soft Logout & Destructive Accents
  static const Color logoutBg = Color(0xFFFEF2F2);
  static const Color logoutText = Color(0xFFDC2626);

  static const Color glow = Color(0x1015803D);
  static const Color shadow = Color(0x0D000000);
}
