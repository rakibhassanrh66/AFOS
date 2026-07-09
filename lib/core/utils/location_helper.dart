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
      return await Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(accuracy: accuracy));
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
