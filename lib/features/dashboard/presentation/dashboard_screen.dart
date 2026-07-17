import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_icons.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/offline_cache.dart';
import '../../../shared/models/user_model.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../schedule/data/models/class_slot.dart';
import '../../shell/presentation/top_app_bar.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override State<DashboardScreen> createState() => _DashboardState();
}

class _DashboardState extends State<DashboardScreen> {
  UserModel? _user;
  List<Map<String,dynamic>> _notices = [];
  bool _loading = true;
  StreamSubscription? _noticesSub;

  // Real per-user quick stats — replaces what used to be 4 hardcoded
  // strings ('Today: 4 classes', 'Route 5: On time', ...) shown to every
  // user regardless of role or actual data.
  int? _booksDueSoon;
  String? _hallStatus;
  Map<String, dynamic>? _hallApp;
  bool _statsLoading = true;

  // Full week of the user's own classes (student batch/section or teacher's
  // taught slots), used to compute a live "happening now / next up" status
  // instead of just a same-day count — re-evaluated every minute so a class
  // ending or the next one starting updates without a manual refresh.
  List<ClassSlot> _weekSlots = [];
  Timer? _tickTimer;

  // Super_admin gets its own oversight stats instead — the tally of every
  // pending-action queue across the app (new signups, hall, clubs,
  // conference rooms, CR requests, feedback) that used to have literally
  // nothing shown here for this role once the old fake student chips were
  // removed, reading as "half the dashboard is missing".
  Map<String, int> _adminPending = {};

  @override
  void initState() {
    super.initState();
    _load();
    _tickTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() { _noticesSub?.cancel(); _tickTimer?.cancel(); super.dispose(); }

  Future<void> _load() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) { setState(() { _loading = false; _statsLoading = false; }); return; }
    try {
      // Cached so a cold open while offline shows the last-known profile
      // and notices instead of hanging on the loading shimmer forever (a
      // live .stream() never emits at all with no connection).
      final profileRaw = await cachedMapFetch(
        cacheKey: 'dashboard_profile_$uid',
        liveFetch: () => SupabaseConfig.client
            .from('profiles').select('*, students(batch_label,section)').eq('id', uid).single(),
      );
      if (profileRaw == null) { if (mounted) setState(() { _loading = false; _statsLoading = false; }); return; }
      if (mounted) setState(() => _user = UserModel.fromJson(profileRaw));
      // A super_admin posting a notice should reach open dashboards
      // immediately, not on next manual refresh — subscribe instead of
      // fetching once.
      _noticesSub?.cancel();
      _noticesSub = cachedListStream(
        cacheKey: 'dashboard_notices',
        liveStream: () => SupabaseConfig.client.from('notices').stream(primaryKey: ['id'])
            .order('created_at', ascending: false).limit(3)
            .map((rows) => rows.map((r) => Map<String, dynamic>.from(r)).toList()),
      ).listen((rows) {
        if (mounted) setState(() { _notices = rows; _loading = false; });
      });
      unawaited(_loadQuickStats(profileRaw, uid));
    } catch (_) {
      if (mounted) setState(() { _loading = false; _statsLoading = false; });
    }
  }

  Future<void> _loadQuickStats(Map<String,dynamic> p, String uid) async {
    final role = p['role'] as String? ?? 'student';
    final dept = p['department'] as String?;

    if (role == 'student') {
      final students = p['students'];
      final sd = students is List && students.isNotEmpty
          ? students.first as Map<String, dynamic>?
          : (students is Map<String, dynamic> ? students : null);
      final batch = sd?['batch_label'] as String?;
      final section = sd?['section'] as String?;

      if (dept != null && batch != null && section != null) {
        try {
          final rows = await SupabaseConfig.client.from('schedule_slots')
              .select().eq('department', dept) as List;
          final mine = rows.where((s) =>
              s['is_cancelled'] != true &&
              (s['batch'] as String?)?.toLowerCase() == batch.toLowerCase() &&
              (s['section'] as String?)?.toLowerCase() == section.toLowerCase())
              .map((s) => ClassSlot.fromJson(s as Map<String, dynamic>)).toList();
          if (mounted) setState(() => _weekSlots = mine);
        } catch (_) {}
      }

      try {
        final rows = await SupabaseConfig.client.from('borrowed_books')
            .select('due_date').eq('student_id', uid).eq('status', 'borrowed') as List;
        final now = DateTime.now();
        final dueSoon = rows.where((b) {
          final due = DateTime.tryParse(b['due_date'] as String? ?? '');
          return due != null && due.difference(now).inDays <= 3;
        }).length;
        if (mounted) setState(() => _booksDueSoon = dueSoon);
      } catch (_) {}

      try {
        final rows = await SupabaseConfig.client.from('hall_applications')
            .select('status,assigned_room,assigned_building,assigned_floor').eq('student_id', uid)
            .order('created_at', ascending: false).limit(1) as List;
        if (mounted) {
          setState(() {
          _hallStatus = rows.isNotEmpty ? rows.first['status'] as String? : null;
          _hallApp = rows.isNotEmpty ? rows.first as Map<String, dynamic> : null;
        });
        }
      } catch (_) {}
    } else if (role == 'teacher') {
      final initial = p['teacher_initial'] as String?;
      if (initial != null) {
        try {
          final rows = await SupabaseConfig.client.from('schedule_slots')
              .select().eq('teacher_initial', initial) as List;
          final mine = rows.where((s) => s['is_cancelled'] != true)
              .map((s) => ClassSlot.fromJson(s as Map<String, dynamic>)).toList();
          if (mounted) setState(() => _weekSlots = mine);
        } catch (_) {}
      }
    } else if (role == 'super_admin') {
      try {
        final results = await Future.wait([
          SupabaseConfig.client.from('profiles').select('id').eq('is_verified', false) as Future,
          SupabaseConfig.client.from('hall_applications').select('id')
              .inFilter('status', ['pending', 'reviewing', 'cancel_requested']) as Future,
          SupabaseConfig.client.from('club_membership_requests').select('id').eq('status', 'pending') as Future,
          SupabaseConfig.client.from('club_post_requests').select('id').eq('status', 'pending') as Future,
          SupabaseConfig.client.from('conference_room_requests').select('id').eq('status', 'pending') as Future,
          SupabaseConfig.client.from('cr_requests').select('id').eq('status', 'pending') as Future,
          SupabaseConfig.client.from('feedback').select('id').eq('status', 'new') as Future,
        ]);
        if (mounted) {
          setState(() => _adminPending = {
          'users': (results[0] as List).length,
          'hall': (results[1] as List).length,
          'clubs': (results[2] as List).length + (results[3] as List).length,
          'conference': (results[4] as List).length,
          'cr': (results[5] as List).length,
          'feedback': (results[6] as List).length,
        });
        }
      } catch (_) {}
    }

    if (mounted) setState(() => _statsLoading = false);
  }

  List<String> get _quickChips {
    final chips = <String>[];
    // Schedule status now lives in the dedicated _ClassStatusCard below
    // (live now/next class, not just a same-day count) instead of a chip.
    if (_hallStatus == 'approved' && _hallApp?['assigned_room'] != null) {
      chips.add('🏠 Room ${_hallApp!['assigned_room']}');
    } else if (_hallStatus != null) {
      chips.add('🏠 Hall: ${_hallStatusLabel(_hallStatus!)}');
    }
    if (_booksDueSoon != null) {
      chips.add(_booksDueSoon! > 0 ? '📚 $_booksDueSoon book${_booksDueSoon == 1 ? '' : 's'} due soon' : '📚 No books due soon');
    }
    return chips;
  }

  /// The single most contextually relevant module + reason to surface as a
  /// banner, so the landing page leads with what actually matters to this
  /// user right now instead of a flat uniform grid every time.
  (_Module, String)? get _featured {
    if (_hallStatus == 'pending' || _hallStatus == 'reviewing') {
      return (_allModules.firstWhere((m) => m.title == 'Hall'),
          'Your hall application is ${_hallStatusLabel(_hallStatus!).toLowerCase()}');
    }
    if ((_booksDueSoon ?? 0) > 0) {
      return (_allModules.firstWhere((m) => m.title == 'Library'),
          '$_booksDueSoon book${_booksDueSoon == 1 ? '' : 's'} due soon — renew now');
    }
    // Schedule status lives in the dedicated _ClassStatusCard instead.
    return null;
  }

  /// Computes "happening now" / "next up" from the fetched week of classes,
  /// re-evaluated on every rebuild (driven by _tickTimer) so a class ending
  /// or the next one starting updates live without a manual refresh.
  _ClassStatus get _classStatus {
    if (_weekSlots.isEmpty) return const _ClassStatus();
    final now = DateTime.now();
    // schedule_slots.day_of_week is Sat=0..Thu=5, Fri=6 — see schedule_screen.dart.
    final todayIdx = (now.weekday + 1) % 7;
    final nowMin = now.hour * 60 + now.minute;

    int toMin(String hhmmss) {
      final p = hhmmss.split(':');
      return int.parse(p[0]) * 60 + int.parse(p[1]);
    }

    final today = _weekSlots.where((s) => s.dayOfWeek == todayIdx).toList()
      ..sort((a, b) => toMin(a.startTime).compareTo(toMin(b.startTime)));

    ClassSlot? current;
    for (final s in today) {
      if (nowMin >= toMin(s.startTime) && nowMin < toMin(s.endTime)) { current = s; break; }
    }

    final laterToday = today.where((s) => toMin(s.startTime) > nowMin).toList();
    if (laterToday.isNotEmpty) {
      return _ClassStatus(current: current, next: laterToday.first, nextDayOffset: 0);
    }
    // Nothing left today -- scan forward up to 6 more days for the next slot.
    for (var offset = 1; offset <= 6; offset++) {
      final day = (todayIdx + offset) % 7;
      final onThatDay = _weekSlots.where((s) => s.dayOfWeek == day).toList()
        ..sort((a, b) => toMin(a.startTime).compareTo(toMin(b.startTime)));
      if (onThatDay.isNotEmpty) {
        return _ClassStatus(current: current, next: onThatDay.first, nextDayOffset: offset);
      }
    }
    return _ClassStatus(current: current);
  }

  static const _adminCategories = {
    'users':      ('New Signups',       Icons.how_to_reg_rounded, AppColors.holoviolet, '/admin/users'),
    'hall':       ('Hall Requests',      AppIcons.hall,            AppColors.amber,      '/admin/hall'),
    'clubs':      ('Club Requests',      AppIcons.manageClubs,     AppColors.pink,       '/admin/clubs'),
    'conference': ('Conference Rooms',   AppIcons.conferenceRoom,  AppColors.holoTeal,   '/admin/conference-rooms'),
    'cr':         ('CR Requests',        Icons.badge_rounded,      AppColors.gold,       '/admin/users'),
    'feedback':   ('Feedback',           Icons.feedback_rounded,   AppColors.red,        '/admin/feedback'),
  };

  /// Highest-count pending category, surfaced the same way student/teacher
  /// get a "recommended for you" banner — the single thing most needing
  /// super_admin's attention right now, not a flat unprioritized list.
  (_Module, String)? get _adminFeatured {
    if (_adminPending.isEmpty || _adminPending.values.every((v) => v == 0)) return null;
    final top = _adminPending.entries.where((e) => e.value > 0).reduce((a, b) => a.value >= b.value ? a : b);
    final cat = _adminCategories[top.key]!;
    return (_Module(cat.$1, cat.$2, cat.$3, cat.$4, ''),
        '${top.value} ${cat.$1.toLowerCase()} need${top.value == 1 ? 's' : ''} your review');
  }

  String _hallStatusLabel(String s) => switch (s) {
    'approved' => 'Approved',
    'rejected' => 'Rejected',
    'cancelled' => 'Cancelled',
    'cancel_requested' => 'Cancel pending',
    'reviewing' => 'Reviewing',
    _ => 'Pending',
  };

  static const _allModules = [
    _Module('Schedule',    AppIcons.schedule,    AppColors.blue,   '/schedule',  'Today\'s classes'),
    _Module('Hall',        AppIcons.hall,        AppColors.amber,  '/hall',      'Application status'),
    _Module('Transport',   AppIcons.transport,   AppColors.teal,   '/transport', 'Next departure'),
    _Module('Payment',     AppIcons.payment,     AppColors.gold,   '/payment',   'Check dues'),
    _Module('Library',     AppIcons.library,     AppColors.indigo, '/library',   'Borrowed books'),
    _Module('Lost & Found',AppIcons.lostFound,   AppColors.coral,  '/lost-found','New found items'),
    _Module('Clubs',       AppIcons.clubs,       AppColors.pink,   '/clubs',     'Upcoming events'),
    _Module('Mentorship',  AppIcons.mentorship,  AppColors.blueLight,'/mentorship','Book a session'),
    _Module('Exam Seats',  AppIcons.examSeat,    AppColors.orange, '/exam-seat', 'View seat plan'),
    _Module('Dept Chat',   AppIcons.deptChat,    AppColors.indigo, '/dept-chat', 'Department channel'),
    _Module('VR-ID',       AppIcons.vrId,        AppColors.green,  '/vr-id',     'Active ✓'),
    _Module('Notices',     AppIcons.notices,     AppColors.red,    '/notifications','Latest notices'),
  ];

  // Hall/Payment/Exam Seats/Library are personal student records — matches
  // slide_menu.dart's _studentOnlyItems exactly. This used to only hide
  // them for 'teacher' (and never included Library at all), so every other
  // non-student role (admin/dept_admin/super_admin/staff/exam_controller)
  // still saw these as dashboard tiles even though the slide menu, router
  // guards, and the screens' own internal role checks already treat them
  // as not-applicable for those roles — inconsistent, not just redundant.
  static const _studentOnlyModules = {'Hall', 'Payment', 'Exam Seats', 'Library'};

  String _search = '';

  List<_Module> get _modules => _user?.role == 'student' || _user?.role == null
      ? _allModules
      : _allModules.where((m) => !_studentOnlyModules.contains(m.title)).toList();

  List<_Module> get _visibleModules {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return _modules;
    return _modules.where((m) => m.title.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.isDark(context) ? AppColors.background : AppColors.lightBg,
      appBar: const AfosAppBar(title: 'Dashboard'),
      body: RefreshIndicator(
        onRefresh: _load, color: AppColors.holoBlue,
        backgroundColor: AppColors.surfaceOf(context),
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              RepaintBoundary(
                child: GlassCard(
                  borderRadius: 20,
                  glowColor: AppColors.holoBlue,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _Greeting(user: _user, loading: _loading),
                      const SizedBox(height: 16),
                      _user?.role == 'super_admin'
                          ? _AdminPendingGrid(pending: _adminPending, categories: _adminCategories, loading: _statsLoading)
                          : _QuickChips(chips: _quickChips, loading: _statsLoading),
                    ]),
                  ),
                ),
              ),
              if (!_loading && !_statsLoading && _search.trim().isEmpty) ...[
                if ((_user?.role == 'student' || _user?.role == 'teacher')) ...[
                  const SizedBox(height: 16),
                  _ClassStatusCard(status: _classStatus),
                ],
                if (_user?.role == 'super_admin' && _adminFeatured != null) ...[
                  const SizedBox(height: 16),
                  _FeaturedCard(module: _adminFeatured!.$1, reason: _adminFeatured!.$2),
                ] else if (_user?.role != 'super_admin' && _featured != null) ...[
                  const SizedBox(height: 16),
                  _FeaturedCard(module: _featured!.$1, reason: _featured!.$2),
                ],
              ],
              const SizedBox(height: 24),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Expanded(child: Text('Modules', style: AppTextStyles.headlineLarge
                    .copyWith(color: AppColors.textPrimaryOf(context)),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
                // Only appears while actively searching -- without Expanded
                // above, this second child had nothing stopping the Row
                // from overflowing once it actually had two competing
                // children (e.g. with larger system font scaling), which
                // the "Modules" text alone could never trigger by itself.
                if (_search.trim().isNotEmpty)
                  Text('${_visibleModules.length} found',
                      style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(context))),
              ]),
              const SizedBox(height: 12),
              TextField(
                  onChanged: (v) => setState(() => _search = v),
                  style: TextStyle(color: AppColors.textPrimaryOf(context)),
                  decoration: InputDecoration(hintText: 'Search facilities (Hall, Transport, Library...)',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true, fillColor: AppColors.glassFill(context),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
              const SizedBox(height: 12),
            ]),
          )),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: _loading
                ? const SliverToBoxAdapter(child: ShimmerGrid(count: 12))
                : _visibleModules.isEmpty
                    ? SliverToBoxAdapter(child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: Text('No facilities match "$_search"',
                            style: TextStyle(color: AppColors.textSecondaryOf(context))))))
                    // A fixed 2-column count looked right at phone widths,
                    // but stretched to fill AdaptiveContentWidth's wider
                    // desktop container it meant exactly 2 giant columns
                    // instead of more, reasonably-sized ones -- a max-extent
                    // delegate keeps each tile a consistent size and adds
                    // columns as space allows instead.
                    //
                    // Height must NOT be width-derived (childAspectRatio):
                    // the tile content -- 44px icon + gaps + two one-line
                    // labels + 28px padding -- is a constant ~122px, but an
                    // aspect-ratio height shrinks with column width and
                    // under-provides at narrow widths (or when the runtime
                    // Google-Fonts fetch falls back to taller system font
                    // metrics), which is exactly the "RenderFlex overflowed
                    // by 10px" the overflow smoke test kept catching on
                    // /home. A fixed extent scaled by the user's text size
                    // fits the content at every width and accessibility
                    // scale.
                    : SliverGrid(
                        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 190, crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            mainAxisExtent:
                                90 + MediaQuery.textScalerOf(context).scale(44)),
                        delegate: SliverChildBuilderDelegate(
                            (ctx, i) => _ModuleCard(m: _visibleModules[i], index: i),
                            childCount: _visibleModules.length)),
          ),
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Expanded(child: Row(children: [
                  const Icon(AppIcons.notices, size: 18, color: AppColors.red),
                  const SizedBox(width: 8),
                  Flexible(child: Text('Latest Notices', style: AppTextStyles.headlineLarge
                      .copyWith(color: AppColors.textPrimaryOf(context)),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                ])),
                TextButton(
                  onPressed: () => context.push('/notifications'),
                  child: const Text('See all →', style: TextStyle(color: AppColors.holoBlue))),
              ]),
              const SizedBox(height: 12),
              if (_loading) const ShimmerList(count: 3, itemHeight: 80)
              else if (_notices.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text('No notices yet',
                      style: TextStyle(color: AppColors.textSecondaryOf(context))))
              else ..._notices.asMap().entries.map((e) =>
                  _NoticeCard(notice: e.value, index: e.key)),
              const SizedBox(height: 32),
            ]),
          )),
        ]),
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  final UserModel? user; final bool loading;
  const _Greeting({this.user, required this.loading});
  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Row(children: [
        ShimmerCard(width: 56, height: 56, radius: 28),
        SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ShimmerCard(width: 200, height: 28, radius: 6),
          SizedBox(height: 8),
          ShimmerCard(width: 140, height: 18, radius: 4),
        ])),
      ]);
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Container(
        width: 56, height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: AppColors.holoGradient,
          boxShadow: [BoxShadow(color: AppColors.holoBlue.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 5))],
        ),
        padding: const EdgeInsets.all(2),
        child: CircleAvatar(
          backgroundColor: AppColors.surfaceOf(context),
          backgroundImage: (user?.avatarUrl?.isNotEmpty ?? false) ? CachedNetworkImageProvider(user!.avatarUrl!) : null,
          child: (user?.avatarUrl?.isNotEmpty ?? false) ? null : Text(user?.initials ?? '?',
              style: AppTextStyles.titleLarge.copyWith(color: AppColors.textPrimaryOf(context), fontWeight: FontWeight.w800)),
        ),
      ),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${AppFormatters.greetingEmoji()} ${AppFormatters.greeting()},',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context))),
        Text(user?.firstName ?? 'Student', style: AppTextStyles.displayMedium
            .copyWith(color: AppColors.textPrimaryOf(context)), maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        Text(AppFormatters.fullDate(DateTime.now()),
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context))),
      ])),
    ]).animate().fadeIn(duration: const Duration(milliseconds: 500), curve: Curves.easeOutCubic);
  }
}

class _FeaturedCard extends StatelessWidget {
  final _Module module; final String reason;
  const _FeaturedCard({required this.module, required this.reason});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(module.route),
      child: RepaintBoundary(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [module.color.withValues(alpha: 0.9), module.color.withValues(alpha: 0.6)]),
          ),
          child: Row(children: [
            Container(width: 44, height: 44,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
                child: Icon(module.icon, color: Colors.white, size: 22)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('RECOMMENDED FOR YOU', style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
              const SizedBox(height: 3),
              Text(reason, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            ])),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_rounded, color: Colors.white),
          ]),
        ),
      ),
    ).animate().fadeIn(duration: const Duration(milliseconds: 400)).slideY(begin: 0.08, curve: Curves.easeOutCubic);
  }
}

class _ClassStatus {
  final ClassSlot? current;
  final ClassSlot? next;
  final int nextDayOffset; // 0 = later today, 1 = tomorrow, ... 6
  const _ClassStatus({this.current, this.next, this.nextDayOffset = 0});
}

/// Live "what's my class situation right now" card for students/teachers —
/// replaces the old flat same-day count with a status that auto-advances as
/// classes start/end (driven by _DashboardState's minute tick timer) and
/// explicitly spells out "no class today, next one's X" instead of leaving
/// the user to guess from a bare number.
class _ClassStatusCard extends StatelessWidget {
  final _ClassStatus status;
  const _ClassStatusCard({required this.status});

  static const _dayNames = ['Saturday', 'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];

  @override
  Widget build(BuildContext context) {
    if (status.current == null && status.next == null) return const SizedBox.shrink();
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);

    String fmtTime(String hhmmss) {
      final p = hhmmss.split(':');
      return AppFormatters.time(DateTime(2000, 1, 1, int.parse(p[0]), int.parse(p[1])));
    }

    String? nextSubtitle;
    if (status.next != null) {
      final n = status.next!;
      final where = '${n.building} · ${n.roomNumber}';
      if (status.nextDayOffset == 0) {
        final p = n.startTime.split(':');
        final startMin = int.parse(p[0]) * 60 + int.parse(p[1]);
        final now = DateTime.now();
        final inMin = startMin - (now.hour * 60 + now.minute);
        final inText = inMin < 60 ? 'in ${inMin}m' : 'in ${(inMin / 60).floor()}h ${inMin % 60}m';
        nextSubtitle = '$where · ${fmtTime(n.startTime)} ($inText)';
      } else {
        nextSubtitle = '$where · ${_dayNames[n.dayOfWeek]} at ${fmtTime(n.startTime)}';
      }
    }

    return GestureDetector(
      onTap: () => context.push('/schedule'),
      child: RepaintBoundary(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: AppColors.surfaceOf(context),
            border: Border.all(color: AppColors.borderOf(context)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (status.current != null) ...[
              Row(children: [
                Container(width: 8, height: 8,
                    decoration: const BoxDecoration(color: AppColors.green, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                const Text('LIVE NOW', style: TextStyle(
                    color: AppColors.green, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
              ]),
              const SizedBox(height: 6),
              Text(status.current!.subject,
                  style: AppTextStyles.titleMedium.copyWith(color: textPrimary, fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text('${status.current!.building} · ${status.current!.roomNumber} · until ${fmtTime(status.current!.endTime)}',
                  style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
              if (nextSubtitle != null) ...[
                const SizedBox(height: 12),
                Divider(color: AppColors.borderOf(context), height: 1),
                const SizedBox(height: 12),
              ],
            ],
            if (nextSubtitle != null) ...[
              Text(status.current != null ? 'NEXT UP' : 'NEXT CLASS', style: const TextStyle(
                  color: AppColors.holoBlue, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
              const SizedBox(height: 6),
              Text(status.next!.subject,
                  style: AppTextStyles.titleMedium.copyWith(color: textPrimary, fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(nextSubtitle, style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
            ] else if (status.current == null) ...[
              Text('No class today',
                  style: AppTextStyles.titleMedium.copyWith(color: textPrimary, fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text('No more classes scheduled this week',
                  style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
            ],
          ]),
        ),
      ),
    ).animate().fadeIn(duration: const Duration(milliseconds: 400)).slideY(begin: 0.08, curve: Curves.easeOutCubic);
  }
}

/// Real per-user status chips (today's class count, hall status, books due) —
/// previously 4 hardcoded strings shown identically to every user regardless
/// of role or actual data. Rendered empty (nothing) once loaded if a role
/// has no scoped chip to show, rather than fabricating one.
class _QuickChips extends StatelessWidget {
  final List<String> chips; final bool loading;
  const _QuickChips({required this.chips, required this.loading});

  @override
  Widget build(BuildContext context) {
    if (loading) {
      // Was a plain Row of 3 fixed-120px cards (~384px, before padding) with
      // no scroll and no width cap -- overflowed on any phone narrower than
      // that, confirmed live ("RenderFlex overflowed by 25 pixels on the
      // right"). The loaded state below already uses a horizontal ListView
      // for the exact same reason; the shimmer placeholder just never
      // matched it.
      return SizedBox(height: 44, child: ListView(
        scrollDirection: Axis.horizontal,
        children: List.generate(3, (i) =>
            const Padding(padding: EdgeInsets.only(right: 8),
                child: ShimmerCard(width: 120, height: 36, radius: 22)))));
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return SizedBox(height: 44, child: ListView(
      scrollDirection: Axis.horizontal,
      children: chips
          .map((t) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  // A direct child of a horizontal ListView gets stretched
                  // to the full 44px cross-axis height by the sliver layout
                  // (unlike Row/Column, which center by default) -- without
                  // this, the padding only inset from the top, leaving the
                  // text looking stuck near the top of the pill.
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: AppColors.glassFill(context),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: AppColors.glassBorder(context), width: 0.5)),
                  child: Text(t, style: TextStyle(
                      color: AppColors.textPrimaryOf(context), fontSize: 12)))))
          .toList()));
  }
}

/// Super_admin's own oversight strip — tappable, colored stat tiles for
/// every pending-action queue in the app, replacing what used to render
/// nothing at all for this role once the fake student chips were removed.
class _AdminPendingGrid extends StatelessWidget {
  final Map<String, int> pending;
  final Map<String, (String, IconData, Color, String)> categories;
  final bool loading;
  const _AdminPendingGrid({required this.pending, required this.categories, required this.loading});

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return SizedBox(height: 72, child: Row(children: List.generate(4, (i) =>
          const Padding(padding: EdgeInsets.only(right: 10), child: ShimmerCard(width: 100, height: 72, radius: 14)))));
    }
    return SizedBox(height: 72, child: ListView(
      scrollDirection: Axis.horizontal,
      children: categories.entries.map((e) {
        final count = pending[e.key] ?? 0;
        final (label, icon, color, route) = e.value;
        final active = count > 0;
        return Padding(padding: const EdgeInsets.only(right: 10), child: GestureDetector(
          onTap: () => context.push(route),
          child: Container(
            width: 104,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            // Direct child of a horizontal ListView -- gets stretched to the
            // full 72px cross-axis height (unlike Row/Column, which center
            // by default), leaving the content crammed at the top with dead
            // space below instead of vertically centered.
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: active ? color.withValues(alpha: 0.14) : AppColors.glassFill(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: active ? color.withValues(alpha: 0.4) : AppColors.glassBorder(context),
                    width: active ? 1 : 0.5)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(icon, size: 16, color: active ? color : AppColors.textSecondaryOf(context)),
                const Spacer(),
                Text('$count', style: TextStyle(
                    color: active ? color : AppColors.textSecondaryOf(context),
                    fontWeight: FontWeight.w800, fontSize: 16)),
              ]),
              const SizedBox(height: 6),
              Text(label, style: TextStyle(color: AppColors.textSecondaryOf(context), fontSize: 10),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ).animate().fadeIn(duration: const Duration(milliseconds: 350))
            .scale(begin: const Offset(0.9, 0.9), curve: Curves.easeOutCubic));
      }).toList(),
    ));
  }
}

/// Lightweight repeated-list-item card: gradient border only, no BackdropFilter.
/// Used for grid/list items where many are on screen at once — full [GlassCard]
/// blur is reserved for hero/summary panels per the perf budget.
class _LiteCard extends StatelessWidget {
  final Widget child; final double borderRadius; final Color accent;
  const _LiteCard({required this.child, required this.accent, this.borderRadius = 16});
  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [accent.withValues(alpha:AppColors.isDark(context) ? 0.35 : 0.25),
                     AppColors.holoTeal.withValues(alpha:0.15)]),
        ),
        padding: const EdgeInsets.all(1),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceOf(context),
            borderRadius: BorderRadius.circular(borderRadius - 1),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _ModuleCard extends StatefulWidget {
  final _Module m; final int index;
  const _ModuleCard({required this.m, required this.index});
  @override State<_ModuleCard> createState() => _ModuleCardState();
}

class _ModuleCardState extends State<_ModuleCard> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.m;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => context.push(m.route),
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          scale: _pressed ? 0.97 : (_hover ? 1.02 : 1.0),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: _hover ? [
                BoxShadow(color: m.color.withValues(alpha: 0.28), blurRadius: 22, spreadRadius: -4, offset: const Offset(0, 8)),
              ] : null,
            ),
            child: _LiteCard(
        accent: m.color,
        child: Padding(
          padding: const EdgeInsets.all(14),
          // Was icon pinned to the top + Spacer() pushing title/subtitle to
          // the bottom -- on a small phone-width card the gap was modest,
          // but the same layout on a much bigger/wider card (or just a
          // squarer aspect ratio) left the icon stranded near the top with
          // a large dead gap below it, reading as "icon too high" /
          // uncentered. A single centered group reads right at any tile
          // size, on every platform (not just web).
          child: Stack(children: [
            Positioned(top: 0, right: 0, child: AnimatedSlide(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                offset: _hover ? const Offset(0.12, -0.12) : Offset.zero,
                child: Icon(Icons.arrow_outward_rounded, size: 15,
                    color: m.color.withValues(alpha: _hover ? 0.9 : 0.5)))),
            Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              AnimatedScale(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                scale: _hover ? 1.08 : 1.0,
                child: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                        colors: [m.color.withValues(alpha: 0.85), m.color.withValues(alpha: 0.55)]),
                    borderRadius: BorderRadius.circular(13),
                    boxShadow: [BoxShadow(color: m.color.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4))]),
                child: Icon(m.icon, color: Colors.white, size: 22)),
              ),
              const SizedBox(height: 10),
              Text(m.title, textAlign: TextAlign.center, style: AppTextStyles.titleMedium
                      .copyWith(color: AppColors.textPrimaryOf(context), fontWeight: FontWeight.w700),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(m.subtitle, textAlign: TextAlign.center, style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textSecondaryOf(context)),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ])),
          ]),
        ),
            ),
          ),
        ),
      ),
    ).animate(delay: Duration(milliseconds: widget.index * 60))
        .fadeIn(curve: Curves.easeOutCubic)
        .scale(begin: const Offset(0.95, 0.95), curve: Curves.easeOutCubic);
  }
}

class _NoticeCard extends StatelessWidget {
  final Map<String,dynamic> notice; final int index;
  const _NoticeCard({required this.notice, required this.index});

  Color _catColor(String? cat) => switch (cat) {
    'EXAM'   => AppColors.red,   'EVENT' => AppColors.holoBlue,
    'URGENT' => AppColors.gold,  _ => AppColors.green,
  };

  IconData _catIcon(String? cat) => switch (cat) {
    'EXAM'   => Icons.edit_note_rounded,     'EVENT' => Icons.celebration_rounded,
    'URGENT' => Icons.priority_high_rounded, _ => Icons.campaign_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final cat = notice['category'] as String? ?? 'GENERAL';
    final c = _catColor(cat);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _LiteCard(
        borderRadius: 12,
        accent: c,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              border: Border(left: BorderSide(color: c, width: 3))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 34, height: 34,
                decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
                child: Icon(_catIcon(cat), color: c, size: 17)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: c.withAlpha(38), borderRadius: BorderRadius.circular(4)),
                child: Text(cat, textHeightBehavior: const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
                    style: TextStyle(color: c, fontSize: 10, height: 1.0, fontWeight: FontWeight.w700))),
              const SizedBox(height: 6),
              Text(notice['title'] ?? '', style: AppTextStyles.titleMedium
                      .copyWith(color: AppColors.textPrimaryOf(context)),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(notice['body'] ?? '', style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textSecondaryOf(context)),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            ])),
          ]),
        ),
      ),
    ).animate(delay: Duration(milliseconds: index * 100))
        .fadeIn(curve: Curves.easeOutCubic).slideY(begin: 0.05, curve: Curves.easeOutCubic);
  }
}

class _Module {
  final String title, route, subtitle; final IconData icon; final Color color;
  const _Module(this.title, this.icon, this.color, this.route, this.subtitle);
}
