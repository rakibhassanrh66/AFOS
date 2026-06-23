import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTextStyles {
  AppTextStyles._();
  static TextStyle displayLarge  = GoogleFonts.syne(fontSize:32,fontWeight:FontWeight.w800,color:AppColors.textPrimary);
  static TextStyle displayMedium = GoogleFonts.syne(fontSize:24,fontWeight:FontWeight.w700,color:AppColors.textPrimary);
  static TextStyle headlineLarge = GoogleFonts.syne(fontSize:20,fontWeight:FontWeight.w700,color:AppColors.textPrimary);
  static TextStyle headlineMed   = GoogleFonts.syne(fontSize:18,fontWeight:FontWeight.w700,color:AppColors.textPrimary);
  static TextStyle titleLarge    = GoogleFonts.dmSans(fontSize:16,fontWeight:FontWeight.w600,color:AppColors.textPrimary);
  static TextStyle titleMedium   = GoogleFonts.dmSans(fontSize:14,fontWeight:FontWeight.w600,color:AppColors.textPrimary);
  static TextStyle bodyLarge     = GoogleFonts.dmSans(fontSize:15,fontWeight:FontWeight.w400,color:AppColors.textPrimary);
  static TextStyle bodyMedium    = GoogleFonts.dmSans(fontSize:13,fontWeight:FontWeight.w400,color:AppColors.textSecondary);
  static TextStyle labelSmall    = GoogleFonts.dmSans(fontSize:11,fontWeight:FontWeight.w500,color:AppColors.textSecondary);
  static TextStyle monoMedium    = GoogleFonts.jetBrainsMono(fontSize:13,color:AppColors.textPrimary);
  static TextStyle monoSmall     = GoogleFonts.jetBrainsMono(fontSize:11,color:AppColors.textSecondary);
}
