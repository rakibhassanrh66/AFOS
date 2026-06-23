class AppValidators {
  AppValidators._();
  static String? email(String? v) {
    if(v==null||v.trim().isEmpty) return 'Email required';
    if(!RegExp(r'^[\w-.]+@([\w-]+\.)+[\w-]{2,4}\$').hasMatch(v.trim())) return 'Invalid email';
    return null;
  }
  static String? password(String? v) {
    if(v==null||v.isEmpty) return 'Password required';
    if(v.length<8) return 'Minimum 8 characters';
    if(!v.contains(RegExp(r'[A-Z]'))) return 'Need one uppercase letter';
    if(!v.contains(RegExp(r'[0-9]'))) return 'Need one number';
    return null;
  }
  static String? studentId(String? v) {
    if(v==null||v.trim().isEmpty) return 'Student ID required';
    if(!RegExp(r'^\d{3}-\d{2}-\d{4}\$').hasMatch(v.trim())) return 'Format: XXX-XX-XXXX';
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
