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

  /// Lower-cased, because the categories in the table are not consistently
  /// cased and the old switches were. `ANNOUNCEMENT`, `GENERAL` and `RULE` are
  /// all really in `user_notifications`, and every one of them missed its case
  /// in a case-sensitive `switch` and fell through to the generic bell.
  static String? _key(String? category) => category?.trim().toLowerCase();

  static IconData iconOf(String? category) => switch (_key(category)) {
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
        // Real categories that had no mark: 13 hall decisions and 6
        // mentorship verdicts in the table, both drawing the generic bell.
        // (A class-representative verdict is sent under 'general', not 'cr' --
        // see manage_users_screen.dart:466.)
        'hall' => AppIcons.hall,
        'mentorship' => AppIcons.mentorship,
        // MEASURED AGAINST THE TABLE, NOT GUESSED. Counting
        // `user_notifications` by category showed the map covered names
        // nothing emits (`payment`, `library`, `message`, `course_message`)
        // while missing the ones that dominate it: `app_update` alone is 225
        // of the rows, and `routine`, `general`, `sos` and `feedback` together
        // are most of the rest. Roughly three in five notifications in the app
        // were drawing the anonymous bell.
        'app_update' => AppIcons.notifications,
        'routine' => AppIcons.schedule,
        'sos' => Icons.emergency_share_rounded,
        'feedback' => Icons.rate_review_outlined,
        'announcement' => Icons.campaign_rounded,
        'rule' => Icons.gavel_rounded,
        'general' => Icons.info_outline_rounded,
        _ => AppIcons.notifications,
      };

  static Color colorOf(String? category) => switch (_key(category)) {
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
        'app_update' => AppColors.blue,
        'routine' => AppColors.red,
        'sos' => AppColors.red,
        'feedback' => AppColors.teal,
        'announcement' => AppColors.amber,
        'rule' => AppColors.purple,
        'general' => AppColors.blue,
        _ => AppColors.blue,
      };
}
