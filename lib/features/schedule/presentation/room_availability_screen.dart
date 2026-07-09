import 'package:flutter/material.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../shell/presentation/top_app_bar.dart';
import '../data/models/class_slot.dart';
import '../data/repositories/schedule_repository.dart';

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
      if (mounted) setState(() {
        _department = department;
        _rooms = results[0] as List<Map<String, String>>;
        _periods = results[1] as List<({String start, String end})>;
        _daySlots = results[2] as List<ClassSlot>;
        _claims = results[3] as List<Map<String, dynamic>>;
        _loading = false;
      });
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

  Future<void> _request(String building, String room, ({String start, String end}) period) async {
    final purposeCtrl = TextEditingController();
    final purpose = await showModalBottomSheet<String>(
      context: context, isScrollControlled: true,
      backgroundColor: AppColors.surfaceOf(context),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(sheetCtx).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Claim $building-$room', style: AppTextStyles.headlineLarge.copyWith(color: AppColors.textPrimaryOf(sheetCtx))),
          const SizedBox(height: 4),
          Text('${period.start}–${period.end}, ${_days[_day]} — this claim is visible to others and auto-expires in 24 hours.',
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(sheetCtx))),
          const SizedBox(height: 16),
          TextField(controller: purposeCtrl, style: TextStyle(color: AppColors.textPrimaryOf(sheetCtx)),
              decoration: const InputDecoration(hintText: 'Purpose (e.g. Makeup class for CSE221)')),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: () => Navigator.pop(sheetCtx, purposeCtrl.text.trim()),
              child: const Text('Claim this room'))),
        ]),
      ),
    );
    if (purpose == null || purpose.isEmpty || !mounted) return;
    try {
      await _repo.requestEmptyRoom(
        department: _department!, building: building, roomNumber: room,
        dayOfWeek: _day, startTime: '${period.start}:00', endTime: '${period.end}:00', purpose: purpose,
      );
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Room claimed ✓'), backgroundColor: AppColors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AfosAppBar(title: 'Room Availability'),
      body: Column(children: [
        SizedBox(height: 44, child: ListView.builder(
          scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          itemCount: _days.length,
          itemBuilder: (ctx, i) {
            final sel = _day == i;
            return GestureDetector(
              onTap: () { setState(() => _day = i); _load(); },
              child: Container(margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                      gradient: sel ? AppColors.holoGradient : null,
                      color: sel ? null : AppColors.glassFill(context), borderRadius: BorderRadius.circular(20)),
                  child: Text(_days[i], style: TextStyle(color: sel ? Colors.white : textSecondary, fontSize: 13))),
            );
          },
        )),
        Expanded(child: _loading
            ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList())
            : _rooms.isEmpty || _periods.isEmpty
                ? Center(child: Text('No routine data yet for this department', style: TextStyle(color: textSecondary)))
                : RefreshIndicator(onRefresh: _load, child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _rooms.length,
                    itemBuilder: (ctx, ri) {
                      final room = _rooms[ri];
                      final building = room['building']!, roomNumber = room['room_number']!;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.borderOf(context), width: 0.5)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('$building-$roomNumber', style: AppTextStyles.titleMedium.copyWith(color: textPrimary, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          Wrap(spacing: 8, runSpacing: 8, children: _periods.map((period) {
                            final occ = _occupant(building, roomNumber, period);
                            final claim = _claim(building, roomNumber, period);
                            final label = '${period.start}–${period.end}';
                            if (occ != null) {
                              return _PeriodChip(label: label, sub: occ.subjectCode ?? occ.subject, color: AppColors.textMutedOf(context));
                            }
                            if (claim != null) {
                              final claimant = (claim['profiles'] as Map?)?['full_name'] as String? ?? 'Someone';
                              return _PeriodChip(label: label, sub: 'Claimed by $claimant', color: AppColors.amber);
                            }
                            return GestureDetector(
                              onTap: () => _request(building, roomNumber, period),
                              child: _PeriodChip(label: label, sub: 'Free — tap to claim', color: AppColors.green),
                            );
                          }).toList()),
                        ]),
                      );
                    })),
        ),
      ]),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  final String label, sub; final Color color;
  const _PeriodChip({required this.label, required this.sub, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    width: 150,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      const SizedBox(height: 2),
      Text(sub, style: TextStyle(color: AppColors.textSecondaryOf(context), fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
    ]),
  );
}
