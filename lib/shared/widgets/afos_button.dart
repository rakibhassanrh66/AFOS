import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../config/theme/app_colors.dart';

class AfosButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool loading;
  final bool outlined;
  final IconData? icon;
  final Color? color;

  const AfosButton({super.key, required this.label, this.onTap,
    this.loading=false, this.outlined=false, this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final bg = color ?? AppColors.blue;
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds:200),
        height: 52,
        decoration: BoxDecoration(
          gradient: outlined ? null : LinearGradient(colors:[bg, bg.withOpacity(0.8)],begin:Alignment.topLeft,end:Alignment.bottomRight),
          border: outlined ? Border.all(color:bg,width:1.5) : null,
          borderRadius: BorderRadius.circular(12),
          color: outlined ? Colors.transparent : null,
        ),
        child: loading
          ? const Center(child:SizedBox(width:22,height:22,child:CircularProgressIndicator(color:Colors.white,strokeWidth:2)))
          : Row(mainAxisAlignment:MainAxisAlignment.center, children:[
              if(icon!=null) ...[Icon(icon,color:outlined?bg:Colors.white,size:18), const SizedBox(width:8)],
              Text(label, style:TextStyle(color:outlined?bg:Colors.white,fontSize:15,fontWeight:FontWeight.w600)),
            ]),
      ),
    ).animate().scale(begin:const Offset(1,1),duration:100.ms,curve:Curves.easeInOut);
  }
}
