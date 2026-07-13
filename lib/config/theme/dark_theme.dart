import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';
import 'liquid_glass_theme.dart';
import 'liquid_glass_tokens.dart';

ThemeData buildDarkTheme({Color? accent}) {
  // Brand teal is the Liquid Glass primary; the user's saved accent-color
  // setting still overrides it (DB-synced via user_settings — keep working).
  final primary = accent ?? AppColors.green;
  // Teal (and several user-pickable accents) are light hues — white text on
  // them fails contrast, so the foreground is chosen by luminance instead
  // of hardcoding white.
  final onPrimary =
      primary.computeLuminance() > 0.45 ? const Color(0xFF072A1C) : Colors.white;
  const signatureShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.only(
      topLeft: Radius.circular(LiquidGlass.radiusCard),
      topRight: Radius.circular(LiquidGlass.radiusCut),
      bottomLeft: Radius.circular(LiquidGlass.radiusCard),
      bottomRight: Radius.circular(LiquidGlass.radiusCard),
    ),
    side: BorderSide(color: LiquidGlass.glassBorderDark, width: 1),
  );
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.background,
    primaryColor: primary,
    extensions: const [LiquidGlassTheme.dark],
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: LiquidPageTransitionsBuilder(),
      TargetPlatform.iOS: LiquidPageTransitionsBuilder(),
      TargetPlatform.windows: LiquidPageTransitionsBuilder(),
      TargetPlatform.macOS: LiquidPageTransitionsBuilder(),
      TargetPlatform.linux: LiquidPageTransitionsBuilder(),
    }),
    colorScheme: ColorScheme.dark(
      primary: primary,
      secondary: AppColors.blueLight,
      surface: AppColors.surface,
      error: AppColors.red,
      onPrimary: onPrimary,
      onSurface: AppColors.textPrimary,
    ),
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
    cardTheme: const CardThemeData(
      color: AppColors.card,
      elevation: 0,
      shape: signatureShape,
    ),
    dialogTheme: const DialogThemeData(shape: signatureShape),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(LiquidGlass.radiusControl),
        borderSide: const BorderSide(color: LiquidGlass.glassBorderDark, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(LiquidGlass.radiusControl),
        borderSide: const BorderSide(color: LiquidGlass.glassBorderDark, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(LiquidGlass.radiusControl),
        borderSide: BorderSide(color: primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(LiquidGlass.radiusControl),
        borderSide: const BorderSide(color: AppColors.red, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(LiquidGlass.radiusControl),
        borderSide: const BorderSide(color: AppColors.red, width: 1.5),
      ),
      hintStyle: GoogleFonts.dmSans(color: AppColors.textMuted, fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: onPrimary,
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
    dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 0.5),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.card,
      side: const BorderSide(color: LiquidGlass.glassBorderDark, width: 1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      labelStyle: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textPrimary),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(LiquidGlass.radiusSheet))),
    ),
    useMaterial3: true,
  );
}
