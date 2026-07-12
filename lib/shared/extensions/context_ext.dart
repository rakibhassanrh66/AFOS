import 'package:flutter/material.dart';
import '../../config/theme/app_colors.dart';

extension ContextExt on BuildContext {
  ThemeData    get theme   => Theme.of(this);
  ColorScheme  get colors  => Theme.of(this).colorScheme;
  TextTheme    get text    => Theme.of(this).textTheme;
  Size         get size    => MediaQuery.of(this).size;
  double       get width   => MediaQuery.of(this).size.width;
  double       get height  => MediaQuery.of(this).size.height;
  bool         get isDark  => Theme.of(this).brightness == Brightness.dark;
  EdgeInsets   get padding => MediaQuery.of(this).padding;

  void showSnack(String msg, {bool isError=false}) {
    ScaffoldMessenger.of(this).clearSnackBars();
    ScaffoldMessenger.of(this).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: isError ? AppColors.red : AppColors.green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
    ));
  }
}
