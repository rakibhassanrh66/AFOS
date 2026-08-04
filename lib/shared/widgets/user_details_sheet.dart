import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../config/theme/app_colors.dart';
import '../../config/theme/app_text_styles.dart';
import '../../core/utils/role_labels.dart';
import 'glass_sheet.dart';

/// Tap-to-reveal identity card shown from a chat bubble's sender name/avatar
/// -- the bubble itself keeps its anonymized display string (see
/// `chat_naming.dart`), but this reveals the real full name plus enough
/// context (role, department, batch/section or designation, and whether the
/// account is verified by the authority) for the other party to trust the
/// person on the other end is real. [profile] is a raw Supabase row from a
/// `profiles(...)` embed; [designation] is an optional extra label (e.g. a
/// club officer's `club_members.role`) not carried on the profile row itself.
///
/// [extraRows] appends caller-specific detail below the standard fields, in
/// order. It exists so the course join-request card can show a teacher the
/// email and semester it needs to vet a requester, WITHOUT those becoming
/// visible everywhere this sheet is used — the chat caller deliberately
/// reveals only enough to prove the person is real, and quietly widening that
/// for every screen would be a privacy change, not a UI tweak.
void showUserDetailsSheet(
  BuildContext context,
  Map<String, dynamic> profile, {
  String? designation,
  Map<String, String>? extraRows,
}) {
  showGlassSheet(context,
      child: UserDetailsSheet(
          profile: profile, designation: designation, extraRows: extraRows));
}

class UserDetailsSheet extends StatelessWidget {
  final Map<String, dynamic> profile;
  final String? designation;
  final Map<String, String>? extraRows;
  const UserDetailsSheet({
    super.key,
    required this.profile,
    this.designation,
    this.extraRows,
  });

  /// Delegates to the shared [roleLabel] so this sheet and the admin screens
  /// can't drift apart on what a role is called.
  static String _roleLabel(String role) => roleLabel(role);

  @override
  Widget build(BuildContext context) {
    final fullName = (profile['full_name'] as String?)?.trim();
    final avatarUrl = profile['avatar_url'] as String?;
    final role = profile['role'] as String? ?? 'student';
    final dept = profile['department'] as String?;
    final isVerified = profile['is_verified'] as bool? ?? false;

    final rawStudents = profile['students'];
    Map<String, dynamic>? student;
    if (rawStudents is List && rawStudents.isNotEmpty) {
      student = rawStudents.first as Map<String, dynamic>?;
    } else if (rawStudents is Map<String, dynamic>) {
      student = rawStudents;
    }
    // `students` is the registry row; `profiles` carries the student's own
    // self-declared batch/section. The two are known to drift, and not every
    // caller embeds `students` at all (the course join-request card passes a
    // bare profiles row), so fall back rather than silently showing nothing.
    final batch = (student?['batch_label'] as String?)?.trim().isNotEmpty == true
        ? student!['batch_label'] as String?
        : profile['batch'] as String?;
    final section = (student?['section'] as String?)?.trim().isNotEmpty == true
        ? student!['section'] as String?
        : profile['section'] as String?;
    final universityId = profile['university_id'] as String?;

    String? profDesignation = designation;
    if (profDesignation == null) {
      final rawTeachers = profile['teachers'];
      final teacherRow = (rawTeachers is List ? rawTeachers.firstOrNull : rawTeachers) as Map<String, dynamic>?;
      final rawStaff = profile['staff'];
      final staffRow = (rawStaff is List ? rawStaff.firstOrNull : rawStaff) as Map<String, dynamic>?;
      profDesignation = teacherRow?['designation'] as String? ?? staffRow?['designation'] as String?;
    }

    final textPrimary = AppColors.textPrimaryOf(context);

    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Column(children: [
            CircleAvatar(
              radius: 36,
              backgroundColor: AppColors.blue.withValues(alpha: 0.15),
              backgroundImage: avatarUrl != null ? CachedNetworkImageProvider(avatarUrl) : null,
              child: avatarUrl == null
                  ? Text((fullName?.isNotEmpty == true ? fullName![0] : '?').toUpperCase(),
                      style: const TextStyle(color: AppColors.blue, fontSize: 26, fontWeight: FontWeight.w800))
                  : null,
            ),
            const SizedBox(height: 12),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(child: Text(fullName?.isNotEmpty == true ? fullName! : 'Unknown',
                  style: AppTextStyles.headlineMed.copyWith(color: textPrimary), overflow: TextOverflow.ellipsis)),
              if (isVerified)
                const Padding(padding: EdgeInsets.only(left: 6),
                    child: Icon(Icons.verified_rounded, color: AppColors.blue, size: 20)),
            ]),
          ])),
          const SizedBox(height: 20),
          _DetailRow(label: 'Role', value: _roleLabel(role)),
          if (universityId != null && universityId.isNotEmpty)
            _DetailRow(label: 'Student ID', value: universityId),
          if (dept != null && dept.isNotEmpty) _DetailRow(label: 'Department', value: dept),
          if (profDesignation != null && profDesignation.isNotEmpty)
            _DetailRow(label: 'Designation', value: profDesignation),
          if (batch != null && batch.isNotEmpty) _DetailRow(label: 'Batch', value: batch),
          if (section != null && section.isNotEmpty) _DetailRow(label: 'Section', value: section),
          _DetailRow(
            label: 'Account status',
            value: isVerified ? 'Verified by authority' : 'Pending verification',
            valueColor: isVerified ? AppColors.green : AppColors.amber,
          ),
          if (extraRows != null)
            for (final e in extraRows!.entries)
              if (e.value.trim().isNotEmpty) _DetailRow(label: e.key, value: e.value),
        ]);
  }
}

class _DetailRow extends StatelessWidget {
  final String label, value;
  final Color? valueColor;
  const _DetailRow({required this.label, required this.value, this.valueColor});

  /// Label left, value hard against the right edge — every row on the same
  /// column, whatever the width.
  ///
  /// This was `[Text(label), Spacer(), Flexible(value)]`, and `Spacer` is an
  /// `Expanded` with flex 1 while `Flexible` also defaults to flex 1. So the
  /// free space was split 50/50 and `TextAlign.end` aligned each value against
  /// the right edge of ITS OWN HALF rather than the row's — putting every
  /// value's right edge in a different place, in proportion to how long it was.
  /// In a narrow bottom sheet that reads as slightly untidy; on the full-screen
  /// Review Request page it reads as scrambled, which is what it was reported
  /// as.
  ///
  /// `Expanded` on the value (tight, so it fills) is what actually makes
  /// `TextAlign.end` mean the right edge. The label is `Flexible` so a long one
  /// wraps instead of starving the value at a large text scale.
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Flexible(
        flex: 4,
        child: Text(label,
            style: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.textSecondaryOf(context))),
      ),
      const SizedBox(width: 16),
      Expanded(
        flex: 6,
        child: Text(value,
            textAlign: TextAlign.end,
            style: AppTextStyles.titleMedium
                .copyWith(color: valueColor ?? AppColors.textPrimaryOf(context))),
      ),
    ]),
  );
}
