import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class HoneyTheme {
  static const Color amberPrimary = Color(0xFFFFBF00);
  static const Color amberDark = Color(0xFFB38600);
  static const Color amberLight = Color(0xFFFFD54F);
  static const Color honeyBlack = Color(0xFF121212);
  static const Color honeySurface = Color(0xFF1E1E1E);
  
  // Glassmorphism constants
  static Color glassBackground = Colors.white.withOpacity(0.08);
  static Color glassBorder = Colors.white.withOpacity(0.12);
  static const double glassBlur = 12.0;

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorSchemeSeed: amberPrimary,
      scaffoldBackgroundColor: honeyBlack,
      cardTheme: CardThemeData(
        color: honeySurface,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: amberPrimary,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        selectedItemColor: amberPrimary,
        unselectedItemColor: Colors.grey,
        backgroundColor: honeySurface,
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorSchemeSeed: amberPrimary,
      textTheme: GoogleFonts.outfitTextTheme(ThemeData.light().textTheme),
    );
  }
}
