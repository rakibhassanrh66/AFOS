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

  /// DIU student-portal pages surfaced inside AFOS.
  ///
  /// These are opened in an in-app browser ([DiuPortalScreen]) rather than
  /// scraped and re-rendered natively. That is a forced choice, not a
  /// preference: the portal sits behind a **Cloudflare bot challenge** —
  /// every path returns HTTP 403 with `Cf-Mitigated: challenge` to any
  /// non-browser client, including with a real browser User-Agent, because
  /// clearance requires executing the challenge JavaScript. A server-side
  /// scraper (edge function) therefore cannot read these pages at all, and
  /// defeating that challenge is not something this app should do — it is an
  /// access control the university put there deliberately.
  ///
  /// A WebView satisfies the challenge the legitimate way (it is a real
  /// browser engine) and the student signs in with their own credentials.
  static const String diuPortalBase = 'https://studentportal.diu.edu.bd';
  static const String diuPortalDashboard   = '$diuPortalBase/dashboard';
  static const String diuPortalLedger      = '$diuPortalBase/payment-ledger';
  static const String diuPortalScholarship = '$diuPortalBase/scholarship-circular';
  static const String diuPortalWaiver      = '$diuPortalBase/waiver';
  static const String diuPortalCareer      = '$diuPortalBase/career-development-center';
  static const String diuPortalNoticeBoard = '$diuPortalBase/notice-board';
  static const String diuPortalFacilities  = '$diuPortalBase/facilities';
  static const String diuTransportCardApply= '$diuPortalBase/transport-card-apply';
  static const String diuHallLogin         = 'https://hall.diu.edu.bd/web/login';

  /// Hosts the in-app portal browser may navigate to.
  ///
  /// Deliberately the whole DIU family rather than one exact host: signing in
  /// bounces through Cloudflare's challenge and DIU's own login/SSO hosts, and
  /// the old payment WebView allowlisted only `studentportal.diu.edu.bd`. Any
  /// such redirect was answered with `NavigationDecision.prevent`, which — with
  /// both error callbacks empty — rendered as a silent blank page. That is the
  /// reported "even after signing in it shows blank".
  static const List<String> diuTrustedHostSuffixes = [
    'diu.edu.bd',
    'daffodilvarsity.edu.bd',
  ];
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
