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
    // Scrolls ONLY when it genuinely doesn't fit.
    //
    // The content is a fixed ~330px (80px icon + title + subtitle + action), so
    // it overflows the bottom of a 568px-tall phone once text size reaches 1.6x.
    // Wrapping it in an unconditional SingleChildScrollView fixes that, but then
    // every empty state feels loose and draggable even with plenty of room --
    // wrong, and immediately noticeable in the app. LayoutBuilder keeps the
    // rigid centred layout in the normal case and only becomes scrollable in
    // the case that would otherwise clip.
    return LayoutBuilder(builder: (context, constraints) {
      final content = Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 80, height: 80,
            decoration: BoxDecoration(
              color: AppColors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.blue.withValues(alpha: 0.2)),
            ),
            child: Icon(icon, color: AppColors.blue, size: 36),
          ),
          const SizedBox(height: 20),
          Text(title,
              style: AppTextStyles.headlineLarge.copyWith(color: AppColors.textPrimaryOf(context)),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(subtitle,
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context)),
              textAlign: TextAlign.center),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 24),
            ElevatedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ]),
      );

      // Unbounded height (inside a Column/sliver): nothing can overflow, so keep
      // the plain rigid layout.
      if (!constraints.hasBoundedHeight) return Center(child: content);

      return Center(
        child: SingleChildScrollView(
          // Clamping, not the platform default: no iOS rubber-band on a view
          // that normally shouldn't move at all.
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(child: content),
          ),
        ),
      );
    });
  }
}
