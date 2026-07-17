import 'package:flutter/material.dart';
import '../../config/theme/app_colors.dart';
import '../../config/theme/liquid_glass_tokens.dart';

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
    final accent = widget.color ?? AppColors.blue;
    final selected = widget.selected;
    final fg = selected ? Colors.white : AppColors.textSecondaryOf(context);

    final chip = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
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
      child: GestureDetector(onTap: widget.onTap, child: chip),
    );
  }
}
