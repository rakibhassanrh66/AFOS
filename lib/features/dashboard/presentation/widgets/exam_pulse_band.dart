import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../config/supabase_config.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../config/theme/app_text_styles.dart';
import '../../../../config/theme/chart_palette.dart';
import '../../../../config/theme/depth.dart';
import '../../../../config/theme/motion.dart';
import '../../../../config/theme/spacing.dart';

/// The live examination band on the dashboard.
///
/// WHERE IT SITS, and why that is exact: directly under the search field and
/// directly above the module tiles. It adds a row; it removes nothing.
///
/// WHAT IT ANSWERS. A student in an exam period wants three things and had to
/// navigate for all of them: is there an exam today, when is the next one, and
/// which room. The routine says when, the seat plan says where, and until this
/// release nothing in the app joined those two documents. `my_exam_schedule()`
/// does the join server-side and returns the caller's own rows only.
///
/// IT DISAPPEARS WHEN THE TERM ENDS. A finished exam period that keeps
/// advertising a date which has already passed is worse than no banner at all,
/// so `isOver` hides the whole band for students and teachers. Administrators
/// keep their own views elsewhere.
class ExamPulseData {
  final String? role;
  final Map<String, dynamic> term;
  final List<Map<String, dynamic>> exams;
  final List<Map<String, dynamic>> duties;

  const ExamPulseData({
    this.role,
    this.term = const {},
    this.exams = const [],
    this.duties = const [],
  });

  bool get hasTerm => term.isNotEmpty && term['id'] != null;
  bool get isOver => term['isOver'] == true;
  bool get isLive => term['isLive'] == true;

  String get termName {
    final t = '${term['type'] ?? ''}';
    final s = '${term['season'] ?? ''}';
    final y = '${term['year'] ?? ''}';
    String cap(String v) =>
        v.isEmpty ? v : '${v[0].toUpperCase()}${v.substring(1)}';
    return [cap(t), cap(s), y].where((v) => v.isNotEmpty).join(' ');
  }

  static DateTime? _d(Object? v) =>
      v == null ? null : DateTime.tryParse('$v')?.toLocal();

  DateTime? get endsOn => _d(term['endsOn']);

  /// Rows for a specific day, in slot order.
  List<Map<String, dynamic>> on(DateTime day) {
    bool same(Object? v) {
      final d = _d(v);
      return d != null &&
          d.year == day.year &&
          d.month == day.month &&
          d.day == day.day;
    }

    final rows = exams.where((e) => same(e['date'])).toList()
      ..sort((a, b) => '${a['slot']}'.compareTo('${b['slot']}'));
    return rows;
  }

  List<Map<String, dynamic>> get today => on(DateTime.now());

  /// The soonest exam strictly after today, or null.
  Map<String, dynamic>? get next {
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    Map<String, dynamic>? best;
    DateTime? bestDate;
    for (final e in exams) {
      final d = _d(e['date']);
      if (d == null || !d.isAfter(todayMidnight)) continue;
      if (bestDate == null || d.isBefore(bestDate)) {
        bestDate = d;
        best = e;
      }
    }
    return best;
  }

  /// Exams per day across the term, for the line. Dates with none are kept as
  /// zeroes so the shape reads as a timeline rather than a list.
  List<({DateTime day, int count})> get perDay {
    final byDay = <DateTime, int>{};
    for (final e in exams) {
      final d = _d(e['date']);
      if (d == null) continue;
      final key = DateTime(d.year, d.month, d.day);
      byDay[key] = (byDay[key] ?? 0) + 1;
    }
    final keys = byDay.keys.toList()..sort();
    if (keys.isEmpty) return const [];
    final out = <({DateTime day, int count})>[];
    for (var d = keys.first;
        !d.isAfter(keys.last);
        d = d.add(const Duration(days: 1))) {
      out.add((day: d, count: byDay[d] ?? 0));
    }
    return out;
  }

  static Future<ExamPulseData?> load() async {
    if (SupabaseConfig.client.auth.currentUser == null) return null;
    try {
      final r = await SupabaseConfig.client.rpc('my_exam_schedule');
      if (r is! Map) return null;
      final m = Map<String, dynamic>.from(r);
      return ExamPulseData(
        role: m['role'] as String?,
        term: m['term'] is Map
            ? Map<String, dynamic>.from(m['term'] as Map)
            : const {},
        exams: ((m['exams'] as List?) ?? const [])
            .cast<Map<String, dynamic>>(),
        duties: ((m['duties'] as List?) ?? const [])
            .cast<Map<String, dynamic>>(),
      );
    } catch (_) {
      // Best effort. A dashboard must still open if the exam RPC fails.
      return null;
    }
  }
}

class ExamPulseBand extends StatelessWidget {
  final ExamPulseData? data;
  const ExamPulseBand({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final d = data;
    if (d == null || !d.hasTerm || d.isOver) return const SizedBox.shrink();

    final duties = d.duties;
    final isTeacher = duties.isNotEmpty;
    final todays = d.today;
    if (todays.isEmpty && d.next == null && !isTeacher) {
      return const SizedBox.shrink();
    }

    final cards = <Widget>[
      _ExamCard(data: d),
      _CountdownRing(data: d),
      if (d.perDay.length > 1) _TermLine(data: d),
      if (isTeacher) _DutyCard(duties: duties),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text(d.termName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.titleMedium.copyWith(
                    color: AppColors.textPrimaryOf(context),
                    fontWeight: FontWeight.w700)),
          ),
          if (d.isLive)
            Text('in progress',
                style: AppTextStyles.labelSmall
                    .copyWith(color: AppColors.textSecondaryOf(context))),
        ]),
        const SizedBox(height: AppSpace.sm),
        SizedBox(
          height: 148,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: cards.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpace.md),
            itemBuilder: (_, i) => _Reveal(index: i, child: cards[i]),
          ),
        ),
      ]),
    );
  }
}

/// The staggered entrance, once, on first mount.
class _Reveal extends StatefulWidget {
  final int index;
  final Widget child;
  const _Reveal({required this.index, required this.child});

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: AppMotion.base);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AppMotion.isReduced(context)) {
      _c.value = 1;
      return;
    }
    final delay = AppMotion.staggerFor(context, widget.index);
    delay == Duration.zero
        ? _c.forward()
        : Future.delayed(delay, () {
            if (mounted) _c.forward();
          });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _c, curve: AppMotion.standard);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0.10, 0), end: Offset.zero)
            .animate(curved),
        child: widget.child,
      ),
    );
  }
}

/// The shared surface. Translucent fill and a directional shadow — NOT a new
/// BackdropFilter. The constitution's amended rule is that blur belongs to the
/// shell and a content surface does not add another, and the shell already
/// spends that budget.
class _Card extends StatelessWidget {
  final Widget child;
  final double width;
  final Color accent;
  final VoidCallback? onTap;

  const _Card({
    required this.child,
    required this.width,
    required this.accent,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final body = Container(
      width: width,
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        borderRadius: AppDepth.radius(2),
        border: Border.all(color: AppColors.borderOf(context), width: 0.5),
        boxShadow: AppDepth.shadow(2, isDark: dark),
        // Asymmetric stops, per the constitution: 0/42/46/100 rather than a
        // symmetric two-stop gradient, which is what makes a surface read as
        // lit from one direction instead of as flat plastic.
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0.0, 0.42, 0.46, 1.0],
          colors: [
            Color.alphaBlend(accent.withValues(alpha: dark ? 0.22 : 0.14),
                AppColors.surfaceOf(context)),
            Color.alphaBlend(accent.withValues(alpha: dark ? 0.12 : 0.07),
                AppColors.surfaceOf(context)),
            AppColors.surfaceOf(context),
            AppColors.surfaceOf(context),
          ],
        ),
      ),
      child: child,
    );
    if (onTap == null) return body;
    return GestureDetector(onTap: onTap, child: body);
  }
}

/// Today's exam, or the next one.
class _ExamCard extends StatelessWidget {
  final ExamPulseData data;
  const _ExamCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final todays = data.today;
    final live = todays.isNotEmpty;
    final row = live ? todays.first : data.next;
    if (row == null) return const SizedBox.shrink();

    final when = DateTime.tryParse('${row['date']}')?.toLocal();
    final rooms = ((row['rooms'] as List?) ?? const []).cast<String>();
    final accent = live
        ? ChartPalette.critical(context)
        : ChartPalette.series(context, 0);

    return _Card(
      width: 250,
      accent: accent,
      onTap: () => context.push('/exam-seat'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _Pulse(active: live, color: accent),
          const SizedBox(width: AppSpace.xs),
          Text(live ? 'Exam today' : 'Next exam',
              style: AppTextStyles.labelSmall
                  .copyWith(color: accent, fontWeight: FontWeight.w700)),
        ]),
        const Spacer(),
        Text('${row['code']}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.titleMedium.copyWith(
                color: AppColors.textPrimaryOf(context),
                fontWeight: FontWeight.w700)),
        Text('${row['title']}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.labelSmall
                .copyWith(color: AppColors.textSecondaryOf(context))),
        const Spacer(),
        Text(
          [
            if (when != null) '${when.day}/${when.month}',
            if ('${row['start'] ?? ''}'.isNotEmpty)
              '${row['start']}'.substring(0, 5),
            // The room is the whole reason the two documents were joined.
            if (rooms.isNotEmpty) 'Room ${rooms.take(2).join(", ")}',
          ].join('  ·  '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.numericSmall
              .copyWith(color: AppColors.textPrimaryOf(context)),
        ),
        if (rooms.isEmpty)
          Text('Seat plan not published yet',
              maxLines: 1,
              style: AppTextStyles.labelSmall
                  .copyWith(color: AppColors.textSecondaryOf(context))),
      ]),
    );
  }
}

/// A slow pulse, and ONLY while an exam is actually today.
///
/// The constitution bans motion on rebuild and motion added for polish. This
/// is neither: it is a status indicator whose whole meaning is "this is
/// happening now", it runs only on the day, and it stops entirely under
/// reduced motion rather than merely running faster.
class _Pulse extends StatefulWidget {
  final bool active;
  final Color color;
  const _Pulse({required this.active, required this.color});

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shouldRun = widget.active && !AppMotion.isReduced(context);
    if (shouldRun && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!shouldRun && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) {
      return Icon(Icons.event_rounded, size: 12, color: widget.color);
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withValues(alpha: 0.55 + 0.45 * _c.value),
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: 0.45 * _c.value),
              blurRadius: 8 * _c.value,
              spreadRadius: 2 * _c.value,
            ),
          ],
        ),
      ),
    );
  }
}

/// Days left in the exam period, as a ring.
class _CountdownRing extends StatelessWidget {
  final ExamPulseData data;
  const _CountdownRing({required this.data});

  @override
  Widget build(BuildContext context) {
    final end = data.endsOn;
    final perDay = data.perDay;
    if (end == null || perDay.isEmpty) return const SizedBox.shrink();

    final total = perDay.length;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final done = perDay.where((p) => p.day.isBefore(today)).length;
    final left = (total - done).clamp(0, total);

    return _Card(
      width: 150,
      accent: ChartPalette.series(context, 2),
      child: Column(children: [
        Text('Exam days',
            style: AppTextStyles.labelSmall
                .copyWith(color: AppColors.textSecondaryOf(context))),
        Expanded(
          child: Center(
            child: CustomPaint(
              size: const Size(74, 74),
              painter: _ArcPainter(
                fraction: total == 0 ? 0 : done / total,
                done: ChartPalette.series(context, 2),
                rest: ChartPalette.grid(context),
              ),
              child: SizedBox(
                width: 74,
                height: 74,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('$left',
                          style: AppTextStyles.numericLarge.copyWith(
                              color: AppColors.textPrimaryOf(context),
                              fontWeight: FontWeight.w800)),
                      Text('left',
                          style: AppTextStyles.labelSmall.copyWith(
                              color: AppColors.textSecondaryOf(context))),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _ArcPainter extends CustomPainter {
  final double fraction;
  final Color done, rest;
  const _ArcPainter(
      {required this.fraction, required this.done, required this.rest});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 9.0;
    final r = (Offset.zero & size).deflate(stroke / 2);
    Paint pen(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(r, 0, math.pi * 2, false, pen(rest));
    if (fraction > 0) {
      canvas.drawArc(
          r, -math.pi / 2, math.pi * 2 * fraction.clamp(0, 1), false, pen(done));
    }
  }

  @override
  bool shouldRepaint(covariant _ArcPainter o) =>
      o.fraction != fraction || o.done != done || o.rest != rest;
}

/// Exams per day across the term, as a line.
class _TermLine extends StatelessWidget {
  final ExamPulseData data;
  const _TermLine({required this.data});

  @override
  Widget build(BuildContext context) {
    final pts = data.perDay;
    return _Card(
      width: 200,
      accent: ChartPalette.series(context, 1),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Across the term',
            style: AppTextStyles.labelSmall
                .copyWith(color: AppColors.textSecondaryOf(context))),
        const SizedBox(height: AppSpace.xs),
        Text('${data.exams.length} exams',
            style: AppTextStyles.numericMedium.copyWith(
                color: AppColors.textPrimaryOf(context),
                fontWeight: FontWeight.w700)),
        const Spacer(),
        Expanded(
          child: CustomPaint(
            size: Size.infinite,
            painter: _LinePainter(
              values: [for (final p in pts) p.count],
              line: ChartPalette.series(context, 1),
              grid: ChartPalette.grid(context),
              markerAt: pts.indexWhere((p) {
                final n = DateTime.now();
                return p.day.year == n.year &&
                    p.day.month == n.month &&
                    p.day.day == n.day;
              }),
              marker: ChartPalette.critical(context),
            ),
          ),
        ),
      ]),
    );
  }
}

class _LinePainter extends CustomPainter {
  final List<int> values;
  final Color line, grid, marker;
  final int markerAt;

  const _LinePainter({
    required this.values,
    required this.line,
    required this.grid,
    required this.marker,
    required this.markerAt,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final maxV = values.reduce(math.max).toDouble();
    final stepX = size.width / (values.length - 1);
    double yFor(int v) =>
        size.height - (maxV == 0 ? 0 : (v / maxV) * (size.height - 6)) - 3;

    // Baseline, recessive.
    canvas.drawLine(Offset(0, size.height - 1), Offset(size.width, size.height - 1),
        Paint()..color = grid..strokeWidth = 1);

    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final p = Offset(i * stepX, yFor(values[i]));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    // 2px line, per the mark spec.
    canvas.drawPath(
        path,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round);

    // Today, if it falls inside the term. A single emphasised point rather
    // than a dot on every value.
    if (markerAt >= 0 && markerAt < values.length) {
      final p = Offset(markerAt * stepX, yFor(values[markerAt]));
      canvas.drawCircle(p, 4.5, Paint()..color = marker);
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter o) =>
      o.markerAt != markerAt ||
      o.line != line ||
      o.grid != grid ||
      o.marker != marker ||
      o.values.length != values.length;
}

/// A teacher's invigilation duty — deliberately their OWN rooms only.
class _DutyCard extends StatelessWidget {
  final List<Map<String, dynamic>> duties;
  const _DutyCard({required this.duties});

  @override
  Widget build(BuildContext context) {
    final rooms = duties.map((d) => '${d['room']}').toSet().toList()..sort();
    return _Card(
      width: 190,
      accent: ChartPalette.series(context, 3),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Your invigilation',
            style: AppTextStyles.labelSmall
                .copyWith(color: AppColors.textSecondaryOf(context))),
        const Spacer(),
        Text('${duties.length}',
            style: AppTextStyles.numericLarge.copyWith(
                color: AppColors.textPrimaryOf(context),
                fontWeight: FontWeight.w800)),
        Text(duties.length == 1 ? 'duty this term' : 'duties this term',
            style: AppTextStyles.labelSmall
                .copyWith(color: AppColors.textSecondaryOf(context))),
        const Spacer(),
        Text(rooms.take(4).join(', '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.numericSmall
                .copyWith(color: AppColors.textPrimaryOf(context))),
      ]),
    );
  }
}
