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
    // See dark_theme.dart -- displayLarge/displayMedium/headlineLarge and
    // the AppBar title unified from GoogleFonts.syne to GoogleFonts.dmSans
    // for one consistent type family across the whole app.
    textTheme: GoogleFonts.dmSansTextTheme(ThemeData.light().textTheme).copyWith(
      displayLarge:  GoogleFonts.dmSans(fontSize:32,fontWeight:FontWeight.w800,color:AppColors.lightText,letterSpacing:-0.5),
      displayMedium: GoogleFonts.dmSans(fontSize:24,fontWeight:FontWeight.w700,color:AppColors.lightText,letterSpacing:-0.3),
      headlineLarge: GoogleFonts.dmSans(fontSize:20,fontWeight:FontWeight.w700,color:AppColors.lightText),
      titleLarge:    GoogleFonts.dmSans(fontSize:16,fontWeight:FontWeight.w600,color:AppColors.lightText),
      bodyLarge:     GoogleFonts.dmSans(fontSize:15,color:AppColors.lightText),
      bodyMedium:    GoogleFonts.dmSans(fontSize:13,color:AppColors.lightMuted),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      iconTheme: const IconThemeData(color: AppColors.lightText),
      titleTextStyle: GoogleFonts.dmSans(fontSize:18,fontWeight:FontWeight.w700,color:AppColors.lightText),
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
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.red, width: 1)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.red, width: 1.5)),
      hintStyle: GoogleFonts.dmSans(color: AppColors.lightMuted, fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary, foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w600),
        elevation: 0,
      ),
    ),
    // dark_theme.dart defines all four of these; light_theme.dart never did
    // -- every OutlinedButton/Chip/undecorated Divider/bottom sheet that
    // relies on the ambient theme (rather than passing its own explicit
    // style) fell back to generic Material3 defaults in light mode only:
    // shrink-wrapped instead of full-width, default grey border, wrong
    // corner radius, square-cornered sheets. Dark mode always looked
    // custom-styled; light mode looked like a different, unfinished app.
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        side: BorderSide(color: primary),
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.lightBorder, thickness: 0.5),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.lightCard,
      side: const BorderSide(color: AppColors.lightBorder, width: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      labelStyle: GoogleFonts.dmSans(fontSize: 12, color: AppColors.lightText),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.lightCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    useMaterial3: true,
  );
}
