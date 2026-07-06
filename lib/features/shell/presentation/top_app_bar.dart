import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../bloc/shell_bloc.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_icons.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/auth/role_session.dart';

class AfosAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  const AfosAppBar({super.key, required this.title, this.actions});
  @override Size get preferredSize => const Size.fromHeight(60);

  bool get _isSuperAdmin => RoleSession.role == 'super_admin';

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    return AppBar(
      backgroundColor: AppColors.surfaceOf(context),
      elevation: 0,
      // Super admin gets a persistent, unmistakable visual signal across
      // every screen in the app (not just its own dedicated tools) — a
      // bolder solid violet underline plus a badge, rather than the thin
      // blended tri-color line every other role sees.
      bottom: PreferredSize(preferredSize: Size.fromHeight(_isSuperAdmin ? 2.5 : 1),
        child:Container(
          height: _isSuperAdmin ? 2.5 : 1,
          decoration: BoxDecoration(
            gradient: _isSuperAdmin
              ? LinearGradient(colors: [AppColors.holoviolet, AppColors.holoviolet.withValues(alpha: 0.4)])
              : LinearGradient(colors:[
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
      title: Row(children: [
        Flexible(child: Text(title, style:AppTextStyles.headlineMed.copyWith(color: textPrimary), overflow: TextOverflow.ellipsis)),
        if (_isSuperAdmin) Padding(padding: const EdgeInsets.only(left: 8), child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                gradient: LinearGradient(colors: [AppColors.holoviolet, AppColors.holoviolet.withValues(alpha: 0.6)]),
                borderRadius: BorderRadius.circular(20)),
            child: const Text('SUPER ADMIN', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5)))),
      ]),
      actions: [
        ...?actions,
        IconButton(
          icon:Icon(AppIcons.notifications,color:textPrimary),
          onPressed:()=>context.push('/notifications'),
        ),
        const SizedBox(width:8),
      ],
    );
  }
}
