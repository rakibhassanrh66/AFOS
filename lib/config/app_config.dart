class AppConfig {
  AppConfig._();
  static const String appName       = 'AFOS';
  static const String appFullName   = 'All Facilities One System';
  static const String university    = 'Daffodil International University';
  static const String appVersion    = '1.0.0';
  static const String oneSignalAppId= '2ae8d7b3-8999-4054-b185-2256b290993c';
  static const String diuPaymentUrl = 'https://studentportal.diu.edu.bd/payment';
  static const String diuLibraryUrl = 'https://library.daffodilvarsity.edu.bd';
  static const double libraryFinePerDay = 5.0;
  // Fallback only — registration now sources departments from the DB
  // (`departments` table) so this list is used solely if that query fails.
  static const List<String> departments = [
    'CSE','EEE','BBA','English','Law','Architecture',
    'Pharmacy','Textile','Civil','ICE','MCJ','Mathematics',
  ];
  // Mirrors supabase/migrations/20260702_auth_registration_overhaul.sql's
  // auth_email_domain_allowlist table — bootstrap accounts that bypass the
  // edu.bd-only email restriction. Client-side check only; the DB trigger
  // is the authoritative enforcement.
  static const List<String> emailDomainAllowlist = [
    'rakibhassan.rh68@gmail.com',
    // Persistent QA accounts for integration_test/overflow_smoke_test.dart
    // (see the plan file for the full rationale) — this is a client-side
    // form-message gate only (the DB-level enforce_email_domain trigger was
    // already dropped in 20260703030000_remove_email_domain_restriction.sql),
    // not a real security boundary, so adding test accounts here carries no
    // more risk than the existing super_admin entry above.
    'qa_student@afos.test',
    'qa_teacher@afos.test',
    'qa_staff@afos.test',
    'rakibhassan.rh68+qaadmin@gmail.com',
    'rakibhassan.rh68+qasuperadmin@gmail.com',
  ];
}
