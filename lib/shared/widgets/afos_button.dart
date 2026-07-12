import 'package:flutter/material.dart';
import '../../config/theme/app_colors.dart';
import 'supernova_loader.dart';

class AfosButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final bool loading;
  final bool outlined;
  final IconData? icon;
  final Color? color;

  const AfosButton({super.key, required this.label, this.onTap,
    this.loading=false, this.outlined=false, this.icon, this.color});

  @override
  State<AfosButton> createState() => _AfosButtonState();
}

class _AfosButtonState extends State<AfosButton> {
  bool _pressed = false;
  bool _hover = false;

  void _setPressed(bool v) {
    if (widget.loading || widget.onTap == null) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.color ?? AppColors.blue;
    return MouseRegion(
      // No-op on touch (Android/iOS) -- this only ever fires with an
      // actual mouse on web/desktop.
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: widget.loading || widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.loading ? null : widget.onTap,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        child: AnimatedScale(
          scale: _pressed ? 0.97 : (_hover ? 1.015 : 1.0),
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds:220),
            curve: Curves.easeOutCubic,
            height: 52,
            decoration: BoxDecoration(
              gradient: widget.outlined ? null : LinearGradient(
                colors:[bg, AppColors.holoviolet.withValues(alpha: 0.85)],
                begin:Alignment.topLeft,end:Alignment.bottomRight),
              border: widget.outlined
                  ? Border.all(color: _hover ? bg : bg.withValues(alpha: 0.7), width: 1.5)
                  : null,
              borderRadius: BorderRadius.circular(14),
              color: widget.outlined ? (_hover ? bg.withValues(alpha: 0.08) : Colors.transparent) : null,
              boxShadow: widget.outlined ? null : [
                BoxShadow(color: bg.withValues(alpha: _hover ? 0.5 : 0.35),
                    blurRadius: _hover ? 26 : 18, spreadRadius: -2, offset: const Offset(0,6)),
              ],
            ),
            child: widget.loading
              ? Center(child: SupernovaLoader(size: 24, color: widget.outlined ? bg : Colors.white))
              : Row(mainAxisAlignment:MainAxisAlignment.center, children:[
                  if(widget.icon!=null) ...[Icon(widget.icon,color:widget.outlined?bg:Colors.white,size:18), const SizedBox(width:8)],
                  Text(widget.label, style:TextStyle(color:widget.outlined?bg:Colors.white,fontSize:15,fontWeight:FontWeight.w600)),
                ]),
          ),
        ),
      ),
    );
  }
}
