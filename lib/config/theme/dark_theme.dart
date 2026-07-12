import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

ThemeData buildDarkTheme({Color? accent}) {
  final primary = accent ?? AppColors.blue;
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.background,
    primaryColor: primary,
    colorScheme: ColorScheme.dark(
      primary: primary,
      secondary: AppColors.gold,
      surface: AppColors.surface,
      error: AppColors.red,
      onPrimary: Colors.white,
      onSurface: AppColors.textPrimary,
    ),
    // displayLarge/displayMedium/headlineLarge and the AppBar title were
    // GoogleFonts.syne -- an avant-garde display face (flat-topped rounds,
    // very tall x-height) that clashed against the DM Sans used everywhere
    // else, reading as an inconsistent/"weird" font on every single screen's
    // title bar. Unified on DM Sans throughout so the whole type system is
    // one consistent family, matching app_text_styles.dart.
    textTheme: GoogleFonts.dmSansTextTheme(ThemeData.dark().textTheme).copyWith(
      displayLarge:  GoogleFonts.dmSans(fontSize:32,fontWeight:FontWeight.w800,color:AppColors.textPrimary,letterSpacing:-0.5),
      displayMedium: GoogleFonts.dmSans(fontSize:24,fontWeight:FontWeight.w700,color:AppColors.textPrimary,letterSpacing:-0.3),
      headlineLarge: GoogleFonts.dmSans(fontSize:20,fontWeight:FontWeight.w700,color:AppColors.textPrimary),
      titleLarge:    GoogleFonts.dmSans(fontSize:16,fontWeight:FontWeight.w600,color:AppColors.textPrimary),
      bodyLarge:     GoogleFonts.dmSans(fontSize:15,color:AppColors.textPrimary),
      bodyMedium:    GoogleFonts.dmSans(fontSize:13,color:AppColors.textSecondary),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      iconTheme: const IconThemeData(color: AppColors.textPrimary),
      titleTextStyle: GoogleFonts.dmSans(fontSize:18,fontWeight:FontWeight.w700,color:AppColors.textPrimary),
    ),
    cardTheme: CardThemeData(
      color: AppColors.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border, width: 0.5),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border, width: 0.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border, width: 0.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.red, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.red, width: 1.5),
      ),
      hintStyle: GoogleFonts.dmSans(color: AppColors.textMuted, fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w600),
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        side: BorderSide(color: primary),
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 0.5),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.card,
      side: const BorderSide(color: AppColors.border, width: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      labelStyle: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textPrimary),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    useMaterial3: true,
  );
}
