import '../../config/theme/motion.dart';
import 'package:flutter/material.dart';
import '../../config/theme/app_colors.dart';
import '../../config/theme/liquid_glass_tokens.dart';
import 'pressable.dart';

/// One unified selectable chip replacing the ~10 hand-rolled `_Chip`,
/// `_ThemeChip`, `_GenderChip`, `_TypeChip`, `_PeriodChip`, `_SelectedChip`,
/// etc. Pill-shaped, glossy when selected, glass-outlined when not, with a web
/// hover state and overflow-safe label (truncates inside the pill).
///
/// Use [PillBadge] instead for read-only status tags.
class GlassChip extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color? color;
  final bool expand;

  const GlassChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.icon,
    this.color,
    this.expand = false,
  });

  @override
  State<GlassChip> createState() => _GlassChipState();
}

class _GlassChipState extends State<GlassChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    // Falls back to the USER'S accent, not a fixed blue. A caller that passes
    // an explicit colour still wins — those are the semantic ones (a red
    // "Cancelled" filter must stay red).
    final accent = widget.color ?? AppColors.accentOf(context);
    final selected = widget.selected;
    // Foreground by luminance rather than a hardcoded white: several pickable
    // accents (amber, teal) are light enough that white on them is unreadable.
    final fg = selected
        ? AppColors.foregroundOn(accent)
        : AppColors.textSecondaryOf(context);

    final chip = AnimatedContainer(
      duration: AppMotion.tight,
      curve: AppMotion.standard,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        gradient: selected
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [accent, accent.withValues(alpha: 0.72)],
              )
            : null,
        color: selected
            ? null
            : (_hover
                ? accent.withValues(alpha: 0.10)
                : AppColors.glassFill(context)),
        borderRadius: BorderRadius.circular(LiquidGlass.radiusPill),
        border: Border.all(
          color: selected
              ? Colors.transparent
              : (_hover ? accent.withValues(alpha: 0.5) : AppColors.glassBorder(context)),
          width: 1,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (widget.icon != null) ...[
            Icon(widget.icon, size: 15, color: fg),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              textHeightBehavior: const TextHeightBehavior(
                  applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
              style: TextStyle(
                color: selected ? Colors.white : (_hover ? accent : fg),
                fontSize: 12.5,
                height: 1.0,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      // The chip already animates its SELECTED state; what it had no answer
      // for was the press itself. `haptic: false` because selection chips are
      // often tapped in quick succession while filtering, and a buzz per chip
      // in a filter row is noise rather than confirmation.
      child: Pressable(onTap: widget.onTap, haptic: false, child: chip),
    );
  }
}
