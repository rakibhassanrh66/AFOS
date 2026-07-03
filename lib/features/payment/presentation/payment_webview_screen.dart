import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../config/app_config.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';

class PaymentWebViewScreen extends StatefulWidget {
  final String category;
  const PaymentWebViewScreen({super.key, required this.category});
  @override State<PaymentWebViewScreen> createState() => _PayWebViewState();
}

class _PayWebViewState extends State<PaymentWebViewScreen> {
  late final WebViewController _ctrl;
  int _progress = 0;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) { if (!_disposed && mounted) setState(() => _progress = p); },
        onPageFinished: (_) {
          if (_disposed) return;
          _ctrl.runJavaScript(
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
  }

  // Stopping in-flight navigation/JS before the platform view is torn down
  // avoids a native crash some Android WebView builds hit when disposed
  // mid-navigation.
  @override
  void dispose() {
    _disposed = true;
    _ctrl.loadRequest(Uri.parse('about:blank'));
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
        body: WebViewWidget(controller: _ctrl),
      )),
    );
  }
}
