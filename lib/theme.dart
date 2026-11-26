import 'package:flutter/material.dart';

class PrimeTokens {
  static const Color paper = Color(0xFFFBF7F0);
  static const Color ink = Color(0xFF17332B);
  static const Color mint = Color(0xFF8FD9BE);
  static const Color deepGreen = Color(0xFF17332B);
  static const Color dark = Color(0xFF121212);
  static const Color gray = Color(0xFFC9CCC9);
  static const Color nearWhite = Color(0xFFF7F5F0);
  static const Color red = Color(0xFFE8484F);
  static const Color amber = Color(0xFFE8A24F);
  static const Color line = Color(0x2417332B);

  static ThemeData theme() {
    final base = ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: paper,
      colorScheme: ColorScheme.fromSeed(seedColor: mint, primary: deepGreen),
      textTheme: const TextTheme(
        titleLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: ink, height: 1.2),
        bodyLarge: TextStyle(fontSize: 16, height: 1.8, color: ink),
        bodyMedium: TextStyle(fontSize: 15, height: 1.8, color: ink),
        labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: ink),
      ),
    );
    return base;
  }
}
