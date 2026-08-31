import 'dart:async';

import 'package:dio/dio.dart';

import '../services/local_cache_service.dart';
import '../utils/location_helper.dart';

/// WMO weather codes (Open-Meteo's `weather_code`), collapsed to the handful
/// of buckets a dress suggestion actually needs.
enum WeatherCondition { clear, cloudy, fog, drizzle, rain, thunderstorm, snow }

WeatherCondition _conditionFor(int code) {
  if (code == 0) return WeatherCondition.clear;
  if (code <= 3) return WeatherCondition.cloudy;
  if (code == 45 || code == 48) return WeatherCondition.fog;
  if (code >= 51 && code <= 57) return WeatherCondition.drizzle;
  if ((code >= 61 && code <= 67) || (code >= 80 && code <= 82)) return WeatherCondition.rain;
  if ((code >= 71 && code <= 77) || code == 85 || code == 86) return WeatherCondition.snow;
  if (code >= 95) return WeatherCondition.thunderstorm;
  return WeatherCondition.cloudy;
}

class WeatherSnapshot {
  final double temperatureC;
  final WeatherCondition condition;
  final bool isDay;

  const WeatherSnapshot({
    required this.temperatureC,
    required this.condition,
    required this.isDay,
  });

  Map<String, dynamic> toJson() => {
        'temperatureC': temperatureC,
        'condition': condition.name,
        'isDay': isDay,
      };

  factory WeatherSnapshot.fromJson(Map<String, dynamic> j) => WeatherSnapshot(
        temperatureC: (j['temperatureC'] as num).toDouble(),
        condition: WeatherCondition.values.byName('${j['condition']}'),
        isDay: j['isDay'] == true,
      );
}

/// Live weather for wherever the device actually is, via Open-Meteo --
/// chosen specifically because it needs NO account and NO API key: every
/// other option (OpenWeatherMap included) requires a signup and a secret
/// this repo could never hold per its own HARD RULE on credentials. Per-
/// student GPS, not one shared campus-wide value, was the owner's explicit
/// call once the trade-off (more accurate, more requests) was laid out.
///
/// ONLY the fields an on-device dress suggestion needs are requested --
/// current temperature, the WMO condition code, and day/night. Open-Meteo's
/// own request builder happily hands back 60+ variables (hourly soil
/// moisture, UV index, radiation curves) for a single query; asking for all
/// of them here would have been the wrong reference to copy from, not a
/// shortcut.
class WeatherService {
  WeatherService._();

  static const _cacheKey = 'weather_current';
  static const _freshFor = Duration(minutes: 25);

  /// Returns the last good reading if it's still fresh, silently fetches a
  /// new one otherwise. Returns null (never throws to the caller) when
  /// location is unavailable/denied or the request fails -- exactly the
  /// "render nothing" contract every other optional dashboard panel this
  /// session touched already follows; a missing weather card is not an
  /// error a user should ever see.
  static Future<WeatherSnapshot?> current() async {
    final cached = LocalCacheService.instance.getMap(_cacheKey);
    if (cached != null && DateTime.now().difference(cached.cachedAt) < _freshFor) {
      try {
        return WeatherSnapshot.fromJson(cached.data);
      } catch (_) {
        // Falls through to a live fetch -- a cache shape from a version this
        // build no longer parses must not become a permanent dead end.
      }
    }

    // A user with location permission already granted (routine by this
    // point -- complete-profile already asked once) gets a position with no
    // new prompt. One who denied it gets null here and no card, not a
    // request badgering them again on every dashboard load.
    final position = await LocationHelper.getCurrentPosition();
    if (position == null) return null;

    try {
      final res = await Dio().get(
        'https://api.open-meteo.com/v1/forecast',
        queryParameters: {
          'latitude': position.latitude,
          'longitude': position.longitude,
          'current': 'temperature_2m,weather_code,is_day',
          'timezone': 'auto',
        },
      ).timeout(const Duration(seconds: 10));

      final current = res.data['current'] as Map<String, dynamic>;
      final snapshot = WeatherSnapshot(
        temperatureC: (current['temperature_2m'] as num).toDouble(),
        condition: _conditionFor((current['weather_code'] as num).toInt()),
        isDay: current['is_day'] == 1,
      );
      await LocalCacheService.instance.putMap(_cacheKey, snapshot.toJson());
      return snapshot;
    } catch (_) {
      // A stale-but-present cache beats nothing if the network call itself
      // is what failed.
      if (cached != null) {
        try {
          return WeatherSnapshot.fromJson(cached.data);
        } catch (_) {
          return null;
        }
      }
      return null;
    }
  }
}
