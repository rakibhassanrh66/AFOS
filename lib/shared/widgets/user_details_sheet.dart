import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../config/theme/app_colors.dart';
import '../../config/theme/app_text_styles.dart';

/// Tap-to-reveal identity card shown from a chat bubble's sender name/avatar
/// -- the bubble itself keeps its anonymized display string (see
/// `chat_naming.dart`), but this reveals the real full name plus enough
/// context (role, department, batch/section or designation, and whether the
/// account is verified by the authority) for the other party to trust the
/// person on the other end is real. [profile] is a raw Supabase row from a
/// `profiles(...)` embed; [designation] is an optional extra label (e.g. a
/// club officer's `club_members.role`) not carried on the profile row itself.
void showUserDetailsSheet(BuildContext context, Map<String, dynamic> profile, {String? designation}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surfaceOf(context),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sheetCtx) => UserDetailsSheet(profile: profile, designation: designation),
  );
}

class UserDetailsSheet extends StatelessWidget {
  final Map<String, dynamic> profile;
  final String? designation;
  const UserDetailsSheet({super.key, required this.profile, this.designation});

  static String _roleLabel(String role) => switch (role) {
    'teacher' => 'Teacher',
    'student' => 'Student',
    'staff' => 'Staff',
    'admin' => 'Admin',
    'dept_admin' => 'Dept Admin',
    'super_admin' => 'Super Admin',
    'exam_controller' => 'Exam Controller',
    _ => role,
  };

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
    final batch = student?['batch_label'] as String?;
    final section = student?['section'] as String?;

    String? profDesignation = designation;
    if (profDesignation == null) {
      final rawTeachers = profile['teachers'];
      final teacherRow = (rawTeachers is List ? rawTeachers.firstOrNull : rawTeachers) as Map<String, dynamic>?;
      final rawStaff = profile['staff'];
      final staffRow = (rawStaff is List ? rawStaff.firstOrNull : rawStaff) as Map<String, dynamic>?;
      profDesignation = teacherRow?['designation'] as String? ?? staffRow?['designation'] as String?;
    }

    final textPrimary = AppColors.textPrimaryOf(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
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
        ]),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label, value;
  final Color? valueColor;
  const _DetailRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(children: [
      Text(label, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context))),
      const Spacer(),
      Flexible(
          child: Text(value, textAlign: TextAlign.end,
              style: AppTextStyles.titleMedium.copyWith(color: valueColor ?? AppColors.textPrimaryOf(context)))),
    ]),
  );
}
