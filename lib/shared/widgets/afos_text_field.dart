import 'package:flutter/material.dart';
import '../../config/theme/app_colors.dart';

class AfosTextField extends StatefulWidget {
  final String hint;
  final TextEditingController? controller;
  final String? Function(String?)? validator;
  final bool obscure;
  final IconData? prefixIcon;
  final Widget? suffix;
  // Optional extra trailing icon (e.g. a fingerprint quick-login button) shown
  // to the LEFT of the built-in show/hide eye toggle on obscured fields, so a
  // password field can offer both actions without the two icons overlapping.
  final IconData? trailingIcon;
  final VoidCallback? onTrailingIconTap;
  final String? trailingTooltip;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final void Function(String)? onChanged;
  final int? maxLines;
  final bool autocorrect;
  final bool enableSuggestions;

  // Focus plumbing. Without these the field owned a PRIVATE FocusNode that no
  // caller could reach, so nothing could autofocus a search box, focus it
  // programmatically, or react to a tap on it — every search in the app was
  // tap-to-focus only, and the "search" affordances that open a sheet landed
  // the user on an unfocused field with no keyboard. Supplying a node also
  // lets the CALLER own its lifetime, which matters because the node's
  // identity is what the IME connection hangs off.
  final FocusNode? focusNode;
  final bool autofocus;
  final VoidCallback? onTap;
  final void Function(String)? onSubmitted;
  final void Function(PointerDownEvent)? onTapOutside;

  const AfosTextField({super.key, required this.hint, this.controller,
    this.validator, this.obscure=false, this.prefixIcon, this.suffix,
    this.trailingIcon, this.onTrailingIconTap, this.trailingTooltip,
    this.keyboardType, this.textInputAction, this.onChanged, this.maxLines=1,
    this.focusNode, this.autofocus=false, this.onTap, this.onSubmitted,
    this.onTapOutside,
    // Autocorrect/suggestions have no purpose on an obscured password
    // field, and combined with certain Gboard versions on newer Android
    // (reported: Android 15/16) they've been known to fight the IME's own
    // composing region and shove the cursor to the end of the field the
    // moment space is pressed mid-word — reads as "I can't edit/move
    // through what I already typed". Off by default for obscured fields;
    // callers can still opt back in per-field.
    bool? autocorrect, bool? enableSuggestions})
      : autocorrect = autocorrect ?? !obscure,
        enableSuggestions = enableSuggestions ?? !obscure;

  @override State<AfosTextField> createState() => _AfosTextFieldState();
}

class _AfosTextFieldState extends State<AfosTextField> {
  bool _show = false;
  bool _hover = false;
  bool _focused = false;

  /// Only created when the caller didn't supply one — and only *that* one is
  /// disposed here. Disposing a caller-owned node would tear down a node the
  /// caller may still be using (and will dispose itself).
  FocusNode? _ownedNode;
  FocusNode get _focusNode => widget.focusNode ?? (_ownedNode ??= FocusNode());

  void _onFocusChange() {
    if (mounted) setState(() => _focused = _focusNode.hasFocus);
  }

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(AfosTextField old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _ownedNode)?.removeListener(_onFocusChange);
      _focusNode.addListener(_onFocusChange);
    }
  }

  @override
  void dispose() {
    (widget.focusNode ?? _ownedNode)?.removeListener(_onFocusChange);
    _ownedNode?.dispose();
    super.dispose();
  }

  /// Builds the trailing suffix: the built-in show/hide eye toggle (obscured
  /// fields only) plus, when [AfosTextField.trailingIcon] is supplied, an extra
  /// icon button to its left. Each button is a full ≥48dp target and the two
  /// never overlap the field text or border.
  Widget? _buildSuffix(BuildContext context) {
    final Widget? eye = widget.obscure
        ? IconButton(
            icon: Icon(_show ? Icons.visibility_off : Icons.visibility,
                color: AppColors.textSecondaryOf(context), size: 20),
            tooltip: _show ? 'Hide password' : 'Show password',
            onPressed: () => setState(() => _show = !_show))
        : widget.suffix;
    if (widget.trailingIcon == null) return eye;
    final trailing = IconButton(
      icon: Icon(widget.trailingIcon, color: AppColors.holoBlue, size: 22),
      tooltip: widget.trailingTooltip,
      onPressed: widget.onTrailingIconTap,
    );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      trailing,
      if (eye != null) eye,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final active = _focused || _hover;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: _focused ? [
            BoxShadow(color: AppColors.holoBlue.withValues(alpha: 0.22), blurRadius: 16, spreadRadius: -2),
          ] : null,
        ),
        child: TextFormField(
          controller: widget.controller,
          validator: widget.validator,
          focusNode: _focusNode,
          autofocus: widget.autofocus,
          onTap: widget.onTap,
          onFieldSubmitted: widget.onSubmitted,
          onTapOutside: widget.onTapOutside,
          obscureText: widget.obscure && !_show,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          onChanged: widget.onChanged,
          maxLines: widget.obscure ? 1 : widget.maxLines,
          autocorrect: widget.autocorrect,
          enableSuggestions: widget.enableSuggestions,
          style: TextStyle(color: AppColors.textPrimaryOf(context), fontSize: 15),
          decoration: InputDecoration(
            hintText: widget.hint,
            prefixIcon: widget.prefixIcon != null
              ? AnimatedScale(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  scale: active ? 1.1 : 1.0,
                  child: Icon(widget.prefixIcon,
                      color: active ? AppColors.holoBlue : AppColors.textSecondaryOf(context), size: 20))
              : null,
            // Fixed-width suffix slot so a second (fingerprint) icon can sit
            // beside the eye toggle with full ≥48dp targets and no overlap.
            suffixIconConstraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            suffixIcon: _buildSuffix(context),
          ),
        ),
      ),
    );
  }
}
