import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'celadon_colors.dart';

/// Central ThemeData definition for ReGen Mobile
///
/// Implements Material 3 with the global White + Charcoal + Emerald Green
/// color palette specified in the ReGen Visual Theme Enhancement.
abstract final class CeladonTheme {
  static ThemeData get lightTheme {
    const textTheme = TextTheme(
      displayLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        color: CeladonColors.textPrimary,
        letterSpacing: -0.5,
      ),
      displayMedium: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w800,
        color: CeladonColors.textPrimary,
        letterSpacing: -0.3,
      ),
      headlineMedium: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: CeladonColors.textPrimary,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: CeladonColors.textPrimary,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: CeladonColors.textPrimary,
      ),
      titleSmall: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: CeladonColors.textPrimary,
      ),
      bodyLarge: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: CeladonColors.textPrimary,
        height: 1.45,
      ),
      bodyMedium: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: CeladonColors.textSecondary,
        height: 1.4,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: CeladonColors.textMuted,
      ),
      labelLarge: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
      ),
      labelMedium: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: CeladonColors.textPrimary,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: CeladonColors.primary,
      scaffoldBackgroundColor: CeladonColors.background,
      colorScheme: const ColorScheme(
        brightness: Brightness.light,
        primary: CeladonColors.primary,
        onPrimary: CeladonColors.textOnPrimary,
        primaryContainer: CeladonColors.primaryContainer,
        onPrimaryContainer: CeladonColors.primaryDark,
        secondary: CeladonColors.primarySecondary,
        onSecondary: CeladonColors.textOnPrimary,
        error: CeladonColors.error,
        onError: Colors.white,
        surface: CeladonColors.surface,
        onSurface: CeladonColors.textPrimary,
      ),
      textTheme: textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: CeladonColors.surface,
        foregroundColor: CeladonColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
        ),
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: CeladonColors.textPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        color: CeladonColors.cardBackground,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: CeladonColors.border, width: 1.0),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: CeladonColors.primary,
          foregroundColor: CeladonColors.textOnPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: CeladonColors.primary,
          side: const BorderSide(color: CeladonColors.primary, width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: CeladonColors.inputBackground,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: CeladonColors.inputBorder, width: 1.0),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: CeladonColors.inputBorder, width: 1.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: CeladonColors.inputFocusBorder, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: CeladonColors.error, width: 1.2),
        ),
        hintStyle: const TextStyle(
          color: CeladonColors.textPlaceholder,
          fontSize: 14,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: CeladonColors.divider,
        thickness: 1,
        space: 1,
      ),
    );
  }
}
