import 'package:flutter/material.dart';

import 'package:afos_v7/config/theme/app_colors.dart';
import 'package:afos_v7/shared/widgets/afos_text_field.dart';
import 'package:afos_v7/shared/widgets/glass_tab_bar.dart';

import 'package:afos_v7/shared/widgets/surface_card.dart';
import 'package:afos_v7/features/web/presentation/widgets/console_grid.dart';

import 'support/layout_probe.dart';

/// Shared widgets the existing sweeps never covered, driven through the same
/// size x text-scale probe as everything else.
///
/// The reason this file exists: `shared_widgets_layout_test` probes ten
/// widgets, and the ones it does NOT probe are where this session's changes
/// landed. In particular GlassTabBar, whose own doc says icons stack over
/// labels "to stay readable at 3-4 tabs" — and Manage Users now shows FIVE,
/// because the Photos and Code Failed queues were changed to render even when
/// empty so an admin could find them. Adding a tab without re-checking the bar
/// at 320dp and a 2.0x text scale is exactly how a control ends up unreadable
/// for the people who need it most.
///
/// Real widgets only. A copy in a test cannot regress.
void main() {
  runLayoutSweep('ui sweep', {
    // The exact five tabs Manage Users renders for a super_admin now, counts
    // and all. This is the configuration this session created.
    'GlassTabBar (5 tabs, the real Manage Users set)': () => GlassTabBar(
          currentIndex: 0,
          onChanged: (_) {},
          tabs: const [
            GlassTab('Pending (12)', icon: Icons.how_to_reg_rounded),
            GlassTab('Code Failed (3)', icon: Icons.mark_email_unread_rounded),
            GlassTab('Photos (7)', icon: Icons.photo_camera_outlined),
            GlassTab('CR Requests (4)', icon: Icons.badge_rounded),
            GlassTab('Users', icon: Icons.groups_2_outlined),
          ],
        ),

    // The two- and four-tab cases it was designed for, as the control.
    'GlassTabBar (4 tabs)': () => GlassTabBar(
          currentIndex: 1,
          onChanged: (_) {},
          tabs: const [
            GlassTab('Pending (12)', icon: Icons.how_to_reg_rounded),
            GlassTab('Photos (7)', icon: Icons.photo_camera_outlined),
            GlassTab('CR Requests (4)', icon: Icons.badge_rounded),
            GlassTab('Users', icon: Icons.groups_2_outlined),
          ],
        ),

    // SurfaceCard carries this session's Profile Inspection banner: icon,
    // two stacked lines of text, a count chip and a chevron on one row.
    'SurfaceCard (icon + two lines + chip + chevron)': () => SurfaceCard(
          accent: AppColors.amber,
          onTap: () {},
          child: Row(children: [
            const Icon(Icons.fact_check_rounded, color: AppColors.amber, size: 22),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Profile Inspection'),
                Text('13 verified accounts still owe required details'),
              ]),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsetsDirectional.fromSTEB(8, 2, 8, 2),
              color: AppColors.amber.withValues(alpha: 0.14),
              child: const Text('13'),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, size: 20),
          ]),
        ),

    'AfosTextField (long hint)': () => AfosTextField(
          hint: 'Where was it lost or found? Be as specific as you can',
          controller: TextEditingController(),
        ),

    'AfosTextField (long value + error)': () => AfosTextField(
          hint: 'Emergency contact',
          controller: TextEditingController(
              text: 'Someone With A Rather Long Name 01700000001'),
          validator: (_) => 'This must differ from your own number',
        ),

    // OfflineBanner is deliberately NOT probed here. It reads the offline
    // cache on build and throws "HiveError: Box not found" without an opened
    // box, which is a harness limitation rather than a layout fault — probing
    // it would report a failure that says nothing about how it lays out.
    // Left out rather than papered over with a fake pass.

    // The web console figure this session added a ninth of. Its label is a
    // Semantics label, so the NOTE is what a sighted person reads and the
    // note is the part that has to fit.
    'GridFigure (web console figure)': () => const SizedBox(
          height: 78,
          child: GridFigure(
            label: 'Incomplete profiles',
            value: '13',
            note: 'missing required details',
            icon: Icons.fact_check_rounded,
            accent: AppColors.amber,
          ),
        ),
  });
}
