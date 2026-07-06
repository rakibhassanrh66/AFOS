import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

ThemeData buildLightTheme({Color? accent}) {
  final primary = accent ?? AppColors.blue;
  return ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.lightBg,
    primaryColor: primary,
    colorScheme: ColorScheme.light(
      primary: primary,
      secondary: AppColors.gold,
      surface: AppColors.lightCard,
      error: AppColors.red,
    ),
    textTheme: GoogleFonts.dmSansTextTheme(ThemeData.light().textTheme).copyWith(
      displayLarge:  GoogleFonts.syne(fontSize:32,fontWeight:FontWeight.w800,color:AppColors.lightText),
      displayMedium: GoogleFonts.syne(fontSize:24,fontWeight:FontWeight.w700,color:AppColors.lightText),
      headlineLarge: GoogleFonts.syne(fontSize:20,fontWeight:FontWeight.w700,color:AppColors.lightText),
      titleLarge:    GoogleFonts.dmSans(fontSize:16,fontWeight:FontWeight.w600,color:AppColors.lightText),
      bodyLarge:     GoogleFonts.dmSans(fontSize:15,color:AppColors.lightText),
      bodyMedium:    GoogleFonts.dmSans(fontSize:13,color:AppColors.lightMuted),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      iconTheme: const IconThemeData(color: AppColors.lightText),
      titleTextStyle: GoogleFonts.syne(fontSize:18,fontWeight:FontWeight.w700,color:AppColors.lightText),
    ),
    cardTheme: CardThemeData(
      color: AppColors.lightCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.lightBorder, width: 0.5),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.lightBorder, width: 0.5)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.lightBorder, width: 0.5)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: primary, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary, foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
      ),
    ),
    useMaterial3: true,
  );
}
