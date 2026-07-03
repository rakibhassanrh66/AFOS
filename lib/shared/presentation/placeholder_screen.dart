import 'package:flutter/material.dart';
import '../../config/theme/app_colors.dart';

class PlaceholderScreen extends StatelessWidget {
  final String title;
  final IconData icon;
  const PlaceholderScreen({super.key, required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(child: Center(child: Column(mainAxisSize:MainAxisSize.min, children:[
        Container(width:80,height:80,
          decoration:BoxDecoration(
            color: AppColors.blue.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color:AppColors.blue.withOpacity(0.3)),
          ),
          child: Icon(icon, color:AppColors.blue, size:36)),
        const SizedBox(height:20),
        Text(title, style:TextStyle(color:AppColors.textPrimaryOf(context),fontSize:20,fontWeight:FontWeight.bold)),
        const SizedBox(height:8),
        Text('Built in next prompt...', style:TextStyle(color:AppColors.textSecondaryOf(context),fontSize:14)),
      ]))),
    );
  }
}
