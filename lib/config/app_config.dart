class AppConfig {
  AppConfig._();
  static const String appName       = 'AFOS';
  static const String appFullName   = 'All Facilities One System';
  static const String university    = 'Daffodil International University';
  // Set from PackageInfo during bootstrap so it can never drift from
  // pubspec.yaml again (the old '1.0.0' const was stale for months).
  // The literal here is only the pre-bootstrap fallback.
  static String appVersion          = '1.1.1';
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
  // Mirrors the auth_email_domain_allowlist DB table — bootstrap accounts
  // that bypass the @diu.edu.bd-only email restriction. This is the
  // client-side form-message gate; enforce_email_domain (restored in
  // 20260712135746_restore_diu_email_restriction.sql, keeping this exact
  // list in sync with the DB table) is the authoritative server-side
  // enforcement.
  static const List<String> emailDomainAllowlist = [
    'rakibhassan.rh68@gmail.com',
    // Persistent QA accounts for integration_test/overflow_smoke_test.dart
    // (see the plan file for the full rationale).
    'qa_student@afos.test',
    'qa_teacher@afos.test',
    'qa_staff@afos.test',
    'rakibhassan.rh68+qaadmin@gmail.com',
    'rakibhassan.rh68+qasuperadmin@gmail.com',
  ];
}
