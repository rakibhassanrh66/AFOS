extension StringExt on String {
  String get capitalize => isEmpty ? this : '\${this[0].toUpperCase()}\${substring(1)}';
  String get initials {
    final p = trim().split(' ');
    return p.length>=2?'\${p[0][0]}\${p[1][0]}'.toUpperCase():isNotEmpty?this[0].toUpperCase():'?';
  }
  bool   get isValidEmail => RegExp(r'^[\w-.]+@([\w-]+\.)+[\w-]{2,4}\$').hasMatch(this);
  bool   get isValidStudentId => RegExp(r'^\d{3}-\d{2}-\d{4}\$').hasMatch(this);
}
