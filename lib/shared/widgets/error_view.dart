import 'package:flutter/material.dart';
import '../../config/theme/app_colors.dart';

class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const ErrorView({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(child:Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize:MainAxisSize.min, children:[
        const Icon(Icons.error_outline, color:AppColors.red, size:48),
        const SizedBox(height:16),
        Text(message, style:TextStyle(color:AppColors.textSecondaryOf(context)), textAlign:TextAlign.center),
        if(onRetry!=null) ...[
          const SizedBox(height:20),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ]),
    ));
  }
}
