import 'package:flutter/material.dart';

class AppTheme {
  static final ThemeData theme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFFFF934F),
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: const Color(0xFFFFF7EC),
    textTheme: const TextTheme(
      displaySmall: TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.w800,
        color: Color(0xFF33261C),
      ),
      headlineMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: Color(0xFF33261C),
      ),
      titleLarge: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: Color(0xFF33261C),
      ),
      bodyLarge: TextStyle(
        fontSize: 18,
        height: 1.35,
        color: Color(0xFF5F4A3A),
      ),
    ),
  );
}
