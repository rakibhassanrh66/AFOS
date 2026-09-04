import 'package:flutter/material.dart';

import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_icons.dart';

/// The icon and colour for a notification's `category`, in ONE place.
///
/// WHY THIS FILE EXISTS. The popover and the full Notification Center each
/// carried their own private `_catIcon`/`_catColor` switch, and the popover's
/// copy said "Kept in sync with NotificationCenterScreen's category visuals"
/// — which it was not. The center had learned `course_offering`,
/// `course_message` and `assignment`; the popover had not, so the same
/// notification showed a course icon in one surface and a generic bell six
/// pixels away in the other. A comment is not a mechanism.
///
/// Anything not listed falls back to the generic bell rather than throwing:
/// categories are free text written by database triggers, and a new trigger
/// must never be able to crash the tray. Adding a case here is what makes a
/// new category look deliberate in both surfaces at once.
class NotificationVisuals {
  NotificationVisuals._();

  static IconData iconOf(String? category) => switch (category) {
        'schedule' => AppIcons.schedule,
        'transport' => AppIcons.transport,
        'payment' => AppIcons.payment,
        'library' => AppIcons.library,
        'lost_found' => AppIcons.lostFound,
        'club' => AppIcons.clubs,
        'message' => AppIcons.deptChat,
        'exam' => AppIcons.examSeat,
        'course_offering' => AppIcons.schedule,
        'course_message' => AppIcons.deptChat,
        'assignment' => AppIcons.assignments,
        // Added with the request-decision triggers
        // (20260904085938_notify_on_request_decisions.sql): a hall seat, a
        // mentorship session and a class-representative verdict each reach a
        // student who has been waiting on an answer, so they get their own
        // mark rather than the anonymous bell.
        'hall' => AppIcons.hall,
        'mentorship' => AppIcons.mentorship,
        'cr' => AppIcons.badge,
        _ => AppIcons.notifications,
      };

  static Color colorOf(String? category) => switch (category) {
        'schedule' => AppColors.red,
        'transport' => AppColors.amber,
        'payment' => AppColors.gold,
        'library' => AppColors.indigo,
        'lost_found' => AppColors.coral,
        'club' => AppColors.pink,
        'message' => AppColors.blue,
        'exam' => AppColors.orange,
        'course_offering' => AppColors.green,
        'course_message' => AppColors.blue,
        'assignment' => AppColors.purple,
        'hall' => AppColors.teal,
        'mentorship' => AppColors.green,
        'cr' => AppColors.purple,
        _ => AppColors.blue,
      };
}
