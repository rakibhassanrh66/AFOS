import 'package:flutter/material.dart';
import '../../config/theme/app_colors.dart';

class AfosTextField extends StatefulWidget {
  final String hint;
  final TextEditingController? controller;
  final String? Function(String?)? validator;
  final bool obscure;
  final IconData? prefixIcon;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final void Function(String)? onChanged;
  final int? maxLines;
  final bool autocorrect;
  final bool enableSuggestions;

  const AfosTextField({super.key, required this.hint, this.controller,
    this.validator, this.obscure=false, this.prefixIcon, this.suffix,
    this.keyboardType, this.textInputAction, this.onChanged, this.maxLines=1,
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

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      validator: widget.validator,
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
          ? Icon(widget.prefixIcon, color: AppColors.textSecondaryOf(context), size: 20) : null,
        suffixIcon: widget.obscure
          ? IconButton(
              icon: Icon(_show?Icons.visibility_off:Icons.visibility,
                color:AppColors.textSecondaryOf(context), size:20),
              onPressed: () => setState(()=>_show=!_show))
          : widget.suffix,
      ),
    );
  }
}
