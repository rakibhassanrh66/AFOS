import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

/// A `flutter_map` tile provider that keeps tiles on DISK between sessions.
///
/// ---------------------------------------------------------------------------
/// WHAT WAS WRONG
///
/// Both maps in this app (Transport, and the SOS alert detail) used
/// `TileLayer`'s default provider. In flutter_map 7.0.2 that is
/// `NetworkTileProvider`, and its only cache is Flutter's IN-MEMORY
/// `PaintingBinding.instance.imageCache` — read the package source, there is no
/// disk layer. Every tile is therefore re-downloaded:
///
///   * on every cold start,
///   * after the image cache evicts under memory pressure, which an
///     entry-level phone does constantly,
///   * and for any tile that scrolls far enough out of view.
///
/// So opening Transport in Dhaka meant pulling a fresh screenful of tiles from
/// OpenStreetMap over a mobile connection, every single time, and staring at
/// grey squares while it happened. That is a large part of "all over the map
/// sucks": before the route is even wrong, the basemap is not there yet.
///
/// ---------------------------------------------------------------------------
/// WHY cached_network_image AND NOT A NEW PACKAGE
///
/// `flutter_map_cache` exists and is the usual answer. It is also another
/// dependency, another transitive tree, and more bytes in an APK already 7 MB
/// over its budget. `cached_network_image` is ALREADY a direct dependency —
/// six widgets use it — and `CachedNetworkImageProvider` is an `ImageProvider`,
/// which is exactly and only what a tile provider has to return. Zero new
/// dependencies, and tiles share the same disk cache machinery the rest of the
/// app's images already use.
///
/// ---------------------------------------------------------------------------
/// THE TILE USAGE POLICY IS A REASON TO DO THIS, NOT A REASON NOT TO
///
/// OpenStreetMap's tile policy asks consumers to cache aggressively and not to
/// re-request tiles they already hold. Shipping without a disk cache was not
/// only slow for the user, it was the less courteous option toward a free
/// service we depend on. The `User-Agent` the policy also requires is still
/// sent — see [userAgentPackageName] on the layers themselves.
class CachedTileProvider extends TileProvider {
  CachedTileProvider({super.headers});

  @override
  ImageProvider<Object> getImage(TileCoordinates coordinates, TileLayer options) =>
      CachedNetworkImageProvider(
        getTileUrl(coordinates, options),
        // flutter_map's own headers (User-Agent included) forwarded intact:
        // OSM's policy makes identifying the app a condition of use, and the
        // request is ours to identify whether or not we are caching the result.
        headers: headers,
      );
}
