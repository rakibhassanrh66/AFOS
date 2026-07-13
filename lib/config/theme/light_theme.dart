import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';
import 'liquid_glass_theme.dart';
import 'liquid_glass_tokens.dart';

ThemeData buildLightTheme({Color? accent}) {
  // Brand teal primary (accent-color user setting still overrides — see
  // dark_theme.dart); foreground picked by luminance so light accents get
  // ink text instead of unreadable white.
  final primary = accent ?? AppColors.green;
  final onPrimary =
      primary.computeLuminance() > 0.45 ? const Color(0xFF072A1C) : Colors.white;
  const signatureShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.only(
      topLeft: Radius.circular(LiquidGlass.radiusCard),
      topRight: Radius.circular(LiquidGlass.radiusCut),
      bottomLeft: Radius.circular(LiquidGlass.radiusCard),
      bottomRight: Radius.circular(LiquidGlass.radiusCard),
    ),
    side: BorderSide(color: LiquidGlass.glassBorderLight, width: 1),
  );
  return ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.lightBg,
    primaryColor: primary,
    extensions: const [LiquidGlassTheme.light],
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: LiquidPageTransitionsBuilder(),
      TargetPlatform.iOS: LiquidPageTransitionsBuilder(),
      TargetPlatform.windows: LiquidPageTransitionsBuilder(),
      TargetPlatform.macOS: LiquidPageTransitionsBuilder(),
      TargetPlatform.linux: LiquidPageTransitionsBuilder(),
    }),
    colorScheme: ColorScheme.light(
      primary: primary,
      secondary: LiquidGlass.accentBlueDeep,
      surface: AppColors.lightCard,
      error: AppColors.red,
      onPrimary: onPrimary,
    ),
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
    cardTheme: const CardThemeData(
      color: AppColors.lightCard,
      elevation: 0,
      shape: signatureShape,
    ),
    dialogTheme: const DialogThemeData(shape: signatureShape),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(LiquidGlass.radiusControl),
        borderSide: const BorderSide(color: LiquidGlass.glassBorderLight, width: 1)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(LiquidGlass.radiusControl),
        borderSide: const BorderSide(color: LiquidGlass.glassBorderLight, width: 1)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(LiquidGlass.radiusControl),
        borderSide: BorderSide(color: primary, width: 1.5)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(LiquidGlass.radiusControl),
        borderSide: const BorderSide(color: AppColors.red, width: 1)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(LiquidGlass.radiusControl),
        borderSide: const BorderSide(color: AppColors.red, width: 1.5)),
      hintStyle: GoogleFonts.dmSans(color: AppColors.lightMuted, fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary, foregroundColor: onPrimary,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(LiquidGlass.radiusControl)),
        textStyle: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w600),
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        side: BorderSide(color: primary),
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(LiquidGlass.radiusControl)),
        textStyle: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.lightBorder, thickness: 0.5),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.lightCard,
      side: const BorderSide(color: LiquidGlass.glassBorderLight, width: 1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      labelStyle: GoogleFonts.dmSans(fontSize: 12, color: AppColors.lightText),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.lightCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(LiquidGlass.radiusSheet))),
    ),
    useMaterial3: true,
  );
}
