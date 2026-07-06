import 'package:flutter/material.dart';

/// Centralized icon registry, mirroring [AppColors]'s static-const shape.
/// [moduleIcons] is keyed by the same module-name strings as
/// `AppColors.moduleColors`, since nav/dashboard call sites already pair
/// a module key with both a color and an icon.
class AppIcons {
  AppIcons._();

  // --- Modules (matches AppColors.moduleColors keys) ---
  static const IconData schedule   = Icons.calendar_today_rounded;
  static const IconData hall       = Icons.apartment_rounded;
  static const IconData transport  = Icons.directions_bus_rounded;
  static const IconData payment    = Icons.payment_rounded;
  static const IconData library    = Icons.menu_book_rounded;
  static const IconData lostFound  = Icons.search_rounded;
  static const IconData clubs      = Icons.groups_rounded;
  static const IconData mentorship = Icons.school_rounded;
  static const IconData examSeat   = Icons.event_seat_rounded;
  static const IconData deptChat   = Icons.chat_rounded;
  static const IconData vrId       = Icons.qr_code_rounded;
  static const IconData notices    = Icons.campaign_rounded;

  static const Map<String, IconData> moduleIcons = {
    'schedule': schedule, 'hall': hall, 'transport': transport,
    'payment': payment, 'library': library, 'lost_found': lostFound,
    'clubs': clubs, 'mentorship': mentorship, 'exam_seat': examSeat,
    'dept_chat': deptChat, 'vr_id': vrId, 'notices': notices,
  };

  // --- Other nav / dashboard entries ---
  static const IconData dashboard        = Icons.home_rounded;
  static const IconData results          = Icons.assignment_turned_in_rounded;
  static const IconData assignments      = Icons.assignment_outlined;
  static const IconData notifications    = Icons.notifications_rounded;
  static const IconData settings         = Icons.settings_rounded;
  static const IconData conferenceRoom   = Icons.meeting_room_rounded;

  // --- Admin / oversight tooling ---
  static const IconData uploadRoutine    = Icons.upload_file_rounded;
  static const IconData moderateChat     = Icons.shield_rounded;
  static const IconData faculties        = Icons.account_balance_rounded;
  static const IconData manageUsers      = Icons.manage_accounts_rounded;
  static const IconData manageClubs      = Icons.workspace_premium_rounded;

  // --- Common actions, repeated 3+ times across the app ---
  static const IconData close            = Icons.close;
  static const IconData edit             = Icons.edit_outlined;
  static const IconData delete           = Icons.delete_outline;
  static const IconData deleteRounded    = Icons.delete_outline_rounded;
  static const IconData logout           = Icons.logout_rounded;
  static const IconData chevronRight     = Icons.chevron_right_rounded;
  static const IconData errorOutline     = Icons.error_outline_rounded;
  static const IconData infoOutline      = Icons.info_outline_rounded;
  static const IconData badge            = Icons.badge_outlined;
  static const IconData accessTime       = Icons.access_time;
  static const IconData personOutline    = Icons.person_outline;
  static const IconData peopleOutline    = Icons.people_outline;
  static const IconData chatBubbleOutline = Icons.chat_bubble_outline_rounded;
  static const IconData emailOutline     = Icons.email_outlined;
  static const IconData lockOutline      = Icons.lock_outline;
  static const IconData schoolOutline    = Icons.school_outlined;
}
