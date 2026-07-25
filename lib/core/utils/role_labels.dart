/// Human-facing names for `profiles.role` values.
///
/// The stored values stay machine-readable ('staff', 'dept_admin', …) because
/// the role CHECK constraint and 30+ RLS policies test them literally — this
/// is presentation only.
///
/// Centralised because the same mapping was previously open-coded in
/// user_details_sheet and sos_alert_detail_screen while three other places
/// rendered the raw value or a generic title-case of it, so 'staff' showed as
/// "Staff" (or plain lowercase "staff") in the admin screens no matter what
/// the sheets said. Officers sign up under the staff role, which is why the
/// label reads "Staff/Officer".
String roleLabel(String? role) => switch (role) {
      'student' => 'Student',
      'teacher' => 'Teacher',
      'staff' => 'Staff/Officer',
      'admin' => 'Admin',
      'dept_admin' => 'Dept Admin',
      'super_admin' => 'Super Admin',
      'exam_controller' => 'Exam Controller',
      null => 'Unknown',
      // Anything new in the CHECK constraint that predates a label here:
      // de-snake it rather than showing a raw identifier.
      _ => role
          .split('_')
          .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
          .join(' '),
    };
