import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../config/supabase_config.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../config/theme/app_text_styles.dart';
import '../../../../config/theme/depth.dart';
import '../../../../config/theme/spacing.dart';
import '../../../../core/auth/capabilities.dart';
import '../widgets/web_layout.dart';

/// One thing a person is responsible for, and how much of it is waiting.
///
/// THE POINT OF THE WHOLE REDESIGN, in one class. The mobile dashboard shows a
/// grid of twelve app icons and calls it a home screen. That is a launcher: it
/// tells you what exists, never what needs doing. On a phone that is arguably
/// fine — you opened the app for a reason. On a desktop, where someone sits
/// down to work for an hour, "here are some icons" is a wasted screen.
///
/// A work queue says: this is your area, this many items are waiting, here is
/// the door. A person with four granted areas sees four numbers and knows
/// where their afternoon goes before they have clicked anything.
class WorkQueue {
  final AppCapability cap;

  /// How many items are waiting. Null while loading, or when this area has no
  /// meaningful count — some areas are tools rather than queues, and inventing
  /// a number for them would be worse than showing none.
  final int? pending;

  /// What the number means. Never bare: "7" is not information, "7 waiting for
  /// approval" is.
  final String? unit;

  const WorkQueue({required this.cap, this.pending, this.unit});
}

/// Counts the queue behind each granted area.
///
/// EVERY COUNT IS A HEAD REQUEST. `.count()` (postgrest 2.7.2) issues a HEAD
/// and returns the integer without transferring rows — the same fix that was
/// applied to the mobile dashboard after nine of its queries were found
/// downloading whole ID lists just to call `.length` on them. A console that
/// opens with eight counts must not download eight tables.
///
/// EVERY COUNT IS ALSO ALLOWED TO FAIL. RLS decides what a caller may read,
/// and a caller who cannot read a table gets an error or a zero, not a crash.
/// A failed count renders as "—" rather than as "0", because those are
/// different claims and only one of them is honest.
Future<List<WorkQueue>> loadWorkQueues(Set<String> grants) async {
  final caps = delegatedCapabilities(grants);
  if (caps.isEmpty) return const [];

  Future<WorkQueue> countFor(AppCapability c) async {
    Future<int>? q;
    String? unit;

    switch (c.route) {
      case '/admin/hall':
        q = SupabaseConfig.client
            .from('hall_applications').count().eq('status', 'pending');
        unit = 'applications waiting';
      case '/admin/users':
        // Two different jobs land here. CR requests are the one with a queue
        // that a delegate is likely to hold; signup approvals are counted by
        // the admin console instead.
        q = SupabaseConfig.client
            .from('cr_requests').count().eq('status', 'pending');
        unit = 'CR requests waiting';
      case '/admin/course-offerings':
        q = SupabaseConfig.client.from('course_offerings')
            .count().eq('status', 'pending').eq('is_archived', false);
        unit = 'offerings to review';
      case '/admin/sos':
        q = SupabaseConfig.client
            .from('sos_alerts').count().eq('status', 'active');
        unit = 'alerts active';
      case '/admin/feedback':
        q = SupabaseConfig.client.from('feedback').count().eq('status', 'new');
        unit = 'reports unread';
      case '/conference-room':
        q = SupabaseConfig.client
            .from('conference_room_requests').count().eq('status', 'pending');
        unit = 'bookings to decide';
      default:
        // Upload, notices, library, exam seats, the activity log: tools, not
        // queues. Showing "0 waiting" against a PDF importer would be a number
        // invented to fill a slot.
        return WorkQueue(cap: c);
    }

    try {
      return WorkQueue(cap: c, pending: await q, unit: unit);
    } catch (_) {
      return WorkQueue(cap: c, unit: unit);
    }
  }

  return Future.wait(caps.map(countFor));
}

/// A granted area, rendered as work rather than as an app icon.
class WorkQueueCard extends StatelessWidget {
  final WorkQueue queue;
  const WorkQueueCard({super.key, required this.queue});

  @override
  Widget build(BuildContext context) {
    final c = queue.cap;
    final n = queue.pending;
    final hasWork = n != null && n > 0;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => context.go(c.route),
        child: WebPanel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  color: c.accent.withValues(alpha: 0.12),
                  borderRadius: AppDepth.radius(1),
                ),
                child: Icon(c.icon, size: 18, color: c.accent),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text(c.label,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.titleMedium.copyWith(
                        color: AppColors.textPrimaryOf(context),
                        fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: AppSpace.md),
            if (queue.unit == null)
              Text(c.hint ?? 'Open',
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textSecondaryOf(context)))
            else
              Row(crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                Text(
                  // "—" not "0": a count that failed and a count that is zero
                  // are different claims, and only one of them is honest.
                  n == null ? '—' : '$n',
                  style: AppTextStyles.displayMedium.copyWith(
                    color: hasWork
                        ? c.accent
                        : AppColors.textSecondaryOf(context),
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text(queue.unit!,
                      style: AppTextStyles.labelSmall
                          .copyWith(color: AppColors.textSecondaryOf(context))),
                ),
              ]),
          ]),
        ),
      ),
    );
  }
}

/// Shown to an employee whose account carries no areas at all.
///
/// This is what a staff member actually saw before any of this work: a
/// dashboard of student modules they have no use for, and no indication that
/// their account was simply never given a job. `staff` is the one role whose
/// menu is built entirely from grants, so with none it is correctly empty —
/// and an empty screen with no explanation reads as a broken app rather than
/// as an unfinished setup step.
class NoAreasPanel extends StatelessWidget {
  const NoAreasPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return WebPanel(
      padding: const EdgeInsets.all(AppSpace.xl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.badge_outlined, size: 22, color: AppColors.amber),
          const SizedBox(width: AppSpace.sm),
          Text('No work areas assigned yet',
              style: AppTextStyles.titleMedium.copyWith(
                  color: AppColors.textPrimaryOf(context),
                  fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: AppSpace.sm),
        Text(
          'Your account is set up, but nobody has given it an area to work in '
          'yet. Routine uploads, hall allocation, notices and the rest are each '
          'granted separately — the role on its own does not carry them.\n\n'
          'Ask a super-admin, or a manager in your department, to open Manage '
          'Users and assign your areas. Anything they grant appears here and in '
          'the sidebar straight away.',
          style: AppTextStyles.bodyMedium
              .copyWith(color: AppColors.textSecondaryOf(context), height: 1.5),
        ),
      ]),
    );
  }
}
