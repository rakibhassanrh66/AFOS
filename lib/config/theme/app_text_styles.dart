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

  // --- The third type role: TABULAR NUMERIC -------------------------------
  //
  // The audit found ZERO uses of FontFeature.tabularFigures() in 188 files.
  // DM Sans ships PROPORTIONAL figures by default, meaning a '1' is narrower
  // than a '0'. That is correct for prose and wrong for every number this app
  // shows that CHANGES IN PLACE:
  //
  //   * the transport "next bus in 9m" -> "10m" countdown
  //   * CGPA/SGPA, which recompute as marks land
  //   * live class-status timers on the dashboard
  //   * seat numbers, student IDs and grade columns, which must align down a
  //     column to be scannable at all
  //
  // With proportional figures every one of those visibly jitters as the digits
  // tick, and columns of them come out ragged. Tabular figures give every digit
  // the same advance width, so the text box stops resizing and the column lines
  // up. This is a rendering defect, not a stylistic preference.
  //
  // These are the same DM Sans family at the same sizes as their prose
  // counterparts, so swapping a Text to one of these changes alignment and
  // nothing else. Use them for any number that updates or that sits in a column
  // -- not for numbers inside a sentence, where proportional is still correct.
  // Public and const so it can be asserted on directly. Constructing any
  // GoogleFonts TextStyle in a unit test triggers a network fetch (DM Sans is
  // not bundled as an asset here), so the shared FEATURE LIST is the part that
  // can be pinned offline — and it is the part that actually carries the rule.
  static const List<FontFeature> tabularFeatures = [
    FontFeature.tabularFigures(),
    // Slashed zero: on an ID or a seat number, 0 and O must not be guessable.
    FontFeature.slashedZero(),
  ];

  /// Headline-sized figures: CGPA, a dashboard hero stat.
  static TextStyle numericLarge = GoogleFonts.dmSans(
      fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary,
      letterSpacing: -0.3, fontFeatures: tabularFeatures);

  /// In-row figures: times, marks, counts in a list.
  static TextStyle numericMedium = GoogleFonts.dmSans(
      fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
      fontFeatures: tabularFeatures);

  /// Badge and caption figures.
  static TextStyle numericSmall = GoogleFonts.dmSans(
      fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary,
      fontFeatures: tabularFeatures);
}
