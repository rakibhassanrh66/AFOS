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

  @override
  void initState() {
    super.initState();
    _ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) => setState(() => _progress = p),
        onPageFinished: (_) {
          _ctrl.runJavaScript(
              "window.afosStudentId='${SupabaseConfig.uid ?? ''}'; "
              "window.afosToken='${SupabaseConfig.jwt ?? ''}';");
        },
        onHttpError: (e) {},
        onWebResourceError: (e) {},
      ))
      ..addJavaScriptChannel('AFOSPayment',
          onMessageReceived: (msg) {
            if (msg.message == 'PAYMENT_SUCCESS') {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Payment successful!'),
                    backgroundColor: AppColors.green));
              Navigator.pop(context);
            }
          })
      ..loadRequest(Uri.parse(AppConfig.diuPaymentUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text(widget.category, style: const TextStyle(color: AppColors.textPrimary)),
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppColors.textPrimary),
          onPressed: () async {
            final leave = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: AppColors.card,
                title: const Text('Leave payment?', style: TextStyle(color: Colors.white)),
                content: const Text('Your payment may be incomplete.',
                    style: TextStyle(color: AppColors.textSecondary)),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Stay')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Leave', style: TextStyle(color: AppColors.red))),
                ],
              ),
            );
            if (leave == true && context.mounted) Navigator.pop(context);
          },
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: _progress < 100
              ? LinearProgressIndicator(value: _progress / 100,
                  backgroundColor: AppColors.border, color: AppColors.blue)
              : const SizedBox.shrink(),
        ),
      ),
      body: WebViewWidget(controller: _ctrl),
    );
  }
}
