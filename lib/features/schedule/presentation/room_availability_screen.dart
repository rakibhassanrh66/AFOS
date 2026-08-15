import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/depth.dart';
import '../../../config/theme/liquid_glass_tokens.dart';
import '../../../config/theme/motion.dart';
import '../../../config/theme/spacing.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/feature_header.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../shell/presentation/top_app_bar.dart';
import '../data/models/class_slot.dart';
import '../data/repositories/schedule_repository.dart';

import '../../../core/layout/nav_insets.dart';
/// Room x period availability for a department, teacher/CR-only — this is
/// inherently a room-centric view (the source routine PDF's own axis is
/// Room x Period), not a personal one, so it's a separate screen from the
/// student/teacher "my classes" schedule. Lets a teacher or CR claim a free
/// room/period for 24 hours (e.g. a makeup class) via empty_room_requests.
class RoomAvailabilityScreen extends StatefulWidget {
  const RoomAvailabilityScreen({super.key});
  @override State<RoomAvailabilityScreen> createState() => _RoomAvailabilityScreenState();
}

class _RoomAvailabilityScreenState extends State<RoomAvailabilityScreen> {
  final _repo = ScheduleRepository();
  static const _days = ['Sat', 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri'];
  static const _dayNames = ['Saturday', 'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];
  int _day = 0;
  bool _loading = true;
  String? _department;
  List<Map<String, String>> _rooms = [];
  List<({String start, String end})> _periods = [];
  List<ClassSlot> _daySlots = [];
  List<Map<String, dynamic>> _claims = [];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final uid = SupabaseConfig.uid;
      var department = _department;
      if (department == null && uid != null) {
        final p = await SupabaseConfig.client.from('profiles').select('department').eq('id', uid).single();
        department = p['department'] as String?;
      }
      if (department == null) { if (mounted) setState(() => _loading = false); return; }
      final results = await Future.wait([
        _repo.fetchDistinctRooms(department),
        _repo.fetchDistinctPeriods(department),
        _repo.fetchSlotsForDay(department, _day),
        _repo.fetchEmptyRoomRequests(department, _day),
      ]);
      if (mounted) {
        setState(() {
        _department = department;
        _rooms = results[0] as List<Map<String, String>>;
        _periods = results[1] as List<({String start, String end})>;
        _daySlots = results[2] as List<ClassSlot>;
        _claims = results[3] as List<Map<String, dynamic>>;
        _loading = false;
      });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  ClassSlot? _occupant(String building, String room, ({String start, String end}) period) {
    for (final s in _daySlots) {
      if (s.building == building && s.roomNumber == room && s.startTime == period.start) return s;
    }
    return null;
  }

  Map<String, dynamic>? _claim(String building, String room, ({String start, String end}) period) {
    for (final c in _claims) {
      if (c['building'] == building && c['room_number'] == room && c['start_time'] == '${period.start}:00') return c;
    }
    return null;
  }

  int _freeCountFor(String building, String room) {
    var free = 0;
    for (final period in _periods) {
      if (_occupant(building, room, period) == null && _claim(building, room, period) == null) free++;
    }
    return free;
  }

  int get _freeCount {
    var free = 0;
    for (final room in _rooms) {
      free += _freeCountFor(room['building']!, room['room_number']!);
    }
    return free;
  }

  Future<void> _request(String building, String room, ({String start, String end}) period) async {
    final purposeCtrl = TextEditingController();
    String? purpose;
    try {
      purpose = await showModalBottomSheet<String>(
      context: context, isScrollControlled: true,
      backgroundColor: AppColors.surfaceOf(context),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(LiquidGlass.radiusSheet))),
      builder: (sheetCtx) => Padding(
        padding: EdgeInsetsDirectional.fromSTEB(24, 24, 24, MediaQuery.of(sheetCtx).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.green.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: const Icon(Icons.meeting_room_rounded, color: AppColors.green, size: 22)),
            const SizedBox(width: 12),
            Expanded(child: Text('Claim $building · $room', style: AppTextStyles.headlineLarge.copyWith(color: AppColors.textPrimaryOf(sheetCtx)))),
          ]),
          const SizedBox(height: 10),
          Container(padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.glassFill(sheetCtx), borderRadius: AppDepth.radius(1)),
            child: Row(children: [
              Icon(Icons.schedule_rounded, size: 15, color: AppColors.textSecondaryOf(sheetCtx)),
              const SizedBox(width: 8),
              Text('${AppFormatters.time12(period.start)}–${AppFormatters.time12(period.end)} · ${_dayNames[_day]}',
                  style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimaryOf(sheetCtx), fontWeight: FontWeight.w600)),
            ])),
          const SizedBox(height: 8),
          Text('First come, first served — this claim is visible to everyone and auto-expires in 24 hours.',
              style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(sheetCtx))),
          const SizedBox(height: 16),
          TextField(controller: purposeCtrl, style: TextStyle(color: AppColors.textPrimaryOf(sheetCtx)),
              decoration: InputDecoration(hintText: 'Purpose (e.g. Makeup class for CSE221)',
                  filled: true, fillColor: AppColors.glassFill(sheetCtx),
                  border: OutlineInputBorder(borderRadius: AppDepth.radius(1), borderSide: BorderSide.none))),
          const SizedBox(height: 20),
          AfosButton(label: 'Claim this room', onTap: () => Navigator.pop(sheetCtx, purposeCtrl.text.trim())),
        ]),
      ),
      );
    } finally {
      // BUG_REGISTER P1-02. This controller was created on every claim attempt
      // and never released. The sheet has already closed by the time the await
      // resolves, so disposing here cannot pull the field out from under a
      // live TextField.
      purposeCtrl.dispose();
    }
    if (purpose == null || purpose.isEmpty || !mounted) return;
    try {
      await _repo.requestEmptyRoom(
        department: _department!, building: building, roomNumber: room,
        dayOfWeek: _day, startTime: '${period.start}:00', endTime: '${period.end}:00', purpose: purpose,
      );
      await _load();
      if (mounted) {
        AppHaptics.success();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Room claimed'), backgroundColor: AppColors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textSecondary = AppColors.textSecondaryOf(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const AfosAppBar(title: 'Room Availability'),
      body: Column(children: [
        FeatureHeader(
          title: 'Claim an empty room',
          subtitle: 'First come, first served · visible to everyone',
          icon: Icons.meeting_room_rounded,
          gradient: AppColors.holoGradient,
          margin: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 12),
          trailing: _loading ? null : TweenAnimationBuilder<int>(
            tween: IntTween(begin: 0, end: _freeCount),
            duration: AppMotion.durationOf(context, AppMotion.slow),
            curve: AppMotion.standard,
            builder: (ctx, value, _) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: AppDepth.radius(1)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('$value', textHeightBehavior: const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
                    style: const TextStyle(color: Colors.white, fontSize: 20, height: 1.0, fontWeight: FontWeight.w800)),
                Text('free now', textHeightBehavior: const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 10, height: 1.0)),
              ]),
            ),
          ),
        ).animate().fadeIn(duration: AppMotion.durationOf(context, AppMotion.base))
            .slideY(begin: -0.06, curve: AppMotion.standard),
        // 44 before, i.e. under the 48dp touch floor the constitution sets.
        SizedBox(height: AppSpace.minTouchTarget, child: ListView.builder(
          scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: _days.length,
          itemBuilder: (ctx, i) {
            final sel = _day == i;
            return GestureDetector(
              onTap: () { AppHaptics.selection(); setState(() => _day = i); _load(); },
              child: AnimatedContainer(
                duration: AppMotion.durationOf(context, AppMotion.tight),
                curve: AppMotion.standard,
                margin: const EdgeInsetsDirectional.only(end: 8),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                    gradient: sel ? AppColors.holoGradient : null,
                    color: sel ? null : AppColors.glassFill(context),
                    borderRadius: BorderRadius.circular(LiquidGlass.radiusPill)),
                child: Center(child: Text(_days[i], textHeightBehavior: const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
                    style: TextStyle(color: sel ? Colors.white : textSecondary,
                    fontSize: 13, height: 1.0, fontWeight: sel ? FontWeight.w700 : FontWeight.w500))),
              ),
            );
          },
        )),
        const SizedBox(height: 10),
        if (!_loading && _rooms.isNotEmpty) Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            const _LegendDot(color: AppColors.green, label: 'Free'),
            const SizedBox(width: 14),
            const _LegendDot(color: AppColors.amber, label: 'Claimed'),
            const SizedBox(width: 14),
            _LegendDot(color: AppColors.textMutedOf(context), label: 'In class'),
          ]),
        ),
        const SizedBox(height: 8),
        Expanded(child: _loading
            ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList())
            : _rooms.isEmpty || _periods.isEmpty
                ? const EmptyState(
                    icon: Icons.meeting_room_outlined,
                    title: 'No routine data yet',
                    subtitle: 'Once a routine is uploaded for this department, '
                        'room availability appears here.')
                : RefreshIndicator(onRefresh: _load, color: AppColors.holoBlue, child: ListView.builder(
                    padding: EdgeInsetsDirectional.fromSTEB(16, 0, 16, 16 + NavInsets.of(context)),
                    itemCount: _rooms.length,
                    // Guarded by the `_rooms.isEmpty || _periods.isEmpty`
                    // ternary above, so .first is safe. Every room's chip
                    // row is built from the SAME shared _periods list for a
                    // given load, so row height is uniform within one load.
                    // The index only drives the stagger fade-in delay.
                    prototypeItem: _buildRoomCard(context, _rooms.first, 0),
                    itemBuilder: (ctx, ri) => _buildRoomCard(ctx, _rooms[ri], ri))),
        ),
      ]),
    );
  }

  Widget _buildRoomCard(BuildContext ctx, Map<String, String> room, int ri) {
    final textPrimary = AppColors.textPrimaryOf(ctx);
    final textSecondary = AppColors.textSecondaryOf(ctx);
    final building = room['building']!, roomNumber = room['room_number']!;
    final freeHere = _freeCountFor(building, roomNumber);
    final totalHere = _periods.length;
    final freeRatio = totalHere == 0 ? 0.0 : freeHere / totalHere;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surfaceOf(ctx), borderRadius: AppDepth.radius(2),
          border: Border.all(color: AppColors.borderOf(ctx), width: 0.6)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 38, height: 38,
              decoration: BoxDecoration(color: AppColors.holoBlue.withValues(alpha: 0.12), borderRadius: AppDepth.radius(1)),
              child: const Icon(Icons.door_front_door_rounded, color: AppColors.holoBlue, size: 19)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$building · $roomNumber', style: AppTextStyles.titleMedium.copyWith(color: textPrimary, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            // A 5px bar: the pill rung is the only radius that reads as
            // intentional at this height — the 8px flush rung would square it off.
            ClipRRect(borderRadius: BorderRadius.circular(LiquidGlass.radiusPill),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: freeRatio),
                  duration: AppMotion.durationOf(ctx, AppMotion.slow),
                  curve: AppMotion.standard,
                  builder: (tCtx, v, _) => LinearProgressIndicator(
                      value: v, minHeight: 5,
                      backgroundColor: AppColors.borderOf(ctx),
                      valueColor: AlwaysStoppedAnimation(
                          v > 0.5 ? AppColors.green : v > 0.2 ? AppColors.amber : AppColors.red)),
                )),
          ])),
          const SizedBox(width: 8),
          Text('$freeHere/$totalHere free', textHeightBehavior: const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
              style: TextStyle(color: textSecondary, fontSize: 11, height: 1.0, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: _periods.map((period) {
          final occ = _occupant(building, roomNumber, period);
          final claim = _claim(building, roomNumber, period);
          final label = '${AppFormatters.time12(period.start)}–${AppFormatters.time12(period.end)}';
          if (occ != null) {
            return _PeriodChip(label: label, sub: occ.subjectCode ?? occ.subject,
                icon: Icons.school_rounded, color: AppColors.textMutedOf(ctx));
          }
          if (claim != null) {
            final claimant = (claim['profiles'] as Map?)?['full_name'] as String? ?? 'Someone';
            return _PeriodChip(label: label, sub: 'Claimed by $claimant',
                icon: Icons.lock_clock_rounded, color: AppColors.amber);
          }
          return _PeriodChip(label: label, sub: 'Free — tap to claim',
              icon: Icons.add_circle_outline_rounded, color: AppColors.green,
              onTap: () => _request(building, roomNumber, period));
        }).toList()),
      ]),
    ).animate(delay: AppMotion.staggerFor(ctx, ri))
        .fadeIn(duration: AppMotion.durationOf(ctx, AppMotion.base), curve: AppMotion.standard)
        .slideY(begin: 0.06, curve: AppMotion.standard);
  }
}

class _LegendDot extends StatelessWidget {
  final Color color; final String label;
  const _LegendDot({required this.color, required this.label});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 5),
    Text(label, style: TextStyle(color: AppColors.textSecondaryOf(context), fontSize: 11)),
  ]);
}

/// A period slot. The free variant is the primary tappable thing on this
/// screen, so it is the one element here that carries the full press treatment
/// (Law 4): the scale answers inside one frame, and the haptic waits for the
/// claim to actually land — it fires in [_RoomAvailabilityScreenState._request]
/// on the write's success path, not here on touch.
class _PeriodChip extends StatefulWidget {
  final String label, sub; final Color color; final IconData icon;
  final VoidCallback? onTap;
  const _PeriodChip({required this.label, required this.sub, required this.color, required this.icon, this.onTap});
  @override
  State<_PeriodChip> createState() => _PeriodChipState();
}

class _PeriodChipState extends State<_PeriodChip> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final tappable = widget.onTap != null;
    final color = widget.color;
    final chip = Container(
      // Was 156px, sized for 24H labels ("08:30–10:00"). 12H labels
      // ("8:30 AM–10:00 AM") run noticeably longer -- widened to fit without
      // clipping/ellipsis, and the label now wraps in a Flexible so a really
      // long label degrades gracefully instead of overflowing the chip.
      width: 178,
      // Vertical padding was 9, which left the tappable variant ~45dp tall,
      // under the 48dp floor. AppSpace.md clears it and is on the scale.
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.md),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: AppDepth.radius(1),
          border: Border.all(color: color.withValues(alpha: tappable ? 0.5 : 0.3), width: tappable ? 1.1 : 0.8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(widget.icon, size: 12, color: color),
          const SizedBox(width: 4),
          Flexible(child: Text(widget.label, textHeightBehavior: const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
              style: TextStyle(color: color, fontSize: 10.5, height: 1.0, fontWeight: FontWeight.w700),
              maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 3),
        Text(widget.sub, style: TextStyle(color: AppColors.textSecondaryOf(context), fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
    );
    if (!tappable) return chip;
    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? AppMotion.pressScale : 1.0,
        duration: AppMotion.durationOf(context, AppMotion.pressDuration),
        curve: AppMotion.standard,
        child: chip,
      ),
    );
  }
}
