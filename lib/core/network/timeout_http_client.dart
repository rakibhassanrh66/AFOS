import 'dart:async';
import 'package:http/http.dart' as http;

/// Wraps every request Supabase makes (Postgrest, Storage, Edge Functions —
/// Realtime is a websocket and doesn't go through this) with a hard deadline.
///
/// Without this, a network that accepts the connection but leads nowhere
/// (dead WiFi uplink, captive portal never signed into) leaves `package:http`
/// waiting on the platform's own socket timeout, which on Android can run
/// well past a minute. `cachedListFetch` already bounds the screens that go
/// through it, but a third of this app's screens query Supabase directly and
/// have no such wrapper -- this is the one place that protects those too,
/// without touching any of those call sites.
class TimeoutHttpClient extends http.BaseClient {
  TimeoutHttpClient(
    this._inner, {
    this.timeout = const Duration(seconds: 15),
    this.uploadTimeout = const Duration(seconds: 60),
  });

  final http.Client _inner;
  final Duration timeout;
  final Duration uploadTimeout;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    // A PDF/assignment-submission upload is genuinely large and can take
    // real seconds on a slow-but-working connection -- the same 15s bound
    // that correctly kills a dead-network Postgrest query would just as
    // correctly abort a legitimate multi-MB upload still in flight. Storage
    // writes get a longer budget instead of exempting them entirely, so a
    // truly dead connection still gives up rather than hanging forever.
    final isStorageWrite = request.url.path.contains('/storage/v1/object/') &&
        (request.method == 'POST' || request.method == 'PUT');
    return _inner.send(request).timeout(isStorageWrite ? uploadTimeout : timeout);
  }

  @override
  void close() => _inner.close();
}
