import 'package:flutter/material.dart';

class AppTheme {
  static const Color darkBackground = Color(0xFF0F172A);
  static const Color primaryColor = Color(0xFF38BDF8); // Vibrant Cyan
  static const Color accentColor = Color(0xFFF472B6); // Soft Pink

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBackground,
      primaryColor: primaryColor,
      colorScheme: const ColorScheme.dark(
        primary: primaryColor,
        secondary: accentColor,
        surface: Color(0xFF1E293B),
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 24,
        ),
        bodyLarge: TextStyle(
          color: Colors.white70,
          fontSize: 16,
        ),
      ),
      useMaterial3: true,
    );
  }
}
