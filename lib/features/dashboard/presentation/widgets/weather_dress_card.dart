import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../config/theme/app_colors.dart';
import '../../../../config/theme/app_text_styles.dart';
import '../../../../config/theme/depth.dart';
import '../../../../config/theme/motion.dart';
import '../../../../config/theme/spacing.dart';
import '../../../../core/services/weather_service.dart';

/// Live weather plus a gendered dress suggestion, for every user's own
/// device location — the owner's ask. A RULE TABLE, not a generated one: a
/// temperature band plus a condition plus (optionally) gender is a fixed,
/// small combination, so this is instant, free, and works offline once
/// fetched. Nothing here calls out to an LLM for something a lookup table
/// answers exactly as well.
///
/// SAME MOTION CONTRACT as MyCompletenessRing: a one-time mount animation and
/// real AppDepth shadow, never a perpetual loop — the owner's "living, moving
/// weather scene (heat haze drifting, rain animating)" idea was heard, but
/// building it as a continuous idle animation on every open dashboard is
/// exactly what "animate on mount or explicit action, never on rebuild"
/// exists to stop. This is the compliant version: real current data, refreshed
/// on each visit, presented with one settle-in rather than never settling.
class WeatherDressCard extends StatelessWidget {
  final WeatherSnapshot weather;
  final String? gender;

  const WeatherDressCard({super.key, required this.weather, this.gender});

  (IconData, String) get _conditionIconLabel => switch (weather.condition) {
        WeatherCondition.clear =>
          (weather.isDay ? Icons.wb_sunny_rounded : Icons.nightlight_round, weather.isDay ? 'Clear' : 'Clear night'),
        WeatherCondition.cloudy => (Icons.cloud_rounded, 'Cloudy'),
        WeatherCondition.fog => (Icons.foggy, 'Foggy'),
        WeatherCondition.drizzle => (Icons.grain_rounded, 'Drizzle'),
        WeatherCondition.rain => (Icons.water_drop_rounded, 'Rain'),
        WeatherCondition.thunderstorm => (Icons.thunderstorm_rounded, 'Thunderstorm'),
        WeatherCondition.snow => (Icons.ac_unit_rounded, 'Snow'),
      };

  String get _suggestion {
    final t = weather.temperatureC;
    final isFemale = gender == 'female';

    final String base;
    if (t >= 32) {
      base = isFemale
          ? 'Hot out — light cotton kurti or salwar in a breathable fabric, and carry water.'
          : 'Hot out — a light cotton shirt and breathable trousers, and carry water.';
    } else if (t >= 20) {
      base = 'Comfortable weather — regular clothing is fine today.';
    } else {
      base = isFemale
          ? 'A bit cool — a light shawl or jacket over your outfit would help.'
          : 'A bit cool — a light jacket would help.';
    }

    return switch (weather.condition) {
      WeatherCondition.rain || WeatherCondition.drizzle => '$base Carry an umbrella.',
      WeatherCondition.thunderstorm => '$base Avoid open areas until it passes.',
      _ => base,
    };
  }

  @override
  Widget build(BuildContext context) {
    final (icon, label) = _conditionIconLabel;
    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceOf(context),
          borderRadius: AppDepth.radius(2),
          border: Border.all(color: AppColors.borderOf(context), width: 0.5),
          boxShadow: AppDepth.shadow(2, isDark: AppColors.isDark(context)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 48, height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.holoBlue.withValues(alpha: 0.14),
              borderRadius: AppDepth.radius(1),
            ),
            child: Icon(icon, color: AppColors.holoBlue, size: 26),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Wrap, not Row. Both of these were non-flex children of a Row,
              // so at a large text scale the pair overflowed the card by 11px
              // on a 320dp phone (measured at 1.6x). Making the condition
              // Flexible stopped the overflow but truncated "Cloudy" to half
              // its width — trading a visible fault for a silent one, which is
              // worse: the reader cannot tell they are missing a word.
              //
              // Neither string is long; there simply is not room for both on
              // one line beside a 48px icon at 1.6x. A Wrap puts the condition
              // on its own line exactly when it stops fitting, and both stay
              // whole and readable.
              Wrap(
                spacing: 8,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('${weather.temperatureC.round()}°C',
                      style: AppTextStyles.titleMedium.copyWith(
                          color: AppColors.textPrimaryOf(context),
                          fontWeight: FontWeight.w700)),
                  Text(label,
                      style: AppTextStyles.labelSmall
                          .copyWith(color: AppColors.textSecondaryOf(context))),
                ],
              ),
              const SizedBox(height: 4),
              Text(_suggestion,
                  style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context))),
            ]),
          ),
        ]),
      ),
    )
        .animate()
        .fadeIn(duration: AppMotion.durationOf(context, AppMotion.base))
        .scaleXY(begin: 0.96, duration: AppMotion.durationOf(context, AppMotion.base),
            curve: AppMotion.standard);
  }
}
