import 'package:flutter/material.dart';

class AppTheme {
  static const Color primary = Color(0xFF5B4CF5);
  static const Color primaryLight = Color(0xFF8175FF);
  static const Color partnerCoral = Color(0xFFFF5A79);
  static const Color liveGreen = Color(0xFF10B981);
  static const Color warningAmber = Color(0xFFF59E0B);

  static const Color bgLight = Color(0xFFF6F7FB);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color textPrimaryLight = Color(0xFF141625);
  static const Color textSecondaryLight = Color(0xFF6B7280);

  static const Color bgDark = Color(0xFF0F111A);
  static const Color surfaceDark = Color(0xFF1A1D2B);
  static const Color textPrimaryDark = Color(0xFFF3F4F6);
  static const Color textSecondaryDark = Color(0xFF9CA3AF);

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      secondary: partnerCoral,
      surface: surfaceLight,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: bgLight,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      foregroundColor: textPrimaryLight,
    ),
    cardTheme: CardThemeData(
      color: surfaceLight,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF0F2F8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
  );

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      primary: primaryLight,
      secondary: partnerCoral,
      surface: surfaceDark,
      brightness: Brightness.dark,
    ),
    scaffoldBackgroundColor: bgDark,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      foregroundColor: textPrimaryDark,
    ),
    cardTheme: CardThemeData(
      color: surfaceDark,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF25293A),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
  );
}
