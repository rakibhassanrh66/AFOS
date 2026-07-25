import '../../config/app_config.dart';

enum AccountType { student, teacher, staff }

class AppValidators {
  AppValidators._();
  // Shape-only check, shared by both validators. Allows '+' aliasing in the
  // local part (RFC-valid, common for Gmail) — Supabase Auth accepts these.
  static final RegExp _emailShape = RegExp(r'^[\w\-\.\+]+@([\w-]+\.)+[\w-]{2,10}$');

  /// For sign-in / forgot-password: an existing account may legitimately be
  /// outside the registration domain rule (allowlisted bootstrap accounts,
  /// admin-created accounts), so only the shape is checked here.
  static String? loginEmail(String? v) {
    if(v==null||v.trim().isEmpty) return 'Email required';
    if(!_emailShape.hasMatch(v.trim())) return 'Invalid email';
    return null;
  }

  static String? email(String? v) {
    if(v==null||v.trim().isEmpty) return 'Email required';
    final e = v.trim();
    if(!_emailShape.hasMatch(e)) return 'Invalid email';
    final isAllowlisted = AppConfig.emailDomainAllowlist.contains(e.toLowerCase());
    // 'edu.bd' with no leading dot matched anything ending in that literal
    // string ("fake-edu.bd", another university's "buet.edu.bd") -- not
    // just DIU. This is also just the form-message gate now; the real
    // boundary is the enforce_email_domain DB trigger (restored in
    // 20260712135746_restore_diu_email_restriction.sql), which enforces
    // the same '@diu.edu.bd' + allowlist rule server-side.
    if(!e.toLowerCase().endsWith('@diu.edu.bd') && !isAllowlisted) {
      return 'Only DIU (@diu.edu.bd) email addresses can register';
    }
    return null;
  }
  /// For sign-in only: the complexity rules below are a registration policy;
  /// enforcing them at login can lock out accounts whose password was set
  /// through another channel. The server is the real credential check.
  static String? loginPassword(String? v) {
    if(v==null||v.isEmpty) return 'Password required';
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
    if(type==AccountType.teacher || type==AccountType.staff) {
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
    // Escaped '\$f' printed the literal text "$f is required" to every
    // user who left any required field blank across the whole app (Batch,
    // Section, Designation, Full name, Phone, etc. all use this) instead of
    // the actual field name -- meaningless to anyone who isn't reading the
    // source.
    if(v==null||v.trim().isEmpty) return '$f is required';
    return null;
  }
  // ── Curriculum identity fields ──────────────────────────────────────
  // These mirror the DB CHECK constraints added in
  // sec_input_validation_and_normalisation (profiles_teacher_initial_format,
  // students_section_format, students_batch_label_format,
  // course_offerings_*_format, courses_code_format).
  //
  // The database is the real boundary — PostgREST is directly reachable, so a
  // client rule alone is advisory. But without a matching client rule the
  // user's only feedback is a rejected write, and on the signup path a
  // rejected write fails account creation outright rather than just losing
  // the field. Case is not enforced here because the DB normalises to
  // upper-case on write, so 'a' and 'A' are both accepted and both stored 'A'.
  static final RegExp _sectionShape = RegExp(r'^[A-Za-z0-9]{1,4}$');
  static final RegExp _batchShape = RegExp(r'^[A-Za-z0-9-]{1,10}$');
  static final RegExp _initialShape = RegExp(r'^[A-Za-z]{2,6}$');
  static final RegExp _courseCodeShape = RegExp(r'^[A-Za-z0-9 -]{2,20}$');

  /// [req] is false where the field is genuinely optional (Settings, where a
  /// student may clear it), true on the onboarding forms that demand it.
  static String? section(String? v, {bool req = true}) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return req ? 'Section is required' : null;
    if (!_sectionShape.hasMatch(s)) return 'Use 1-4 letters or digits (e.g. A, B2)';
    return null;
  }

  static String? batch(String? v, {bool req = true}) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return req ? 'Batch is required' : null;
    if (!_batchShape.hasMatch(s)) return 'Use 1-10 letters, digits or "-" (e.g. 66)';
    return null;
  }

  static String? teacherInitial(String? v, {bool req = true}) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return req ? 'Teacher initials are required' : null;
    if (!_initialShape.hasMatch(s)) return 'Use 2-6 letters, no digits (e.g. AS, FNN)';
    return null;
  }

  static String? courseCode(String? v, {bool req = true}) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return req ? 'Course code is required' : null;
    if (!_courseCodeShape.hasMatch(s)) {
      return 'Use 2-20 letters, digits, spaces or "-" (e.g. CSE 412)';
    }
    return null;
  }

  static String? confirmPassword(String? v,String original) {
    if(v==null||v.isEmpty) return 'Confirm password';
    if(v!=original) return 'Passwords do not match';
    return null;
  }
  /// Strips angle-bracketed tags and stray quote/bracket characters from free
  /// text. Defence in depth for display only — it is NOT an escaping function
  /// and must never be relied on for SQL (PostgREST parameterises) or for
  /// rendering untrusted HTML.
  ///
  /// The second pattern used to be written `RegExp(r'[<>"\'']')`. A raw string
  /// cannot escape its own quote, so Dart read that as the raw string `[<>"\`
  /// adjacent to the string `]` and concatenated them into `[<>"\]` — an
  /// unterminated character class that threw on every call. Triple quotes let
  /// both `"` and `'` sit in one raw string.
  static String sanitize(String s) =>
    s.trim().replaceAll(RegExp(r'<[^>]*>'),'').replaceAll(RegExp(r'''[<>"']'''),'');
  static bool validFileSize(int bytes,{int maxMB=5}) => bytes<=maxMB*1024*1024;
}
