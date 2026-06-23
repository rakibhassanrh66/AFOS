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
    return AppBar(
      backgroundColor: AppColors.surface,
      elevation: 0,
      bottom: PreferredSize(preferredSize:const Size.fromHeight(0.5),
        child:Container(height:0.5,color:AppColors.border)),
      leading: IconButton(
        icon: BlocBuilder<ShellBloc,ShellState>(
          builder:(_,state) => AnimatedSwitcher(duration:const Duration(milliseconds:200),
            child:Icon(state.isOpen?Icons.close:Icons.menu_rounded,
              key:ValueKey(state.isOpen),color:AppColors.textPrimary))),
        onPressed:()=>context.read<ShellBloc>().add(ToggleMenu()),
      ),
      title: Text(title, style:AppTextStyles.headlineMed),
      actions: [
        ...?actions,
        IconButton(
          icon:const Icon(Icons.notifications_rounded,color:AppColors.textPrimary),
          onPressed:()=>context.go('/notifications'),
        ),
        const SizedBox(width:8),
      ],
    );
  }
}
