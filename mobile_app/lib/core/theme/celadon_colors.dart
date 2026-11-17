import 'package:flutter/material.dart';

/// ReGen Global Colour System (Premium Emerald Green + Clean White + Soft Mint)
///
/// Palette Specification:
/// - Primary Emerald: #087A4B
/// - Deep Forest Green: #07563B
/// - Dark Green: #06452F
/// - Soft Mint: #E8F3EC
/// - Light Green: #F1F7F3
/// - Main Application Background: #F5F7F6
/// - Secondary Background: #EFF3F1
/// - Card Background: #FFFFFF
/// - Input Background: #F8FAF9
/// - Primary Text: #17231F
/// - Secondary Text: #52615B
/// - Muted Text: #829089
/// - White Text: #FFFFFF
/// - Default Border: #E1E8E4
/// - Subtle Green Border: #C9DED1
/// - Card Shadow: Very soft neutral shadow
/// - Focus Border: #087A4B
/// - Success: #16834A
/// - Warning: #E7A52B
/// - Danger / Error: #DC4C4C
/// - Information: #3186C8
/// - Teal: #24A6A0
abstract final class CeladonColors {
  // Primary Greens
  static const Color primary = Color(0xFF087A4B);
  static const Color deepForest = Color(0xFF07563B);
  static const Color darkGreen = Color(0xFF06452F);
  static const Color primaryDark = Color(0xFF07563B);
  static const Color primarySecondary = Color(0xFF07563B);
  static const Color primaryHover = Color(0xFF07563B);
  static const Color primaryPressed = Color(0xFF06452F);
  static const Color primaryLight = Color(0xFFE8F3EC);
  static const Color primaryContainer = Color(0xFFE8F3EC);
  static const Color softMint = Color(0xFFE8F3EC);
  static const Color lightGreen = Color(0xFFF1F7F3);

  // Backgrounds & Canvas
  static const Color background = Color(0xFFF5F7F6);
  static const Color secondaryBackground = Color(0xFFEFF3F1);
  static const Color backgroundGradientStart = Color(0xFFF5F7F6);
  static const Color backgroundGradientEnd = Color(0xFFEFF3F1);

  // Surface & Cards
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFEFF3F1);
  static const Color cardBackground = Color(0xFFFFFFFF);

  // Borders & Dividers
  static const Color border = Color(0xFFE1E8E4);
  static const Color borderLight = Color(0xFFE1E8E4);
  static const Color borderSubtle = Color(0xFFC9DED1);
  static const Color borderSubtleGreen = Color(0xFFC9DED1);
  static const Color divider = Color(0xFFE1E8E4);

  // Typography
  static const Color textPrimary = Color(0xFF17231F);
  static const Color textSecondary = Color(0xFF52615B);
  static const Color textMuted = Color(0xFF829089);
  static const Color textPlaceholder = Color(0xFF829089);
  static const Color textDisabled = Color(0xFF829089);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // Inputs & Search Boxes
  static const Color inputBackground = Color(0xFFF8FAF9);
  static const Color searchBackground = Color(0xFFF8FAF9);
  static const Color inputFocusBackground = Color(0xFFFFFFFF);
  static const Color inputBorder = Color(0xFFE1E8E4);
  static const Color inputFocusBorder = Color(0xFF087A4B);

  // Disabled State
  static const Color disabledBackground = Color(0xFFEFF3F1);
  static const Color disabledText = Color(0xFF829089);

  // Semantic & Status Colours
  static const Color success = Color(0xFF16834A);
  static const Color successLight = Color(0xFFE8F3EC);
  static const Color secondary = Color(0xFF07563B);

  static const Color warning = Color(0xFFE7A52B);
  static const Color warningLight = Color(0xFFFEF9EE);

  static const Color error = Color(0xFFDC4C4C);
  static const Color errorLight = Color(0xFFFDF2F2);
  static const Color danger = Color(0xFFDC4C4C);

  static const Color info = Color(0xFF3186C8);
  static const Color infoLight = Color(0xFFF0F6FB);
  static const Color information = Color(0xFF3186C8);

  static const Color teal = Color(0xFF24A6A0);
  static const Color tealLight = Color(0xFFE9F6F5);

  static const Color badgeBg = Color(0xFFE8F3EC);
  static const Color badgeText = Color(0xFF087A4B);

  // Soft Logout & Destructive Accents
  static const Color logoutBg = Color(0xFFFDF2F2);
  static const Color logoutText = Color(0xFFDC4C4C);

  static const Color glow = Color(0x10087A4B);
  static const Color shadow = Color(0x0A000000);
  static const Color cardShadow = Color(0x08000000);
}
