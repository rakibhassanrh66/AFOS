import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:rxdart/rxdart.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_icons.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/depth.dart';
import '../../../config/theme/liquid_glass_tokens.dart';
import '../../../config/theme/motion.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/user_model.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/glass_sheet.dart';
import '../../../shared/widgets/glass_tab_bar.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../notifications/data/repositories/notification_service.dart';
import '../../shell/presentation/top_app_bar.dart';
import '../../../config/theme/spacing.dart';
import '../data/models/class_slot.dart';
import '../data/repositories/schedule_repository.dart';
import 'widgets/semester_break_card.dart';

import '../../../core/layout/nav_insets.dart';
import '../../web/presentation/widgets/adaptive_list.dart';
/// Pairwise same-day/overlapping-time check over a slot list — used both
/// as a confirmation before pinning a retake course and as a persistent
/// warning chip if a later routine re-upload creates a clash with an
/// already-pinned or regular class.
List<ClassSlot> findConflictsWith(ClassSlot candidate, List<ClassSlot> existing) =>
    existing.where((s) => s.id != candidate.id && s.overlaps(candidate)).toList();

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});
  @override State<ScheduleScreen> createState() => _ScheduleState();
}

class _ScheduleState extends State<ScheduleScreen> with SingleTickerProviderStateMixin {
  // schedule_slots.day_of_week is stored Sat=0..Thu=5 (Fri=6, DIU's weekly
  // holiday, matching parse-routine's dayMap/DAY_NAMES) — NOT the ISO
  // Mon=1..Sun=7 that DateTime.weekday uses, so this remaps rather than
  // just subtracting 1 (which both pointed at the wrong day's classes and
  // overflowed the 6-entry label list on a Sunday: weekday=7 → index 6).
  int _day = (DateTime.now().weekday + 1) % 7;
  UserModel? _user;
  String? _myBatch, _mySection, _myTeacherInitial;
  bool _loading = true;
  Map<String, dynamic>? _classHeader;

  /// Set once the department's final exams are over and no newer routine has
  /// been uploaded. When present it REPLACES the day's slots: last term's
  /// timetable is still in the table, so leaving it on screen would keep
  /// advertising classes that are not happening.
  SemesterBreak? _break;

  /// Whether this routine timetables anything against the viewer's teacher
  /// initial. Null until checked; false also covers "no initial set at all".
  /// Only meaningful for faculty.
  bool? _initialInRoutine;
  late TabController _tab;
  final _repo = ScheduleRepository();
  Map<String, ({String fullName, String? avatarUrl})> _teacherDirectory = const {};
  static const _days = ['Sat','Sun','Mon','Tue','Wed','Thu','Fri'];

  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  List<ClassSlot> _searchResults = [];
  bool _searching = false;
  bool _searchOpen = false;
  List<ClassSlot> _allMySlots = []; // last-emitted effective set (regular + pinned), for conflict checks

  bool get _isFacultyRole => _user?.role == 'teacher';
  // Class schedule only ever meant anything for a student's own
  // batch+section or a teacher's own taught classes — admin/staff/
  // super_admin/dept_admin/exam_controller have neither, so the old
  // fallback to `watchSchedule(department, semester, day)` was showing
  // that role a semi-arbitrary department-wide list using their profile's
  // leftover default department/semester values, which reads as "fake/mock
  // data" to someone who has no personal schedule to begin with.
  bool get _scheduleNotApplicable => _user != null && !_isFacultyRole && _user!.role != 'student';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _loadUser();
    _repo.getTeacherDirectory().then((dir) { if (mounted) setState(() => _teacherDirectory = dir); });
  }

  @override
  void dispose() { _searchDebounce?.cancel(); _tab.dispose(); _searchCtrl.dispose(); super.dispose(); }

  Future<void> _loadUser() async {
    final uid = SupabaseConfig.uid;
    if(uid==null) { setState(()=>_loading=false); return; }
    // `.single()` throws on zero rows and on any dropped request, and this was
    // unguarded — so a flaky connection left Schedule, a primary tab, on its
    // shimmer permanently with no error and no way back. The screen degrades
    // fine without the profile (the routine tabs still render), so swallow and
    // let the load finish rather than blocking on it.
    try {
      final p = await SupabaseConfig.client.from('profiles').select().eq('id',uid).single();
      if(mounted) {
        setState(() {
        _user = UserModel.fromJson(p);
        _myBatch = p['batch'] as String?;
        _mySection = p['section'] as String?;
        _myTeacherInitial = p['teacher_initial'] as String?;
      });
      }
    } catch (_) {}
    if (!mounted) return;
    setState(()=>_loading=false);
    if (_user != null) {
      _repo.fetchRoutineHeader(_user!.department, 'class_routine')
          .then((h) { if (mounted) setState(() => _classHeader = h); });
      _repo.semesterBreak(_user!.department)
          .then((b) { if (mounted) setState(() => _break = b); });
      if (_isFacultyRole) {
        final initial = _myTeacherInitial?.trim() ?? '';
        if (initial.isEmpty) {
          if (mounted) setState(() => _initialInRoutine = false);
        } else {
          _repo.routineMentionsTeacher(initial).then(
              (v) { if (mounted) setState(() => _initialInRoutine = v); });
        }
      }
    }
  }

  Stream<List<ClassSlot>> _regularClassesStream() {
    if (_isFacultyRole && _myTeacherInitial != null && _myTeacherInitial!.isNotEmpty) {
      return _repo.watchMyClassesAsTeacher(_myTeacherInitial!, _day);
    }
    if (!_isFacultyRole && _myBatch != null && _myBatch!.isNotEmpty && _mySection != null && _mySection!.isNotEmpty) {
      return _repo.watchMyClassesAsStudent(_user!.department, _myBatch!, _mySection!, _day);
    }
    return _repo.watchSchedule(_user!.department, _user!.semester, _day);
  }

  /// The "effective" set for the selected day: regular batch/section-or-
  /// teacher-initial classes UNION any retake courses the user has manually
  /// pinned (see pinSlot), deduped by id and sorted by start time — this is
  /// what conflict detection runs over and what the day's list actually shows.
  ///
  /// Memoized by day rather than rebuilt on every call: this used to be
  /// invoked fresh inline as `StreamBuilder(stream: _classesStream())`
  /// inside build(), so ANY unrelated setState in this widget (tab switch,
  /// search toggle, teacher directory load) handed StreamBuilder a brand
  /// new Rx.combineLatest2 stream wrapping brand new underlying Supabase
  /// realtime .stream() subscriptions — the old subscription's teardown and
  /// the new one's setup raced, live-crashing with "Bad state: Stream has
  /// already been listened to." Caching by _day means the same Stream
  /// instance survives unrelated rebuilds, only recreated when the day
  /// actually changes.
  Stream<List<ClassSlot>>? _classesStreamMemo;
  int? _classesStreamMemoDay;
  Stream<List<ClassSlot>> _classesStream() {
    if (_classesStreamMemo == null || _classesStreamMemoDay != _day) {
      _classesStreamMemoDay = _day;
      _classesStreamMemo = Rx.combineLatest2<List<ClassSlot>, List<ClassSlot>, List<ClassSlot>>(
        _regularClassesStream(),
        _repo.watchMyPinnedSlots(),
        (regular, pinned) {
          final byId = <String, ClassSlot>{};
          for (final s in regular) { byId[s.id] = s; }
          for (final s in pinned) { if (s.dayOfWeek == _day) byId[s.id] = s; }
          final all = byId.values.toList()..sort((a, b) => a.startTime.compareTo(b.startTime));
          _allMySlots = all;
          return all;
        },
        // Rx.combineLatest2's own output is single-subscription regardless
        // of whether its inputs are broadcast (making the inputs broadcast,
        // tried first, did not stop the live crash) -- broadcasting the
        // actual stream StreamBuilder subscribes to is what makes a second
        // .listen() on it structurally safe rather than relying on rxdart's
        // internals.
      ).asBroadcastStream();
    }
    return _classesStreamMemo!;
  }

  // Live, debounced filtering as the user types (the field previously only
  // searched on Enter via onSubmitted, so it read as "search doesn't work").
  void _onSearchChanged(String v) {
    _searchDebounce?.cancel();
    final q = v.trim();
    if (q.length < 2) {
      setState(() { _searchResults = []; _searching = false; });
      return;
    }
    setState(() => _searching = true);
    // NOT a motion token, and must not become one. This is an input debounce:
    // how long to wait for the user to stop typing before spending a network
    // request. AppMotion's ladder describes how long things take to MOVE, and
    // borrowing a rung here would couple search latency to animation feel — a
    // later tweak to `base` would silently change how often the app queries
    // Supabase. Different concern, different number.
    _searchDebounce = Timer(const Duration(milliseconds: 300), () => _searchCourses(q));
  }

  Future<void> _searchCourses(String code) async {
    if (_user == null) return;
    setState(() => _searching = true);
    try {
      final results = await _repo.searchByCourseCode(code, department: _user!.department);
      if (mounted) setState(() { _searchResults = results; _searching = false; });
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _pinSlot(ClassSlot slot) async {
    // Compare against the merged set, not the raw one — a merged multi-slot
    // lab candidate's own leftover raw fragments would otherwise fall inside
    // its own new wider time range and register as a false self-conflict.
    final conflicts = findConflictsWith(slot, mergeAdjacentSlots(_allMySlots));
    if (conflicts.isNotEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dctx) => AlertDialog(
          backgroundColor: AppColors.surfaceOf(dctx),
          title: Text('Schedule conflict', style: TextStyle(color: AppColors.textPrimaryOf(dctx))),
          content: Text(
              'This overlaps with ${conflicts.first.subject} (${conflicts.first.startTime}–${conflicts.first.endTime}). Add anyway?',
              style: TextStyle(color: AppColors.textSecondaryOf(dctx))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('Add anyway')),
          ],
        ),
      );
      if (proceed != true) return;
    }
    try {
      await _repo.pinSlot(slot.id);
      if (mounted) {
        // The pin is written; confirm what happened, not what was pressed.
        AppHaptics.success();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Added to your schedule'), backgroundColor: AppColors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
  }

  Future<void> _unpinSlot(ClassSlot slot) async {
    try {
      await _repo.unpinSlot(slot.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasRoutineInfo = _isFacultyRole
        ? (_myTeacherInitial?.isNotEmpty ?? false)
        : ((_myBatch?.isNotEmpty ?? false) && (_mySection?.isNotEmpty ?? false));

    if (_scheduleNotApplicable) {
      return Scaffold(
        backgroundColor: AppColors.isDark(context) ? AppColors.background : AppColors.lightBg,
        appBar: const AfosAppBar(title:'Class Schedule'),
        body: const EmptyState(icon: Icons.calendar_today_outlined, title: 'Not applicable for your role',
            subtitle: 'Class schedules are personal to students and teachers only.'),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.isDark(context) ? AppColors.background : AppColors.lightBg,
      appBar: AfosAppBar(title:'Class Schedule', actions: [
        IconButton(
          icon: Icon(_searchOpen ? Icons.close_rounded : Icons.search_rounded, color: AppColors.textPrimaryOf(context)),
          tooltip: 'Find a retake class by course code',
          onPressed: () => setState(() {
            _searchOpen = !_searchOpen;
            if (!_searchOpen) { _searchResults = []; _searchCtrl.clear(); }
          }),
        ),
      ]),
      body: Column(children:[
        const SizedBox(height: 10),
        AnimatedBuilder(
          animation: _tab,
          builder: (ctx, _) => GlassTabBar(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            currentIndex: _tab.index,
            onChanged: (i) => _tab.animateTo(i),
            tabs: const [
              GlassTab('Class Routine', icon: Icons.event_note_rounded),
              GlassTab('Exam Routine', icon: Icons.assignment_rounded),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (!_loading && !hasRoutineInfo) Container(
            width: double.infinity, color: AppColors.gold.withValues(alpha: 0.08),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Text(
                _isFacultyRole
                    ? 'Set your teacher initials in Settings to see only your own classes.'
                    : 'Set your batch/section in Settings to see only your own classes.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.gold.withValues(alpha: 0.9), fontSize: 12))),
        Expanded(child: TabBarView(controller: _tab, children: [
          Column(children:[
            if (_searchOpen) _SearchBar(controller: _searchCtrl, onSubmit: _searchCourses, onChanged: _onSearchChanged),
            if (_searchOpen)
              Expanded(child: _searching
                  ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList())
                  : _searchResults.isEmpty
                      ? const EmptyState(icon: Icons.search_off_rounded, title: 'Search a course code',
                          subtitle: 'e.g. CSE112 — including retake sections')
                      : Builder(builder: (ctx) {
                          final merged = mergeAdjacentSlots(_searchResults);
                          final existingMerged = mergeAdjacentSlots(_allMySlots);
                          return AdaptiveList(
                            padding: EdgeInsetsDirectional.fromSTEB(16, 16, 16, 16 + NavInsets.of(context)),
                            itemCount: merged.length,
                            itemBuilder: (ctx, i) {
                              final s = merged[i];
                              final pinned = _allMySlots.any((p) => p.id == s.id);
                              return _ClassCard(slot: s, index: i, teacherDirectory: _teacherDirectory,
                                  isTeacher: _isFacultyRole, repo: _repo,
                                  isPinnable: !pinned, isPinned: pinned,
                                  conflicts: findConflictsWith(s, existingMerged),
                                  onPin: () => _pinSlot(s), onUnpin: () => _unpinSlot(s));
                            });
                        }))
            else ...[
            if (_user != null) _RoutineHeaderBanner(kind: 'Class Routine', department: _user!.department, header: _classHeader),
            _DaySelector(selected:_day, onTap:(i)=>setState(()=>_day=i)),
            Expanded(child: _loading
              ? const Padding(padding:EdgeInsets.all(16),child:ShimmerList())
              : _user==null
                ? Center(child:Text('Could not load profile',
                    style:TextStyle(color:AppColors.textSecondaryOf(context))))
                : StreamBuilder<List<ClassSlot>>(
                    stream: _classesStream(),
                    builder:(ctx,snap) {
                      if(snap.connectionState==ConnectionState.waiting) {
                        return const Padding(padding:EdgeInsets.all(16),child:ShimmerList());
                      }
                      final slots = snap.data??[];
                      // BEFORE the slots are considered, not after. Last
                      // term's routine is still in schedule_slots once the
                      // finals end, so `slots.isEmpty` is false and the day
                      // view would happily print a finished semester's
                      // classes, with times, as if term were running. That is
                      // the reported fault, and an empty-state could never
                      // have caught it.
                      if (_break != null) {
                        return SingleChildScrollView(
                          padding: const EdgeInsets.all(AppSpace.md),
                          child: SemesterBreakCard(brk: _break!),
                        );
                      }
                      if(slots.isEmpty) {
                        // "Enjoy your free day!" was the only thing this ever
                        // said, and for a final-year student it is frequently
                        // WRONG rather than merely unhelpful.
                        //
                        // A student's day view is `.eq('batch', myBatch)` plus
                        // whatever they've pinned. Retake sessions are not
                        // filed under any intake's batch — the routine prints
                        // them as RE_A / RE_B / RE_C, so they land in
                        // schedule_slots with batch = 'RE' (175 rows across 69
                        // distinct courses, live). Nothing in a student's own
                        // batch query can ever match one.
                        //
                        // That is invisible for batch 70, who take a full load
                        // of regular classes. It is most of the timetable for
                        // batches 63 and 64, who have finished the core
                        // curriculum -- the whole routine holds only 26 and 92
                        // regular slots for them (verified against the source
                        // PDF: it prints 28 and 93 tokens for those batches, so
                        // nothing is being lost on import). So the app was
                        // telling the students most likely to have a retake
                        // that day to enjoy their free day.
                        //
                        // The retake path is fully built -- searchByCourseCode
                        // finds them, pinSlot adds them, findConflictsWith
                        // warns on a clash. It was just never signposted from
                        // the one screen where its absence is felt.
                        // THE SAME MISTAKE THIS BLOCK'S COMMENT DESCRIBES, ON
                        // THE OTHER SIDE OF THE ROOM.
                        //
                        // "Nothing is scheduled for you today" was said to
                        // every teacher with an empty day, including the ones
                        // whose day is empty because the app cannot match them
                        // to the routine at all. A teacher's day is looked up
                        // purely by teacher_initial, and on 2026-09-01 three of
                        // this department's four teachers could never match:
                        // two have no initial stored, and one's 'FNB' is not
                        // among the routine's 221 initials (FFN and FNN are,
                        // so it reads like a typo). All three were being told
                        // they had a free day.
                        //
                        // Each case now says what is actually true, and the
                        // first two say what to do about it — the initial is
                        // editable by the teacher in Settings.
                        final noInitial =
                            (_myTeacherInitial?.trim() ?? '').isEmpty;
                        if (_isFacultyRole && noInitial) {
                          return const EmptyState(
                            icon: AppIcons.schedule,
                            title: 'Your teaching initial is not set',
                            subtitle:
                                'Your classes are matched to the routine by your '
                                'initial, so nothing can be found without it. Add '
                                'it in Settings, or ask an admin to.',
                          );
                        }
                        if (_isFacultyRole && _initialInRoutine == false) {
                          return EmptyState(
                            icon: AppIcons.schedule,
                            title: 'No classes under "${_myTeacherInitial!.trim()}"',
                            subtitle:
                                'This routine does not mention that initial '
                                'anywhere, so it may be spelled differently here. '
                                'Check it in Settings against the printed routine.',
                          );
                        }
                        return EmptyState(
                          icon: AppIcons.schedule,
                          title: 'No classes ${_days[_day]}',
                          subtitle: _isFacultyRole
                              ? 'Nothing is scheduled for you today.'
                              : 'Retake classes are not listed automatically — '
                                'search the course code to add one to your routine.',
                          actionLabel: _isFacultyRole ? null : 'Find a retake class',
                          onAction: _isFacultyRole ? null : () => setState(() => _searchOpen = true),
                        );
                      }
                      // Display-only: a 3-hour lab stores as two consecutive
                      // 1.5-hour rows (needed for accurate conflict
                      // detection against retakes) but showing that as two
                      // separate back-to-back cards reads as a duplicate or
                      // wrong time — merge into one card spanning the full
                      // block. Conflict checks below also run against this
                      // merged set (not the raw `slots`) — otherwise a
                      // merged lab's own leftover raw fragment would fall
                      // inside its own new wider time range and register as
                      // a false self-conflict.
                      final displaySlots = mergeAdjacentSlots(slots);
                      return Column(children: [
                        if (_isFacultyRole) Padding(
                          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 0),
                          child: Text('${displaySlots.length} class${displaySlots.length == 1 ? '' : 'es'} on ${_days[_day]}',
                              style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.textSecondaryOf(context), fontWeight: FontWeight.w600))),
                        Expanded(child: AdaptiveList(
                          padding: EdgeInsetsDirectional.fromSTEB(16, 16, 16, 16 + NavInsets.of(context)),
                          itemCount:displaySlots.length,
                          itemBuilder:(ctx,i)=>_ClassCard(slot:displaySlots[i],index:i,teacherDirectory:_teacherDirectory,
                            isTeacher:_isFacultyRole, repo:_repo,
                            isPinned: displaySlots[i].isRetake, onUnpin: displaySlots[i].isRetake ? () => _unpinSlot(displaySlots[i]) : null,
                            conflicts: findConflictsWith(displaySlots[i], displaySlots)))),
                      ]);
                    })),
            ],
          ]),
          _loading || _user == null
              ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList())
              : _ExamRoutineTab(repo: _repo, department: _user!.department, batch: _myBatch),
        ])),
      ]),
    );
  }
}

class _ExamRoutineTab extends StatefulWidget {
  final ScheduleRepository repo; final String department; final String? batch;
  const _ExamRoutineTab({required this.repo, required this.department, required this.batch});
  @override State<_ExamRoutineTab> createState() => _ExamRoutineTabState();
}

class _ExamRoutineTabState extends State<_ExamRoutineTab> {
  List<Map<String, dynamic>> _exams = [];
  Map<String, dynamic>? _header;
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final res = await widget.repo.getMyExams(dept: widget.department, batch: widget.batch);
      final header = await widget.repo.fetchRoutineHeader(widget.department, 'exam_routine');
      if (mounted) setState(() { _exams = res; _header = header; _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Padding(padding: EdgeInsets.all(16), child: ShimmerList());
    if (_exams.isEmpty) {
      return const EmptyState(icon: Icons.assignment_outlined,
        title: 'No exam routine yet', subtitle: 'Mid/final term exams will appear here once published');
    }
    // The banner and the validity note are page furniture, not list items.
    // They used to be items 0 and 1 of the AdaptiveList, which on web turns
    // every item into a GRID CELL — so at desktop width the banner rendered
    // one column wide with the note sitting beside it like a card. They scroll
    // with the list (as they always did on phones) but span the full width,
    // by putting the adaptive grid inside the scroll view instead of the
    // furniture inside the grid.
    return RefreshIndicator(onRefresh: _load, color: AppColors.blue,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsetsDirectional.fromSTEB(0, 16, 0, 16 + NavInsets.of(context)),
          children: [
            _RoutineHeaderBanner(kind: 'Exam Routine', department: widget.department, header: _header),
            Padding(padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 12), child: Row(children: [
              Icon(Icons.info_outline_rounded, size: 14, color: AppColors.textSecondaryOf(context)),
              const SizedBox(width: 6),
              Expanded(child: Text('This exam routine stays valid until the next one is uploaded by admin.',
                  style: TextStyle(fontSize: 11, color: AppColors.textSecondaryOf(context)))),
            ])),
            AdaptiveList(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 0),
              itemCount: _exams.length,
              itemBuilder: (ctx, i) => _ExamCard(exam: _exams[i], index: i),
            ),
          ],
        ));
  }
}

class _ExamCard extends StatelessWidget {
  final Map<String, dynamic> exam; final int index;
  const _ExamCard({required this.exam, required this.index});
  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    final examType = exam['exam_type'] as String? ?? 'final';
    final color = examType == 'mid' ? AppColors.holoTeal : AppColors.holoBlue;
    final date = exam['exam_date'] != null ? DateTime.tryParse(exam['exam_date']) : null;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: AppDepth.radius(1),
          border: Border.all(color: color.withValues(alpha:0.3), width: 0.7)),
      child: Row(children: [
        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: color.withValues(alpha:0.12), borderRadius: AppDepth.radius(0)),
            child: Text(examType.toUpperCase(), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(exam['subject'] ?? exam['subject_code'] ?? '', style: AppTextStyles.titleMedium.copyWith(color: textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 3),
          Row(children: [
            if (date != null) ...[
              Icon(Icons.event_rounded, size: 12, color: textSecondary),
              const SizedBox(width: 3),
              Text('${date.day}/${date.month}/${date.year}', style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
              const SizedBox(width: 10),
            ],
            if (exam['start_time'] != null) ...[
              Icon(Icons.access_time_rounded, size: 12, color: textSecondary),
              const SizedBox(width: 3),
              // substring(0,5) turned "13:00:00" into a bare 24-hour "13:00";
              // every other time in the app is 12-hour.
              Text(AppFormatters.time12(exam['start_time'].toString()),
                  style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
            ],
          ]),
        ])),
      ]),
    ).animate(delay: AppMotion.staggerFor(context, index)).fadeIn().slideY(begin: 0.05);
  }
}

/// The "eye-catchy" routine header: the PDF's own printed title/version/
/// effective-date/committee text (captured by parse-routine at upload time),
/// re-rendered here instead of the raw PDF layout — department-driven, not
/// hardcoded to any one department, so this reads correctly no matter which
/// department's routine the signed-in user is looking at. Renders a sane
/// fallback (just the department name, no version line) before any routine
/// has ever been uploaded or if the source file didn't print this text in a
/// recognizable form — never blocks the day's classes from showing.
class _RoutineHeaderBanner extends StatelessWidget {
  final String department;
  final Map<String, dynamic>? header;

  /// What this banner is the header FOR — "Class Routine" or "Exam Routine".
  /// It used to be the hardcoded word "Class", while the exam tab rendered the
  /// same banner off `fetchRoutineHeader(dept, 'exam_routine')`. The data was
  /// already the exam routine's; only the label lied, so the exam tab read
  /// "Class Routine for CSE Program" above a list of exams.
  final String kind;
  const _RoutineHeaderBanner({required this.department, required this.header, required this.kind});

  @override
  Widget build(BuildContext context) {
    final version = header?['version_label'] as String?;
    final effectiveFrom = header?['effective_from_text'] as String?;
    final preparedBy = header?['prepared_by'] as String?;
    final subLine = [
      if (effectiveFrom != null) 'Effective From: $effectiveFrom',
      if (preparedBy != null) 'Prepared by: $preparedBy',
    ].join('   ·   ');

    return Container(
      width: double.infinity,
      margin: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 6),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(gradient: AppColors.holoGradient, borderRadius: AppDepth.radius(2)),
      child: Stack(children: [
        Positioned.fill(child: IgnorePointer(child: DecoratedBox(
            decoration: BoxDecoration(gradient: LiquidGlass.sheen(isDark: true))))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Text(
              '$kind for $department Program${version != null ? '\nVersion $version' : ''}',
              textAlign: TextAlign.center,
              style: AppTextStyles.headlineLarge.copyWith(color: Colors.white, fontWeight: FontWeight.w800, height: 1.3),
            ),
            if (subLine.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(subLine, textAlign: TextAlign.center,
                  style: AppTextStyles.labelSmall.copyWith(color: Colors.white.withValues(alpha: 0.85))),
            ],
          ]),
        ),
      ]),
    ).animate().fadeIn(duration: AppMotion.durationOf(context, AppMotion.slow)).slideY(begin: -0.06, curve: AppMotion.standard);
  }
}

class _DaySelector extends StatelessWidget {
  final int selected; final ValueChanged<int> onTap;
  const _DaySelector({required this.selected, required this.onTap});
  static const _days = ['Sat','Sun','Mon','Tue','Wed','Thu','Fri'];
  @override
  Widget build(BuildContext context) {
    return Container(
      height:52, color:AppColors.surfaceOf(context),
      child: ListView.builder(
        scrollDirection:Axis.horizontal, padding:const EdgeInsets.symmetric(horizontal:16,vertical:8),
        itemCount:_days.length,
        itemBuilder:(ctx,i) {
          final sel = selected==i;
          return GestureDetector(
            onTap:()=>onTap(i),
            child: AnimatedContainer(
              duration: AppMotion.durationOf(context, AppMotion.tight), curve: AppMotion.standard, margin:const EdgeInsetsDirectional.only(end:8),
              padding:const EdgeInsets.symmetric(horizontal:16,vertical:6),
              decoration:BoxDecoration(
                gradient: sel ? AppColors.holoGradient : null,
                color:sel?null:AppColors.glassFill(context),
                borderRadius:AppDepth.radius(2),
                border:Border.all(color:sel?Colors.transparent:AppColors.glassBorder(context),width:0.5)),
              child:Text(_days[i],style:TextStyle(color:sel?Colors.white:AppColors.textSecondaryOf(context),
                fontSize:13,fontWeight:sel?FontWeight.w600:FontWeight.w400)),
            ),
          );
        }),
    );
  }
}

class _ClassCard extends StatelessWidget {
  final ClassSlot slot; final int index;
  final Map<String, ({String fullName, String? avatarUrl})> teacherDirectory;
  final bool isTeacher;
  final ScheduleRepository? repo;
  // isPinnable/onPin: shown in search results for a not-yet-pinned retake.
  // isPinned/onUnpin: shown for an already-pinned slot (either from a search
  // result or in the day's own list) so it can be removed again.
  final bool isPinnable, isPinned;
  final VoidCallback? onPin, onUnpin;
  final List<ClassSlot> conflicts;
  const _ClassCard({required this.slot,required this.index, this.teacherDirectory = const {},
    this.isTeacher = false, this.repo,
    this.isPinnable = false, this.isPinned = false, this.onPin, this.onUnpin,
    this.conflicts = const []});

  Future<void> _messageCr(BuildContext context) async {
    if (repo == null || slot.batch == null || slot.section == null) return;
    final cr = await repo!.findSectionCr(slot.department, slot.batch!, slot.section!);
    if (!context.mounted) return;
    if (cr == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No CR set for this section yet'), backgroundColor: AppColors.amber));
      return;
    }
    final msgCtrl = TextEditingController();
    await showGlassModal(context,
        builder: (sheetCtx) => SingleChildScrollView(
            padding: EdgeInsetsDirectional.fromSTEB(24, 24, 24, MediaQuery.of(sheetCtx).viewInsets.bottom + 24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Message ${cr['full_name']}', style: AppTextStyles.headlineLarge.copyWith(color: AppColors.textPrimaryOf(sheetCtx))),
              const SizedBox(height: 6),
              Text('CR · ${slot.subject} · Batch ${slot.batch} · Section ${slot.section}',
                  style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(sheetCtx))),
              const SizedBox(height: 16),
              TextField(controller: msgCtrl, maxLines: 3, style: TextStyle(color: AppColors.textPrimaryOf(sheetCtx)),
                  decoration: const InputDecoration(hintText: 'Message for the class...')),
              const SizedBox(height: 20),
              SizedBox(width: double.infinity, child: ElevatedButton(
                  onPressed: () async {
                    if (msgCtrl.text.trim().isEmpty) return;
                    Navigator.pop(sheetCtx);
                    await NotificationService.sendToUsers(
                      userIds: [cr['id'] as String],
                      title: '${slot.subject} — message from your teacher',
                      message: msgCtrl.text.trim(),
                      category: 'general',
                    );
                  },
                  child: const Text('Send'))),
            ])));
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    final teacher = teacherDirectory[slot.teacherName.toLowerCase()];
    final teacherLabel = teacher?.fullName ?? slot.teacherName;
    final teacherAvatar = teacher?.avatarUrl;
    return RepaintBoundary(
      child: Container(
        margin:const EdgeInsets.only(bottom:12),
        decoration:BoxDecoration(
          borderRadius:AppDepth.radius(2),
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [AppColors.holoBlue.withValues(alpha:AppColors.isDark(context)?0.3:0.2),
                     AppColors.holoTeal.withValues(alpha:0.12)]),
        ),
        padding: const EdgeInsets.all(1),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceOf(context),
            borderRadius: AppDepth.radius(2)),
          child: Stack(children:[
            Padding(
              padding:const EdgeInsets.all(16),
              child: Row(children:[
                Column(children:[
                  Text(AppFormatters.time12(slot.startTime),style:AppTextStyles.monoSmall.copyWith(color:AppColors.holoBlue)),
                  Container(margin:const EdgeInsets.symmetric(vertical:4),width:1,height:24,color:AppColors.borderOf(context)),
                  Text(AppFormatters.time12(slot.endTime),style:AppTextStyles.monoSmall.copyWith(color:textSecondary)),
                ]),
                const SizedBox(width:14),
                Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                  Text(slot.subject,style:AppTextStyles.titleMedium.copyWith(color:textPrimary),maxLines:2),
                  if (slot.isRetake || slot.isLab || conflicts.isNotEmpty) Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(spacing: 6, runSpacing: 4, children: [
                      if (slot.isRetake) const _Badge(label: 'RETAKE', color: AppColors.gold),
                      if (slot.isLab) _Badge(label: slot.labSubgroup != null ? 'LAB · GROUP ${slot.labSubgroup}' : (slot.roomType ?? 'LAB'), color: AppColors.holoTeal),
                      if (conflicts.isNotEmpty) _Badge(label: 'CONFLICTS WITH ${conflicts.first.subject.toUpperCase()}', color: AppColors.red),
                    ]),
                  ),
                  const SizedBox(height:6),
                  Row(children:[
                    Icon(Icons.location_on_rounded,size:13,color:textSecondary),
                    const SizedBox(width:3),
                    Text('${slot.building} · ${slot.roomNumber}',style:AppTextStyles.bodyMedium.copyWith(color:textSecondary)),
                  ]),
                  if (slot.batch != null && slot.section != null) ...[
                    const SizedBox(height:5),
                    Row(children:[
                      Icon(Icons.groups_outlined,size:13,color:textSecondary),
                      const SizedBox(width:3),
                      Text('Batch ${slot.batch} · Section ${slot.section}',style:AppTextStyles.bodyMedium.copyWith(color:textSecondary)),
                    ]),
                  ],
                  const SizedBox(height:5),
                  Row(children:[
                    CircleAvatar(radius:9, backgroundColor:AppColors.holoBlue.withValues(alpha:0.15),
                      backgroundImage: teacherAvatar!=null ? CachedNetworkImageProvider(teacherAvatar, maxWidth: 128, maxHeight: 128) : null,
                      child: teacherAvatar==null
                        ? const Icon(Icons.person_outline, size:11, color:AppColors.holoBlue)
                        : null),
                    const SizedBox(width:5),
                    Expanded(child: Text(teacherLabel,style:AppTextStyles.bodyMedium.copyWith(color:textSecondary),
                      maxLines:1, overflow:TextOverflow.ellipsis)),
                  ]),
                ])),
                Container(
                  padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),
                  decoration:BoxDecoration(color:AppColors.holoBlue.withValues(alpha:0.12),borderRadius:AppDepth.radius(0)),
                  child:Text('${slot.creditHours}cr',style:const TextStyle(color:AppColors.holoBlue,fontSize:11,fontWeight:FontWeight.w600))),
                if (isPinnable && onPin != null)
                  IconButton(icon: const Icon(Icons.add_circle_outline_rounded, size: 20, color: AppColors.green),
                      tooltip: 'Add to my schedule', onPressed: onPin),
                if (isPinned && onUnpin != null)
                  IconButton(icon: const Icon(Icons.remove_circle_outline_rounded, size: 20, color: AppColors.red),
                      tooltip: 'Remove from my schedule', onPressed: onUnpin),
                if (isTeacher && slot.batch != null && slot.section != null)
                  IconButton(icon: const Icon(Icons.forum_outlined, size: 18, color: AppColors.holoTeal),
                      tooltip: 'Message Section CR', onPressed: () => _messageCr(context)),
              ]),
            ),
            if(slot.isCancelled) Positioned.fill(
              child:Container(
                decoration:BoxDecoration(color:AppColors.red.withValues(alpha:0.88),borderRadius:AppDepth.radius(2)),
                alignment:Alignment.center,
                child:Column(mainAxisSize:MainAxisSize.min,children:[
                  const Icon(Icons.cancel_rounded,color:Colors.white,size:32),
                  const SizedBox(height:6),
                  const Text('CLASS CANCELLED',style:TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.w800,letterSpacing:1.5)),
                  if(slot.cancelledReason!=null) Padding(padding:const EdgeInsets.only(top:4),
                    child:Text(slot.cancelledReason!,style:const TextStyle(color:Colors.white70,fontSize:12))),
                ]),
              ),
            ),
          ]),
        ),
      ),
    ).animate(delay: AppMotion.staggerFor(context, index))
        .fadeIn(curve: AppMotion.standard).slideY(begin:0.05, curve: AppMotion.standard);
  }
}

class _Badge extends StatelessWidget {
  final String label; final Color color;
  const _Badge({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: AppDepth.radius(0)),
    child: Text(label, textHeightBehavior: const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
        style: TextStyle(color: color, fontSize: 9, height: 1.0, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
  );
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onSubmit;
  final ValueChanged<String> onChanged;
  const _SearchBar({required this.controller, required this.onSubmit, required this.onChanged});
  @override
  Widget build(BuildContext context) => Container(
    color: AppColors.surfaceOf(context),
    padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 12),
    child: TextField(
      controller: controller,
      style: TextStyle(color: AppColors.textPrimaryOf(context)),
      textInputAction: TextInputAction.search,
      onChanged: onChanged,
      onSubmitted: onSubmit,
      // Dismiss the keyboard on tap-outside instead of leaving it hanging.
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      decoration: InputDecoration(
        hintText: 'Find a class by course code (e.g. CSE112)…',
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        filled: true, fillColor: AppColors.glassFill(context),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(borderRadius: AppDepth.radius(1), borderSide: BorderSide.none),
      ),
    ),
  );
}
