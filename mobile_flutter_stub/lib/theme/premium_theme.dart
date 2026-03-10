import 'package:flutter/material.dart';

class PremiumPalette {
  static const bg = Color(0xFFFAFAFA); // Slightly off-white for softer contrast
  static const surface = Color(0xFFFFFFFF); // Pure white for cards/surfaces
  static const border = Color(0xFFEBEBEB);
  static const textPrimary = Color(0xFF1E1E1E); // Modern dark charcoal
  static const textSecondary = Color(0xFF8E8E8E);
  static const accent = Color(0xFF4A6CF7); // Vibrant, modern blue

  // Add gradient colors for premium feel
  static const gradientStart = Color(0xFF4A6CF7);
  static const gradientEnd = Color(0xFF7A94FE);
}

ThemeData buildPremiumTheme() {
  final base = ThemeData.light(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: PremiumPalette.bg,
    colorScheme: base.colorScheme.copyWith(
      primary: PremiumPalette.accent,
      surface: PremiumPalette.surface,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: PremiumPalette.textPrimary,
      displayColor: PremiumPalette.textPrimary,
      fontFamily: 'Roboto', // Modern system font
    ).copyWith(
      // Larger, bolder headings
      titleLarge: const TextStyle(fontWeight: FontWeight.w700, fontSize: 24),
      titleMedium: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent, // For glassmorphism if needed
      elevation: 0,
      centerTitle: true,
      foregroundColor: PremiumPalette.textPrimary,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: PremiumPalette.textPrimary,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: PremiumPalette.bg,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16), // Rounded modern inputs
        borderSide: const BorderSide(color: PremiumPalette.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: PremiumPalette.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: PremiumPalette.accent, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    ),
    cardTheme: CardThemeData(
      color: PremiumPalette.surface,
      elevation: 4, // Soft shadow
      shadowColor: Colors.black.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20), // More pronounced rounding
        side: const BorderSide(color: PremiumPalette.border, width: 0.5),
      ),
      margin: EdgeInsets.zero,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: PremiumPalette.textPrimary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), // Better shape
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16), // Thicker button
        elevation: 0,
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: PremiumPalette.surface,
      selectedItemColor: PremiumPalette.accent, // Accent color for selection
      unselectedItemColor: PremiumPalette.textSecondary,
      type: BottomNavigationBarType.fixed,
      showUnselectedLabels: true,
      elevation: 10,
    ),
  );
}
