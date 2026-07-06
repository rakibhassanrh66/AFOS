import 'package:flutter/material.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_icons.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/afos_text_field.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../../shared/widgets/surface_card.dart';
import '../../notifications/data/repositories/notification_service.dart';
import '../../shell/presentation/top_app_bar.dart';

/// admin/dept_admin/super_admin/exam_controller: bulk-generate exam seat
/// assignments for an exam's matched students (department+batch+section,
/// resolved server-side via list_exam_candidates RPC — exam_controller has
/// no direct `students` table permission, unlike the other three roles, so
/// a narrow RPC was added rather than widening that grant).
class ManageExamSeatsScreen extends StatefulWidget {
  const ManageExamSeatsScreen({super.key});
  @override State<ManageExamSeatsScreen> createState() => _ManageExamSeatsScreenState();
}

class _ManageExamSeatsScreenState extends State<ManageExamSeatsScreen> {
  List<Map<String, dynamic>> _exams = [];
  Map<String, dynamic>? _selectedExam;
  int _existingCount = 0;
  bool _loading = true, _generating = false, _clearing = false;

  final _buildingCtrl = TextEditingController();
  final _floorCtrl = TextEditingController();
  final _roomsCtrl = TextEditingController();
  final _seatsPerRoomCtrl = TextEditingController(text: '30');
  final _seatsPerRowCtrl = TextEditingController(text: '5');

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() {
    _buildingCtrl.dispose(); _floorCtrl.dispose(); _roomsCtrl.dispose();
    _seatsPerRoomCtrl.dispose(); _seatsPerRowCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await SupabaseConfig.client.from('exams').select()
          .order('exam_date', ascending: true) as List;
      if (mounted) setState(() { _exams = res.cast(); _loading = false; });
      if (_exams.isNotEmpty) await _selectExam(_exams.first);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _selectExam(Map<String, dynamic> exam) async {
    setState(() { _selectedExam = exam; _existingCount = 0; });
    try {
      final res = await SupabaseConfig.client.from('exam_seat_assignments')
          .select('id').eq('exam_id', exam['id']) as List;
      if (mounted) setState(() => _existingCount = res.length);
    } catch (_) {}
  }

  Future<void> _generate() async {
    final exam = _selectedExam;
    if (exam == null) return;
    final rooms = _roomsCtrl.text.split(',').map((r) => r.trim()).where((r) => r.isNotEmpty).toList();
    final seatsPerRoom = int.tryParse(_seatsPerRoomCtrl.text.trim()) ?? 0;
    final seatsPerRow = int.tryParse(_seatsPerRowCtrl.text.trim()) ?? 0;
    if (rooms.isEmpty || seatsPerRoom <= 0 || seatsPerRow <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Enter at least one room, seats per room, and seats per row.'),
          backgroundColor: AppColors.red));
      return;
    }
    setState(() => _generating = true);
    try {
      final candidates = await SupabaseConfig.client
          .rpc('list_exam_candidates', params: {'p_exam_id': exam['id']}) as List;
      if (candidates.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text("No students match this exam's department/batch/section."),
              backgroundColor: AppColors.amber));
        }
        if (mounted) setState(() => _generating = false);
        return;
      }
      final capacity = rooms.length * seatsPerRoom;
      if (candidates.length > capacity) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('${candidates.length} students but only $capacity seats — add more rooms or increase seats per room.'),
              backgroundColor: AppColors.red));
        }
        if (mounted) setState(() => _generating = false);
        return;
      }

      // Replace, don't append — re-generating (e.g. after fixing room
      // config) shouldn't leave stale duplicate rows from a prior attempt.
      await SupabaseConfig.client.from('exam_seat_assignments').delete().eq('exam_id', exam['id']);

      final floor = int.tryParse(_floorCtrl.text.trim());
      final rows = <Map<String, dynamic>>[];
      for (var i = 0; i < candidates.length; i++) {
        final c = candidates[i] as Map<String, dynamic>;
        final room = rooms[i ~/ seatsPerRoom];
        final posInRoom = i % seatsPerRoom;
        final rowLabel = String.fromCharCode(65 + (posInRoom ~/ seatsPerRow));
        final seatInRow = posInRoom % seatsPerRow + 1;
        rows.add({
          'exam_id': exam['id'], 'student_id': c['profile_id'],
          'room_number': room, 'building': _buildingCtrl.text.trim(),
          if (floor != null) 'floor_number': floor,
          'row_label': rowLabel, 'seat_number': '$rowLabel$seatInRow',
          'is_retake': exam['is_retake'] ?? false,
        });
      }
      await SupabaseConfig.client.from('exam_seat_assignments').insert(rows);

      // Direct notifications are capped at 20 recipients per call — chunk
      // rather than broadcasting (there's no department+batch+section
      // broadcast filter, only department alone, which would over-notify
      // students in the same department but a different batch/section).
      final studentIds = candidates.map((c) => (c as Map)['profile_id'] as String).toList();
      for (var i = 0; i < studentIds.length; i += 20) {
        await NotificationService.sendToUsers(
          userIds: studentIds.sublist(i, i + 20 > studentIds.length ? studentIds.length : i + 20),
          title: 'Exam seat plan published',
          message: '${exam['subject'] ?? 'Your exam'} seating has been assigned — check Exam Seat Plan.',
          category: 'exam', deepLink: '/exam-seat',
        );
      }

      await _selectExam(exam);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Assigned seats for ${candidates.length} students ✓'), backgroundColor: AppColors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
    if (mounted) setState(() => _generating = false);
  }

  Future<void> _clear() async {
    final exam = _selectedExam;
    if (exam == null) return;
    final count = _existingCount;
    final confirm = await showDialog<bool>(
        context: context,
        builder: (dCtx) => AlertDialog(
              backgroundColor: AppColors.surfaceOf(dCtx),
              title: Text('Clear seat assignments?', style: TextStyle(color: AppColors.textPrimaryOf(dCtx))),
              content: Text('This removes all $count existing seat assignments for this exam.',
                  style: TextStyle(color: AppColors.textSecondaryOf(dCtx))),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Cancel')),
                TextButton(onPressed: () => Navigator.pop(dCtx, true), child: const Text('Clear', style: TextStyle(color: AppColors.red))),
              ],
            ));
    if (confirm != true) return;
    setState(() => _clearing = true);
    try {
      await SupabaseConfig.client.from('exam_seat_assignments').delete().eq('exam_id', exam['id']);
      await _selectExam(exam);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
    if (mounted) setState(() => _clearing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AfosAppBar(title: 'Manage Exam Seats'),
      body: _loading
          ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList())
          : _exams.isEmpty
              ? EmptyState(icon: AppIcons.examSeat, title: 'No exams yet',
                  subtitle: 'Upload an exam routine first from Upload Routine/Transport')
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Exam', style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimaryOf(context))),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<Map<String, dynamic>>(
                      initialValue: _selectedExam,
                      isExpanded: true,
                      decoration: InputDecoration(
                          filled: true, fillColor: AppColors.surfaceOf(context),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: AppColors.borderOf(context)))),
                      dropdownColor: AppColors.surfaceOf(context),
                      style: TextStyle(color: AppColors.textPrimaryOf(context)),
                      items: _exams.map((e) => DropdownMenuItem(
                          value: e,
                          child: Text('${e['subject'] ?? '?'} · ${e['batch'] ?? '?'}-${e['section'] ?? '?'} · ${e['exam_date'] ?? ''}',
                              overflow: TextOverflow.ellipsis))).toList(),
                      onChanged: (v) { if (v != null) _selectExam(v); },
                    ),
                    const SizedBox(height: 12),
                    if (_selectedExam != null)
                      SurfaceCard(child: Row(children: [
                        Icon(AppIcons.examSeat, color: AppColors.gold, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(
                            _existingCount > 0
                                ? '$_existingCount students already assigned for this exam'
                                : 'No seats assigned yet for this exam',
                            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context)))),
                        if (_existingCount > 0)
                          TextButton(onPressed: _clearing ? null : _clear,
                              child: Text(_clearing ? '...' : 'Clear', style: const TextStyle(color: AppColors.red))),
                      ])),
                    const SizedBox(height: 20),
                    Text('Room Setup', style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimaryOf(context))),
                    const SizedBox(height: 8),
                    AfosTextField(hint: 'Building (e.g. Main Building)', controller: _buildingCtrl),
                    const SizedBox(height: 10),
                    AfosTextField(hint: 'Floor number (optional)', controller: _floorCtrl, keyboardType: TextInputType.number),
                    const SizedBox(height: 10),
                    AfosTextField(hint: 'Room numbers, comma-separated (e.g. 301, 302, 303)', controller: _roomsCtrl),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: AfosTextField(hint: 'Seats per room', controller: _seatsPerRoomCtrl, keyboardType: TextInputType.number)),
                      const SizedBox(width: 10),
                      Expanded(child: AfosTextField(hint: 'Seats per row', controller: _seatsPerRowCtrl, keyboardType: TextInputType.number)),
                    ]),
                    const SizedBox(height: 20),
                    AfosButton(label: 'Generate & Assign Seats', loading: _generating, onTap: _generate),
                    const SizedBox(height: 8),
                    Text("Assigns every student in this exam's department/batch/section to sequential seats across the given rooms, and notifies them.",
                        style: AppTextStyles.labelSmall.copyWith(color: AppColors.textMutedOf(context))),
                    const SizedBox(height: 24),
                  ]),
                ),
    );
  }
}
