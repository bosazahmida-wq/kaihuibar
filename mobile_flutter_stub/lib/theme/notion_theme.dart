import 'package:flutter/material.dart';

class NotionPalette {
  static const bg = Color(0xFFFFFFFF);
  static const surface = Color(0xFFF7F7F5);
  static const border = Color(0xFFE9E9E7);
  static const textPrimary = Color(0xFF37352F);
  static const textSecondary = Color(0xFF787774);
  static const accent = Color(0xFF2F6FEB);
}

ThemeData buildNotionTheme() {
  final base = ThemeData.light(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: NotionPalette.bg,
    colorScheme: base.colorScheme.copyWith(
      primary: NotionPalette.accent,
      surface: NotionPalette.surface,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: NotionPalette.textPrimary,
      displayColor: NotionPalette.textPrimary,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: NotionPalette.bg,
      elevation: 0,
      centerTitle: false,
      foregroundColor: NotionPalette.textPrimary,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: NotionPalette.textPrimary,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: NotionPalette.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: NotionPalette.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: NotionPalette.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: NotionPalette.accent),
      ),
    ),
    cardTheme: CardThemeData(
      color: NotionPalette.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: NotionPalette.border),
      ),
      margin: EdgeInsets.zero,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: NotionPalette.textPrimary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: NotionPalette.bg,
      selectedItemColor: NotionPalette.textPrimary,
      unselectedItemColor: NotionPalette.textSecondary,
      type: BottomNavigationBarType.fixed,
      showUnselectedLabels: true,
    ),
  );
}
