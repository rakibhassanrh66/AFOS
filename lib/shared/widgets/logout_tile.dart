import 'package:flutter/material.dart';
import '../../config/theme/app_colors.dart';
import '../../config/theme/app_icons.dart';
import '../../config/theme/liquid_glass_tokens.dart';

/// The red gradient "log out" row — one component replacing the two identical
/// hand-rolled copies (settings_screen + slide_menu). Overflow-safe label.
class LogoutTile extends StatelessWidget {
  final VoidCallback onTap;
  final String label;
  const LogoutTile({super.key, required this.onTap, this.label = 'Log Out'});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(LiquidGlass.radiusControl),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(LiquidGlass.radiusControl),
            gradient: LinearGradient(colors: [
              AppColors.red.withValues(alpha: 0.14),
              AppColors.red.withValues(alpha: 0.05),
            ]),
            border: Border.all(color: AppColors.red.withValues(alpha: 0.25)),
          ),
          child: Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                  color: AppColors.red.withValues(alpha: 0.16), shape: BoxShape.circle),
              child: const Icon(AppIcons.logout, color: AppColors.red, size: 19),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppColors.red, fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: AppColors.red.withValues(alpha: 0.6), size: 20),
          ]),
        ),
      ),
    );
  }
}
