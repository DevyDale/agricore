import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
        seedColor: AppColors.green, primary: AppColors.green, brightness: Brightness.light);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Inter',
      scaffoldBackgroundColor: AppColors.cream,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.cream,
        foregroundColor: AppColors.inkWarm,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: AppColors.inkWarm),
        titleTextStyle: TextStyle(
            fontFamily: 'Fraunces',
            fontWeight: FontWeight.w700,
            fontSize: 22,
            color: AppColors.inkWarm),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        prefixIconColor: AppColors.g700,
        hintStyle: const TextStyle(color: AppColors.slate500),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.line)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.line)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.green, width: 2)),
      ),
      cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: AppColors.line))),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: Colors.white,
        elevation: 0,
        indicatorColor: const Color(0xFFE7F4EC),
        labelTextStyle: WidgetStateProperty.all(const TextStyle(
            fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600)),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? AppColors.g700 : AppColors.slate500)),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: Colors.white,
        selectedIconTheme: IconThemeData(color: AppColors.g700),
        unselectedIconTheme: IconThemeData(color: AppColors.slate500),
        selectedLabelTextStyle:
            TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, color: AppColors.g700),
        unselectedLabelTextStyle:
            TextStyle(fontFamily: 'Inter', color: AppColors.slate600),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.line, thickness: 1),
    );
  }
}
