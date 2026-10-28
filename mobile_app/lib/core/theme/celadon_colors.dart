import 'package:flutter/material.dart';

/// Premium Celadon Color Palette
///
/// Extracted directly from the "8. Premium Celadon" design specification:
/// - Palette Swatch 1: Very pale soft mint #E8F3ED
/// - Palette Swatch 2: Sage celadon tint #B5D6C3
/// - Palette Swatch 3: Vibrant celadon green #68A68A
/// - Palette Swatch 4: Deep forest celadon #2D6A4F
/// - Palette Swatch 5: Dark spruce #0F3A2E
abstract final class CeladonColors {
  // Primary Forest Greens
  static const Color primaryDark = Color(0xFF0F3A2E);
  static const Color primary = Color(0xFF2D6A4F);
  static const Color primaryLight = Color(0xFF52B788);
  static const Color primaryContainer = Color(0xFFE8F3ED);

  // Mint & Celadon Canvas Backgrounds
  static const Color background = Color(0xFFF2F7F4);
  static const Color backgroundGradientStart = Color(0xFFEAF4EE);
  static const Color backgroundGradientEnd = Color(0xFFF7FAF8);

  // Surface & Cards
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF8FAF9);
  static const Color cardBackground = Color(0xFFFFFFFF);

  // Borders & Dividers
  static const Color border = Color(0xFFD8EADB);
  static const Color borderLight = Color(0xFFE8F3EA);
  static const Color divider = Color(0xFFE4EFE7);

  // Typography
  static const Color textPrimary = Color(0xFF1B4332);
  static const Color textSecondary = Color(0xFF52796F);
  static const Color textMuted = Color(0xFF8DA499);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // Functional & Semantic Badges
  static const Color success = Color(0xFF2D6A4F);
  static const Color successLight = Color(0xFFD8F3DC);

  static const Color warning = Color(0xFFD97706);
  static const Color warningLight = Color(0xFFFEF3C7);

  static const Color error = Color(0xFFE02424);
  static const Color errorLight = Color(0xFFFDE8E8);

  static const Color info = Color(0xFF0284C7);
  static const Color infoLight = Color(0xFFE0F2FE);

  static const Color badgeBg = Color(0xFFE8F3ED);
  static const Color badgeText = Color(0xFF1B4332);

  // Soft Logout & Special Accents
  static const Color logoutBg = Color(0xFFFFECEB);
  static const Color logoutText = Color(0xFFE02424);

  static const Color glow = Color(0x182D6A4F);
}
