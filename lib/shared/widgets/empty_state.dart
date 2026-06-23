import 'package:flutter/material.dart';
import '../../config/theme/app_colors.dart';
import '../../config/theme/app_text_styles.dart';

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  const EmptyState({super.key, required this.icon, required this.title,
    required this.subtitle, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize:MainAxisSize.min, children:[
          Container(width:80, height:80,
            decoration:BoxDecoration(
              color: AppColors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color:AppColors.blue.withOpacity(0.2)),
            ),
            child: Icon(icon, color:AppColors.blue, size:36),
          ),
          const SizedBox(height:20),
          Text(title, style:AppTextStyles.headlineLarge, textAlign:TextAlign.center),
          const SizedBox(height:8),
          Text(subtitle, style:AppTextStyles.bodyMedium, textAlign:TextAlign.center),
          if(actionLabel!=null && onAction!=null) ...[
            const SizedBox(height:24),
            ElevatedButton(onPressed:onAction, child:Text(actionLabel!)),
          ],
        ]),
      ),
    );
  }
}
