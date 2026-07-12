import 'package:flutter/material.dart';
import '../../config/theme/app_colors.dart';

/// Pill-style tab selector shared across admin management screens (Manage
/// Clubs, Manage Conference Rooms, Manage Dept Chat, Manage Exam Seats,
/// Manage Library) — matches the gradient pill pattern used everywhere else
/// in the app instead of each screen's own plain Material TabBar.
class AdminTabPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final Gradient gradient;
  const AdminTabPill({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.gradient = AppColors.holoGradient,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
          gradient: selected ? gradient : null,
          color: selected ? null : AppColors.glassFill(context),
          borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 16, color: selected ? Colors.white : AppColors.textSecondaryOf(context)),
        const SizedBox(width: 6),
        Flexible(child: Text(label, textAlign: TextAlign.center,
            textHeightBehavior: const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: selected ? Colors.white : AppColors.textSecondaryOf(context),
                fontSize: 12, height: 1.0, fontWeight: selected ? FontWeight.w700 : FontWeight.w500))),
      ]),
    ),
  );
}
