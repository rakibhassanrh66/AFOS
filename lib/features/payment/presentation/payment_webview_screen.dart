import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../config/app_config.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';

class PaymentWebViewScreen extends StatefulWidget {
  final String category;
  const PaymentWebViewScreen({super.key, required this.category});
  @override State<PaymentWebViewScreen> createState() => _PayWebViewState();
}

// webview_flutter only ships Android/iOS platform implementations here (no
// webview_flutter_web dependency) — embedding WebViewWidget on web throws
// "WebViewPlatform.instance null" immediately. Banking/payment gateways also
// commonly set X-Frame-Options to block iframe embedding regardless, so on
// web this opens the payment portal in a real browser tab instead of trying
// to embed it, matching the kIsWeb fallback pattern used in vr_id_screen.dart.
class _WebPaymentFallback extends StatelessWidget {
  final String category;
  const _WebPaymentFallback({required this.category});
  @override
  Widget build(BuildContext context) => Center(child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.open_in_new_rounded, color: AppColors.textSecondaryOf(context), size: 40),
        const SizedBox(height: 16),
        Text('Pay $category outside the app', textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textPrimaryOf(context), fontWeight: FontWeight.w600, fontSize: 16)),
        const SizedBox(height: 8),
        Text('The payment portal opens in a new browser tab on web.', textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondaryOf(context))),
        const SizedBox(height: 20),
        FilledButton.icon(
            onPressed: () => launchUrl(Uri.parse(AppConfig.diuPaymentUrl), mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('Open payment portal')),
      ])));
}

class _PayWebViewState extends State<PaymentWebViewScreen> {
  WebViewController? _ctrl;
  int _progress = 0;
  bool _disposed = false;

  // The only origin allowed to receive the injected Supabase identity/token
  // and the only host this webview is permitted to navigate to. Anything
  // else (a redirect off-portal, an XSS-driven navigation, a crafted link)
  // is blocked so the user's live JWT can never be handed to another origin.
  static final String _trustedHost = Uri.parse(AppConfig.diuPaymentUrl).host;

  bool _isTrusted(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    // Exact host or a subdomain of the trusted payment host.
    return host == _trustedHost || host.endsWith('.$_trustedHost');
  }

  @override
  void initState() {
    super.initState();
    if (kIsWeb) return;
    final ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (req) {
          // about:blank is used on dispose; everything else must be the
          // trusted payment host.
          if (req.url == 'about:blank' || _isTrusted(req.url)) {
            return NavigationDecision.navigate;
          }
          return NavigationDecision.prevent;
        },
        onProgress: (p) { if (!_disposed && mounted) setState(() => _progress = p); },
        onPageFinished: (url) {
          if (_disposed) return;
          // Only hand the student id + live session token to the genuine
          // DIU portal origin — never to any page that a redirect or
          // injection could have steered the webview onto.
          if (!_isTrusted(url)) return;
          _ctrl?.runJavaScript(
              "window.afosStudentId='${SupabaseConfig.uid ?? ''}'; "
              "window.afosToken='${SupabaseConfig.jwt ?? ''}';");
        },
        onHttpError: (e) {},
        onWebResourceError: (e) {},
      ))
      ..addJavaScriptChannel('AFOSPayment',
          onMessageReceived: (msg) {
            if (_disposed || !mounted) return;
            if (msg.message == 'PAYMENT_SUCCESS') {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Payment successful!'),
                    backgroundColor: AppColors.green));
              Navigator.pop(context);
            }
          })
      ..loadRequest(Uri.parse(AppConfig.diuPaymentUrl));
    _ctrl = ctrl;
  }

  // Stopping in-flight navigation/JS before the platform view is torn down
  // avoids a native crash some Android WebView builds hit when disposed
  // mid-navigation.
  @override
  void dispose() {
    _disposed = true;
    _ctrl?.loadRequest(Uri.parse('about:blank'));
    super.dispose();
  }

  Future<void> _confirmAndLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.surfaceOf(dialogCtx),
        title: Text('Leave payment?',
            style: TextStyle(color: AppColors.textPrimaryOf(dialogCtx))),
        content: Text('Your payment may be incomplete.',
            style: TextStyle(color: AppColors.textSecondaryOf(dialogCtx))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: Text('Stay', style: TextStyle(color: AppColors.textSecondaryOf(dialogCtx)))),
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('Leave', style: TextStyle(color: AppColors.red))),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _confirmAndLeave();
      },
      child: Builder(builder: (scaffoldCtx) => Scaffold(
        backgroundColor: AppColors.isDark(scaffoldCtx) ? AppColors.background : AppColors.lightBg,
        appBar: AppBar(
          backgroundColor: AppColors.surfaceOf(scaffoldCtx),
          title: Text(widget.category, style: TextStyle(color: AppColors.textPrimaryOf(scaffoldCtx))),
          leading: IconButton(
            icon: Icon(Icons.close, color: AppColors.textPrimaryOf(scaffoldCtx)),
            onPressed: _confirmAndLeave,
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(3),
            child: _progress < 100
                ? LinearProgressIndicator(value: _progress / 100,
                    backgroundColor: AppColors.borderOf(scaffoldCtx), color: AppColors.holoBlue)
                : const SizedBox.shrink(),
          ),
        ),
        body: kIsWeb ? _WebPaymentFallback(category: widget.category) : WebViewWidget(controller: _ctrl!),
      )),
    );
  }
}
