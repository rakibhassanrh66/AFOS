import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/depth.dart';
import '../../../config/theme/motion.dart';
import '../../../config/theme/spacing.dart';
import '../../../core/auth/capabilities.dart';
import '../../../core/auth/permission_session.dart';
import '../../../core/navigation/nav_destinations.dart';
import '../../../core/navigation/router_location.dart';
import '../../../core/services/app_config_service.dart';
import '../../../shared/models/user_model.dart';
import '../../../shared/widgets/logout_tile.dart';
import '../../../shared/widgets/radial_logout_menu.dart';

/// The desktop sidebar.
///
/// WHAT IT REPLACES. `SlideMenu(permanent: true)` in a 248px box: the phone
/// drawer, standing up. It rendered every capability as one flat list, which
/// for a super_admin is twenty-five identical rows with no structure — a list,
/// not navigation. Finding "Manage Exam Seats" meant reading twenty-five
/// labels in order.
///
/// WHAT IT DOES INSTEAD. Groups from the capability model (You / Academics /
/// Campus / Operations / Oversight), each collapsible, with the group holding
/// the current route open on arrival. A super_admin's twenty-five entries
/// become five headings; a student's fifteen become three. Nobody reads a flat
/// list of twenty-five things, and nobody should have to.
///
/// DELEGATED ENTRIES ARE MARKED. A capability that arrived through a grant
/// rather than through the role carries a dot. "You were given this" is a
/// different fact from "this comes with your job" — a delegate who cannot tell
/// them apart cannot tell what they would lose if the grant were revoked.
class WebSidebar extends StatefulWidget {
  const WebSidebar({super.key});

  /// The fixed width app_shell.dart lays this sidebar out at. Named here
  /// (rather than left as a bare literal at each call site) so the header's
  /// own full-bleed-width calculation in top_app_bar.dart can subtract the
  /// same number the shell actually uses, instead of a second, driftable
  /// copy of "264".
  static const double railWidth = 264;

  @override
  State<WebSidebar> createState() => _WebSidebarState();
}

class _WebSidebarState extends State<WebSidebar> {
  UserModel? _user;
  bool _isCr = false;
  Set<String> _grants = const {};

  /// Groups the user has collapsed by hand this session. Absent means open —
  /// a sidebar that starts collapsed hides the app from someone who has just
  /// arrived at it.
  final Set<CapabilityGroup> _collapsed = {};

  @override
  void initState() {
    super.initState();
    _load();
    AppConfigService.instance.ensureInit();
    AppConfigService.instance.sosEnabled.addListener(_onConfig);
  }

  void _onConfig() { if (mounted) setState(() {}); }

  @override
  void dispose() {
    AppConfigService.instance.sosEnabled.removeListener(_onConfig);
    super.dispose();
  }

  Future<void> _load() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) return;
    try {
      final p = await SupabaseConfig.client
          .from('profiles')
          .select('*, teachers(designation), staff(designation, office), students(is_cr)')
          .eq('id', uid).single();
      final isCr = (p['students'] as Map?)?['is_cr'] as bool? ?? false;
      // reload(), not ensureLoaded(): a permission granted since app start has
      // to reach the person it was granted to without them signing out.
      final grants = await PermissionSession.reload();
      if (mounted) {
        setState(() { _user = UserModel.fromJson(p); _isCr = isCr; _grants = grants; });
      }
    } catch (_) {
      // A failed profile load must not blank the navigation. The capability
      // model falls back to the student baseline, which is the least
      // privileged answer rather than the most.
    }
  }

  List<AppCapability> get _caps {
    var caps = capabilitiesFor(role: _user?.role, grants: _grants, isCr: _isCr);
    final sosVisible = _user?.role == 'super_admin' ||
        AppConfigService.instance.sosEnabled.value;
    if (!sosVisible) {
      caps = caps.where((c) => c.route != Caps.nearbySos.route).toList();
    }
    _publish(caps);
    return caps;
  }

  /// Feeds the Ctrl+K palette the same list the sidebar shows, so the palette
  /// can never offer a destination the router refuses.
  void _publish(List<AppCapability> caps) {
    final seen = <String>{};
    final next = <NavDestination>[
      for (final c in caps)
        if (seen.add(c.route)) NavDestination(c.label, c.icon, c.route, c.accent),
    ];
    if (listEquals(navDestinations.value, next)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) navDestinations.value = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final caps = _caps;
    final grouped = groupCapabilities(caps);
    final border = AppColors.borderOf(context);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        border: Border(right: BorderSide(color: border, width: 0.5)),
      ),
      child: Column(children: [
        _Identity(user: _user, isCr: _isCr),
        Divider(height: 1, color: border),
        Expanded(
          child: ListenableBuilder(
            listenable: GoRouter.of(context).routerDelegate,
            builder: (ctx, _) {
              final router = GoRouter.of(ctx);
              return ListView(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
                children: [
                  for (final entry in grouped.entries)
                    _Group(
                      group: entry.key,
                      caps: entry.value,
                      collapsed: _collapsed.contains(entry.key),
                      isActive: (r) => isRouteActive(router, r),
                      onToggle: () => setState(() {
                        if (!_collapsed.remove(entry.key)) _collapsed.add(entry.key);
                      }),
                    ),
                ],
              );
            },
          ),
        ),
        Divider(height: 1, color: border),
        Padding(
          padding: const EdgeInsets.all(AppSpace.sm),
          // Same radial confirm the drawer uses -- logging out is destructive
          // enough on a shared lab machine to deserve a deliberate gesture,
          // and having two different logout flows would be worse than either.
          child: Builder(
            builder: (tileCtx) => LogoutTile(
              label: 'Log out',
              onTap: () async {
                final choice = await showRadialLogoutMenu(tileCtx);
                if (!tileCtx.mounted) return;
                await applyLogoutChoice(tileCtx, choice);
              },
            ),
          ),
        ),
      ]),
    );
  }
}

class _Identity extends StatelessWidget {
  final UserModel? user;
  final bool isCr;
  const _Identity({required this.user, required this.isCr});

  /// What to call this person's position. `semester` is meaningless for
  /// anyone but a student — a teacher/staff/admin row still carries a leftover
  /// default value, so showing it would be showing noise.
  String get _position {
    final role = user?.role;
    if (role == null) return '';
    if (user!.isStudent) return isCr ? 'Class Representative' : 'Sem ${user!.semester}';
    if (user!.isTeacher) return user!.designation ?? 'Faculty';
    if (user!.isStaff) return user!.designation ?? 'Staff / Officer';
    return switch (role) {
      'super_admin' => 'Super Admin',
      'dept_admin' => 'Dept Admin',
      'admin' => 'Admin',
      'exam_controller' => 'Exam Controller',
      _ => role,
    };
  }

  @override
  Widget build(BuildContext context) {
    final name = user?.fullName ?? '';
    return Padding(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Row(children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: AppColors.holoviolet.withValues(alpha: 0.14),
            borderRadius: AppDepth.radius(1),
          ),
          alignment: Alignment.center,
          child: Text(
            name.isEmpty ? '?' : name.characters.first.toUpperCase(),
            style: AppTextStyles.titleMedium.copyWith(
                color: AppColors.holoviolet, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name.isEmpty ? 'Loading' : name,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: AppTextStyles.titleMedium
                    .copyWith(color: AppColors.textPrimaryOf(context))),
            if (_position.isNotEmpty)
              Text(_position,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelSmall
                      .copyWith(color: AppColors.textSecondaryOf(context))),
          ]),
        ),
      ]),
    );
  }
}

class _Group extends StatelessWidget {
  final CapabilityGroup group;
  final List<AppCapability> caps;
  final bool collapsed;
  final bool Function(String route) isActive;
  final VoidCallback onToggle;

  const _Group({
    required this.group,
    required this.caps,
    required this.collapsed,
    required this.isActive,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    // A group containing the current route never collapses out from under the
    // user: losing sight of where you are is worse than a slightly longer list.
    final holdsActive = caps.any((c) => isActive(c.route));
    final open = !collapsed || holdsActive;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: holdsActive ? null : onToggle,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpace.md, AppSpace.md, AppSpace.sm, AppSpace.xs),
            child: Row(children: [
              Expanded(
                child: Text(group.label.toUpperCase(),
                    style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.textMutedOf(context),
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8)),
              ),
              AnimatedRotation(
                turns: open ? 0 : -0.25,
                duration: AppMotion.durationOf(context, AppMotion.tight),
                child: Icon(Icons.expand_more_rounded,
                    size: 16, color: AppColors.textMutedOf(context)),
              ),
            ]),
          ),
        ),
      ),
      if (open)
        for (final c in caps) _Row(cap: c, active: isActive(c.route)),
    ]);
  }
}

class _Row extends StatefulWidget {
  final AppCapability cap;
  final bool active;
  const _Row({required this.cap, required this.active});

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.cap;
    final active = widget.active;
    // Active reads through the accent; hover is a neutral wash. Two different
    // signals, so hovering an inactive row never looks like selecting it.
    final bg = active
        ? c.accent.withValues(alpha: 0.14)
        : _hover
            ? AppColors.glassFill(context)
            : Colors.transparent;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () => context.go(c.route),
        child: AnimatedContainer(
          duration: AppMotion.durationOf(context, AppMotion.instant),
          margin: const EdgeInsets.symmetric(
              horizontal: AppSpace.sm, vertical: 1),
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.sm, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: AppDepth.radius(1),
          ),
          child: Row(children: [
            Icon(c.icon,
                size: 18,
                color: active ? c.accent : AppColors.textSecondaryOf(context)),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Text(c.label,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: active
                        ? AppColors.textPrimaryOf(context)
                        : AppColors.textSecondaryOf(context),
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  )),
            ),
            // Delegated marker. Small on purpose: it is provenance, not status.
            if (c.delegated)
              Container(
                width: 5, height: 5,
                decoration: BoxDecoration(
                  color: AppColors.holoTeal,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
