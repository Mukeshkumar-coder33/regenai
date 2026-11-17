import 'package:flutter/material.dart';

/// ReGen Visual Design System (Matching Official Image Spec)
///
/// Palette Specification:
/// - Primary Emerald: #096544 (gradient: #075438 -> #0B704C)
/// - Deep Forest Green: #075438
/// - Dark Green: #05402A
/// - Soft Mint: #EAF5EF
/// - Light Green: #F1F7F4
/// - Amber / Warm Accent: #D9822B (container: #FEF4E4)
/// - Teal Accent: #1DA190 (container: #E4F6F4)
/// - Main Application Background: #F3F6F5
/// - Secondary Background: #EDF2F0
/// - Card Background: #FFFFFF
/// - Input Background: #F7FAF8
/// - Primary Text: #101D19
/// - Secondary Text: #384842
/// - Muted Text: #6B7B74
/// - Placeholder Text: #8E9E97
/// - Default Border: #E4ECE8
/// - Subtle Green Border: #D2E2DA
/// - Card Shadow: Soft realistic neutral shadow
/// - Focus Border: #096544
abstract final class CeladonColors {
  // Primary Greens
  static const Color primary = Color(0xFF096544);
  static const Color primaryDark = Color(0xFF075438);
  static const Color primaryLight = Color(0xFFEAF5EF);
  static const Color primarySecondary = Color(0xFF0B704C);
  static const Color primaryHover = Color(0xFF075438);
  static const Color primaryPressed = Color(0xFF05402A);
  static const Color primaryContainer = Color(0xFFEAF5EF);
  static const Color deepForest = Color(0xFF075438);
  static const Color darkGreen = Color(0xFF05402A);
  static const Color softMint = Color(0xFFEAF5EF);
  static const Color lightGreen = Color(0xFFF1F7F4);

  // Gradient
  static const List<Color> primaryGradient = [
    Color(0xFF075438),
    Color(0xFF0B704C),
  ];

  // Backgrounds & Canvas
  static const Color background = Color(0xFFF3F6F5);
  static const Color secondaryBackground = Color(0xFFEDF2F0);
  static const Color backgroundGradientStart = Color(0xFFF3F6F5);
  static const Color backgroundGradientEnd = Color(0xFFEDF2F0);

  // Surface & Cards
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF7FAF8);
  static const Color cardBackground = Color(0xFFFFFFFF);

  // Borders & Dividers
  static const Color border = Color(0xFFE4ECE8);
  static const Color borderLight = Color(0xFFE4ECE8);
  static const Color borderSubtle = Color(0xFFD2E2DA);
  static const Color borderSubtleGreen = Color(0xFFD2E2DA);
  static const Color divider = Color(0xFFE4ECE8);

  // Typography
  static const Color textPrimary = Color(0xFF101D19);
  static const Color textSecondary = Color(0xFF384842);
  static const Color textMuted = Color(0xFF6B7B74);
  static const Color textPlaceholder = Color(0xFF8E9E97);
  static const Color textDisabled = Color(0xFF8E9E97);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // Inputs & Search Boxes
  static const Color inputBackground = Color(0xFFF7FAF8);
  static const Color searchBackground = Color(0xFFF7FAF8);
  static const Color inputFocusBackground = Color(0xFFFFFFFF);
  static const Color inputBorder = Color(0xFFE4ECE8);
  static const Color inputFocusBorder = Color(0xFF096544);

  // Disabled State
  static const Color disabledBackground = Color(0xFFEDF2F0);
  static const Color disabledText = Color(0xFF8E9E97);

  // Semantic & Status Colours
  static const Color success = Color(0xFF096544);
  static const Color successLight = Color(0xFFEAF5EF);
  static const Color secondary = Color(0xFF0B704C);

  static const Color warning = Color(0xFFD9822B);
  static const Color warningLight = Color(0xFFFEF4E4);

  static const Color error = Color(0xFFDC2626);
  static const Color errorLight = Color(0xFFFEECEB);
  static const Color danger = Color(0xFFDC2626);

  static const Color info = Color(0xFF3186C8);
  static const Color infoLight = Color(0xFFEDF5FA);
  static const Color information = Color(0xFF3186C8);

  static const Color teal = Color(0xFF1DA190);
  static const Color tealLight = Color(0xFFE4F6F4);

  // Coral Accent for Holidays & Non-Working / Off Days
  static const Color coral = Color(0xFFFF6F61);
  static const Color coralDark = Color(0xFFE0533C);
  static const Color coralLight = Color(0xFFFFECE8);
  static const Color coralBorder = Color(0xFFFF8A75);

  static const Color badgeBg = Color(0xFFEAF5EF);
  static const Color badgeText = Color(0xFF096544);

  // Soft Logout & Destructive Accents
  static const Color logoutBg = Color(0xFFFEECEB);
  static const Color logoutText = Color(0xFFDC2626);

  static const Color glow = Color(0x18096544);
  static const Color shadow = Color(0x0A0D1F17);
  static const Color cardShadow = Color(0x0A0D1F17);
}
