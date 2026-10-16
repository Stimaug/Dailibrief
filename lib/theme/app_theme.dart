import 'package:flutter/material.dart';

/// Tema putih dan simpel DailyBrief.
class AppColors {
  static const Color primary = Color(0xFF2563EB);
  static const Color primarySoft = Color(0xFFEFF4FF);
  static const Color ring1 = Color(0xFFDCE7FE);
  static const Color text = Color(0xFF111827);
  static const Color textMuted = Color(0xFF6B7280);
  static const Color error = Color(0xFFE11D48);
  static const Color errorSoft = Color(0xFFFFE4EA);
  static const Color border = Color(0xFFE5E7EB);
}

class AppTheme {
  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: Colors.white,
      canvasColor: Colors.white,
      fontFamily: 'Roboto',
      textTheme: const TextTheme().apply(
        bodyColor: AppColors.text,
        displayColor: AppColors.text,
      ),
    );
  }
}
