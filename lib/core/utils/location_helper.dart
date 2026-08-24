import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// Shared location permission/capture boilerplate -- previously only
/// existed inline in transport_screen.dart's _enableLocation(); the SOS
/// floating button (a fresh one-shot capture at trigger time) and the
/// ambient background-sharing layer both need the same logic now.
class LocationHelper {
  LocationHelper._();

  /// Ensures location services + at-least-foreground permission are
  /// available, then returns a fresh one-shot high-accuracy position.
  /// Returns null (after calling [onError]) if services/permission aren't
  /// available -- callers decide how to surface that to the user.
  static Future<Position?> getCurrentPosition({
    void Function(String message)? onError,
    LocationAccuracy accuracy = LocationAccuracy.high,
  }) async {
    try {
      // On web this always returns true regardless of the browser's actual
      // location-services state (a documented geolocator_web limitation) --
      // the real signal on web is the permission prompt below, not this
      // check.
      if (!await Geolocator.isLocationServiceEnabled()) {
        onError?.call('Turn on location services to continue');
        return null;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        onError?.call('Location permission denied');
        return null;
      }
      // Browser geolocation prompts are less reliable than native: a prompt
      // dismissed without an explicit allow/block can leave this Future
      // pending forever on some browser/geolocator-web combinations, which
      // otherwise left the caller's "Getting location..." button stuck
      // permanently -- indistinguishable from the page being broken. Native
      // platforms resolve well inside this window; the timeout only ever
      // fires on a genuinely stuck request.
      try {
        return await Geolocator.getCurrentPosition(
                locationSettings: LocationSettings(accuracy: accuracy))
            .timeout(const Duration(seconds: 12));
      } on TimeoutException {
        onError?.call('Location request timed out — try again');
        return null;
      }
    } catch (_) {
      onError?.call('Could not get your location');
      return null;
    }
  }

  /// Requests "always" (background) location access for the SOS ambient
  /// sharing layer -- must only be called after foreground access is
  /// already granted (both platforms require that before background access
  /// can be requested at all). Best-effort: a user who declines still gets
  /// full app access, they just won't appear in anyone's proximity match.
  static Future<bool> requestBackgroundPermission() async {
    final current = await Geolocator.checkPermission();
    if (current == LocationPermission.always) return true;
    final result = await Geolocator.requestPermission();
    return result == LocationPermission.always;
  }
}
