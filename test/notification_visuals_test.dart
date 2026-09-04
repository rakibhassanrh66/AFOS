import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:afos_v7/config/theme/app_icons.dart';
import 'package:afos_v7/features/notifications/presentation/notification_visuals.dart';

/// The category-to-icon map was written from imagination and never checked
/// against the table it describes.
///
/// Counting `user_notifications` by category found the map covering names
/// nothing has ever emitted — `payment`, `library`, `message`,
/// `course_message` are all zero rows — while missing the ones that dominate
/// it. `app_update` alone was 225 rows, and `routine` (43), `general` (38),
/// `sos` (8) and `feedback` (2) made up most of the remainder. Roughly three
/// in five notifications in the app drew the anonymous bell.
///
/// Three categories are also stored upper-cased (`ANNOUNCEMENT`, `GENERAL`,
/// `RULE`) and the lookup was a case-sensitive `switch`, so those could not
/// have matched even if they had been listed.
void main() {
  // Every category actually present in user_notifications, with the counts at
  // the time of writing. Update this list when a new trigger adds one — that
  // is the point of it.
  const liveCategories = <String>[
    'app_update', 'routine', 'general', 'transport', 'course_offering',
    'club', 'hall', 'lost_found', 'ANNOUNCEMENT', 'GENERAL', 'sos',
    'mentorship', 'exam', 'feedback', 'RULE',
    // Added by 20260904085938_notify_on_request_decisions.
    'cr',
  ];

  test('every category in the database has its own icon, not the fallback', () {
    final fallback = NotificationVisuals.iconOf('a-category-that-cannot-exist');
    final generic = <String>[];

    for (final c in liveCategories) {
      // app_update legitimately uses the bell — it IS the notification icon,
      // and 225 update banners marked with something else would be worse.
      if (c == 'app_update') continue;
      if (NotificationVisuals.iconOf(c) == fallback) generic.add(c);
    }

    expect(generic, isEmpty,
        reason: 'these categories exist in user_notifications but still draw '
            'the generic bell: ${generic.join(', ')}');
  });

  test('lookup is case-insensitive, because the data is not consistently cased', () {
    expect(NotificationVisuals.iconOf('GENERAL'),
        NotificationVisuals.iconOf('general'));
    expect(NotificationVisuals.colorOf('ANNOUNCEMENT'),
        NotificationVisuals.colorOf('announcement'));
    expect(NotificationVisuals.iconOf('RULE'), NotificationVisuals.iconOf('rule'));
  });

  test('an unknown or null category degrades to the bell rather than throwing', () {
    // Categories are free text written by database triggers. A new trigger
    // must never be able to crash the tray.
    expect(NotificationVisuals.iconOf(null), AppIcons.notifications);
    expect(NotificationVisuals.iconOf(''), AppIcons.notifications);
    expect(NotificationVisuals.colorOf('something_new_next_year'), isA<Color>());
  });
}
