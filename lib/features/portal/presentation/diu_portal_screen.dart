import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../shell/presentation/top_app_bar.dart';

/// In-app browser for a DIU student-portal page, styled to sit inside AFOS
/// rather than look like a browser someone bolted on.
///
/// **Why this is a WebView and not a native rebuild.** The portal is behind a
/// Cloudflare bot challenge: every path answers HTTP 403 with
/// `Cf-Mitigated: challenge` to any non-browser client — verified directly,
/// including with a genuine desktop Chrome User-Agent. Clearance requires
/// running the challenge JavaScript, so an edge-function scraper cannot read
/// these pages at all. Building something to defeat that would be circumventing
/// an access control the university chose to put there, and it would break the
/// first time they retune it. A WebView clears the challenge the way it is meant
/// to be cleared, and the student authenticates with their own credentials.
///
/// **The blank-page bug this replaces.** `payment_webview_screen.dart`
/// allowlisted exactly one host and returned `NavigationDecision.prevent` for
/// anything else, while `onHttpError` and `onWebResourceError` were both empty
/// `{}`. Signing in redirects off that single host (Cloudflare, then DIU's login
/// host), so navigation was blocked and *nothing said so* — the user got a blank
/// screen. Here, navigation is allowed across the DIU host family, and every
/// failure path renders a real message with an escape hatch to the system
/// browser instead of failing silently.
class DiuPortalScreen extends StatefulWidget {
  final String title;
  final String url;
  const DiuPortalScreen({super.key, required this.title, required this.url});

  @override
  State<DiuPortalScreen> createState() => _DiuPortalScreenState();
}

class _DiuPortalScreenState extends State<DiuPortalScreen> {
  WebViewController? _ctrl;
  int _progress = 0;
  String? _error;
  bool _disposed = false;

  static bool _isDiuHost(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    if (host.isEmpty) return false;
    return AppConfig.diuTrustedHostSuffixes
        .any((s) => host == s || host.endsWith('.$s'));
  }

  @override
  void initState() {
    super.initState();
    if (kIsWeb) return;
    _ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (req) {
          if (req.url == 'about:blank' || _isDiuHost(req.url)) {
            return NavigationDecision.navigate;
          }
          // Anything genuinely off-DIU (a partner link on the Facilities page,
          // say) goes to the system browser rather than being silently
          // swallowed — the old screen's failure mode.
          launchUrl(Uri.parse(req.url), mode: LaunchMode.externalApplication);
          return NavigationDecision.prevent;
        },
        onProgress: (p) {
          if (!_disposed && mounted) setState(() => _progress = p);
        },
        onPageStarted: (_) {
          if (!_disposed && mounted) setState(() => _error = null);
        },
        // Previously `(e) {}`. A Cloudflare challenge (403) or any portal error
        // therefore produced a blank screen with no explanation at all.
        onHttpError: (e) {
          if (_disposed || !mounted) return;
          final status = e.response?.statusCode;
          if (status == null || status < 400) return;
          setState(() => _error = status == 403
              ? 'The portal blocked this request (403). This usually clears if '
                  'you open it in your browser once and sign in there.'
              : 'The portal returned an error ($status).');
        },
        onWebResourceError: (e) {
          if (_disposed || !mounted) return;
          // Sub-resource failures (an image, a font) must not blank the page.
          if (!e.isForMainFrame.orTrue) return;
          setState(() => _error = e.description.isEmpty
              ? 'Could not load the portal. Check your connection.'
              : e.description);
        },
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  void dispose() {
    _disposed = true;
    _ctrl?.loadRequest(Uri.parse('about:blank'));
    super.dispose();
  }

  Future<void> _openExternally() async {
    await launchUrl(Uri.parse(widget.url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AfosAppBar(title: widget.title, actions: [
        IconButton(
          tooltip: 'Open in browser',
          icon: const Icon(Icons.open_in_new_rounded),
          onPressed: _openExternally,
        ),
        if (!kIsWeb)
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _ctrl?.reload(),
          ),
      ]),
      body: kIsWeb
          ? _Fallback(title: widget.title, onOpen: _openExternally)
          : Column(children: [
              if (_progress > 0 && _progress < 100)
                LinearProgressIndicator(
                  value: _progress / 100,
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                  color: AppColors.holoTeal,
                ),
              Expanded(
                child: _error != null
                    ? _ErrorPane(
                        message: _error!,
                        onRetry: () {
                          setState(() => _error = null);
                          _ctrl?.loadRequest(Uri.parse(widget.url));
                        },
                        onOpen: _openExternally,
                      )
                    : WebViewWidget(controller: _ctrl!),
              ),
            ]),
    );
  }
}

extension on bool? {
  /// `isForMainFrame` is nullable on some platform implementations; treat an
  /// unknown as "main frame" so a real failure is never swallowed.
  bool get orTrue => this ?? true;
}

class _ErrorPane extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onOpen;
  const _ErrorPane({required this.message, required this.onRetry, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.public_off_rounded, size: 44, color: AppColors.amber),
          const SizedBox(height: 16),
          Text('Portal unavailable',
              style: AppTextStyles.headlineLarge
                  .copyWith(color: AppColors.textPrimaryOf(context)),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(message,
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textSecondaryOf(context)),
              textAlign: TextAlign.center),
          const SizedBox(height: 22),
          AfosButton(label: 'Try again', icon: Icons.refresh_rounded, onTap: onRetry),
          const SizedBox(height: 10),
          AfosButton(
              label: 'Open in browser',
              icon: Icons.open_in_new_rounded,
              outlined: true,
              onTap: onOpen),
        ]),
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  final String title;
  final VoidCallback onOpen;
  const _Fallback({required this.title, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.open_in_browser_rounded, size: 44, color: AppColors.holoBlue),
          const SizedBox(height: 16),
          Text(title,
              style: AppTextStyles.headlineLarge
                  .copyWith(color: AppColors.textPrimaryOf(context)),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          // webview_flutter ships no web implementation here, so embedding on
          // web throws "WebViewPlatform.instance null" immediately.
          Text('Open this DIU page in a new tab to sign in.',
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textSecondaryOf(context)),
              textAlign: TextAlign.center),
          const SizedBox(height: 22),
          AfosButton(label: 'Open portal', icon: Icons.open_in_new_rounded, onTap: onOpen),
        ]),
      ),
    );
  }
}
