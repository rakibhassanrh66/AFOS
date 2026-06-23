import 'package:flutter/foundation.dart';
class AppLogger {
  AppLogger._();
  static void d(String msg,{String? tag}) { if(kDebugMode) debugPrint('[D]${tag!=null?"[$tag]":""} $msg'); }
  static void i(String msg,{String? tag}) { if(kDebugMode) debugPrint('[I]${tag!=null?"[$tag]":""} $msg'); }
  static void w(String msg,{String? tag}) { if(kDebugMode) debugPrint('[W]${tag!=null?"[$tag]":""} $msg'); }
  static void e(String msg,{String? tag,Object? error}) {
    if(kDebugMode) debugPrint('[E]${tag!=null?"[$tag]":""} $msg${error!=null?" | $error":""}');
  }
}
