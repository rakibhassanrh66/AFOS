import '../../config/app_config.dart';

enum AccountType { student, teacher }

class AppValidators {
  AppValidators._();
  static String? email(String? v) {
    if(v==null||v.trim().isEmpty) return 'Email required';
    final e = v.trim();
    if(!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,10}$').hasMatch(e)) return 'Invalid email';
    final isAllowlisted = AppConfig.emailDomainAllowlist.contains(e.toLowerCase());
    if(!e.toLowerCase().endsWith('edu.bd') && !isAllowlisted) {
      return 'Only university (edu.bd) email addresses can register';
    }
    return null;
  }
  static String? password(String? v) {
    if(v==null||v.isEmpty) return 'Password required';
    if(v.length<8) return 'Minimum 8 characters';
    if(!v.contains(RegExp(r'[A-Z]'))) return 'Need one uppercase letter';
    if(!v.contains(RegExp(r'[0-9]'))) return 'Need one number';
    return null;
  }
  static String? studentId(String? v, {AccountType type = AccountType.student}) {
    if(v==null||v.trim().isEmpty) {
      return type==AccountType.student ? 'Student ID required' : 'Employee ID required';
    }
    final s = v.trim();
    if(type==AccountType.teacher) {
      // Employee/staff IDs have no fixed university format — just a sanity bound.
      final ok = RegExp(r'^[A-Za-z0-9-]{4,25}$').hasMatch(s);
      if(!ok) return 'Invalid ID format';
      return null;
    }
    // Accept dashed format (e.g. 221-15-5678) or plain digits (6-20 chars,
    // wide enough to cover both short and long-form university IDs).
    final ok = RegExp(r'^\d{3}-\d{2}-\d{4,6}$').hasMatch(s) ||
               RegExp(r'^\d{6,20}$').hasMatch(s);
    if(!ok) return 'Invalid ID format (e.g. 221-15-5678)';
    return null;
  }
  static String? required(String? v,{String f='Field'}) {
    if(v==null||v.trim().isEmpty) return '\$f is required';
    return null;
  }
  static String? confirmPassword(String? v,String original) {
    if(v==null||v.isEmpty) return 'Confirm password';
    if(v!=original) return 'Passwords do not match';
    return null;
  }
  static String sanitize(String s) =>
    s.trim().replaceAll(RegExp(r'<[^>]*>'),'').replaceAll(RegExp(r'[<>"\'']'),'');
  static bool validFileSize(int bytes,{int maxMB=5}) => bytes<=maxMB*1024*1024;
}
