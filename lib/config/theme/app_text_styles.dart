import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTextStyles {
  AppTextStyles._();
  // Was GoogleFonts.syne -- an avant-garde display face with very
  // unconventional letterforms (flat-topped rounds, tall x-height) that
  // clashed against the humanist DM Sans used for every body/title style,
  // reading as a mismatched/"weird" font wherever a headline sat near body
  // text. Switched the whole display/headline tier to DM Sans at heavier
  // weights so the type system is one consistent family end to end, just
  // varying weight/size for hierarchy -- matches the "gentle, not funky"
  // direction requested for the rest of the visual system.
  static TextStyle displayLarge  = GoogleFonts.dmSans(fontSize:32,fontWeight:FontWeight.w800,color:AppColors.textPrimary,letterSpacing:-0.5);
  static TextStyle displayMedium = GoogleFonts.dmSans(fontSize:24,fontWeight:FontWeight.w700,color:AppColors.textPrimary,letterSpacing:-0.3);
  static TextStyle headlineLarge = GoogleFonts.dmSans(fontSize:20,fontWeight:FontWeight.w700,color:AppColors.textPrimary);
  static TextStyle headlineMed   = GoogleFonts.dmSans(fontSize:18,fontWeight:FontWeight.w700,color:AppColors.textPrimary);
  static TextStyle titleLarge    = GoogleFonts.dmSans(fontSize:16,fontWeight:FontWeight.w600,color:AppColors.textPrimary);
  static TextStyle titleMedium   = GoogleFonts.dmSans(fontSize:14,fontWeight:FontWeight.w600,color:AppColors.textPrimary);
  static TextStyle bodyLarge     = GoogleFonts.dmSans(fontSize:15,fontWeight:FontWeight.w400,color:AppColors.textPrimary);
  static TextStyle bodyMedium    = GoogleFonts.dmSans(fontSize:13,fontWeight:FontWeight.w400,color:AppColors.textSecondary);
  static TextStyle labelSmall    = GoogleFonts.dmSans(fontSize:11,fontWeight:FontWeight.w500,color:AppColors.textSecondary);
  static TextStyle monoMedium    = GoogleFonts.jetBrainsMono(fontSize:13,color:AppColors.textPrimary);
  static TextStyle monoSmall     = GoogleFonts.jetBrainsMono(fontSize:11,color:AppColors.textSecondary);
}
