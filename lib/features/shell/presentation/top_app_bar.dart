import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../bloc/shell_bloc.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';

class AfosAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  const AfosAppBar({super.key, required this.title, this.actions});
  @override Size get preferredSize => const Size.fromHeight(60);
  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    return AppBar(
      backgroundColor: AppColors.surfaceOf(context),
      elevation: 0,
      bottom: PreferredSize(preferredSize:const Size.fromHeight(1),
        child:Container(
          height:1,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors:[
              AppColors.holoBlue.withOpacity(0.35),
              AppColors.holoviolet.withOpacity(0.25),
              AppColors.holoTeal.withOpacity(0.35),
            ]),
          ),
        )),
      leading: IconButton(
        icon: BlocBuilder<ShellBloc,ShellState>(
          builder:(_,state) => AnimatedSwitcher(
            duration:const Duration(milliseconds:200),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (child, anim) => RotationTransition(
              turns: Tween(begin: 0.75, end: 1.0).animate(anim),
              child: FadeTransition(opacity: anim, child: child),
            ),
            child:Icon(state.isOpen?Icons.close:Icons.menu_rounded,
              key:ValueKey(state.isOpen),color:textPrimary))),
        onPressed:()=>context.read<ShellBloc>().add(ToggleMenu()),
      ),
      title: Text(title, style:AppTextStyles.headlineMed.copyWith(color: textPrimary)),
      actions: [
        ...?actions,
        IconButton(
          icon:Icon(Icons.notifications_rounded,color:textPrimary),
          onPressed:()=>context.go('/notifications'),
        ),
        const SizedBox(width:8),
      ],
    );
  }
}
