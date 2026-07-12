import '../../../../config/supabase_config.dart';
import '../../../../core/utils/offline_cache.dart';
import '../models/class_slot.dart';

class ScheduleRepository {
  final _client = SupabaseConfig.client;

  /// Stream schedule slots, filter by dept+semester+day client-side.
  /// Supabase stream builder supports only one .eq() — we filter the rest
  /// locally. Cached so this (and the two variants below) still render the
  /// last-known routine while offline instead of hanging on the loading
  /// shimmer forever, since a live .stream() never emits with no connection.
  Stream<List<ClassSlot>> watchSchedule(String dept, int semester, int day) {
    return cachedListStream(
      cacheKey: 'schedule_slots_${dept}_${semester}_$day',
      liveStream: () => _client
          .from('schedule_slots')
          .stream(primaryKey: ['id'])
          .eq('department', dept)
          .order('start_time', ascending: true)
          .map((list) => list
              .where((s) =>
                  s['semester'] == semester &&
                  s['day_of_week'] == day)
              .map((s) => Map<String, dynamic>.from(s))
              .toList()),
    ).map((rows) => rows.map((s) => ClassSlot.fromJson(s)).toList());
  }

  /// Stream only the classes belonging to this student's own batch+section
  /// (from PDF-imported class routine data), so they don't see every other
  /// section's classes in the department.
  ///
  /// Filters the SERVER-side stream by `batch`, not `department` — Supabase's
  /// realtime .stream() only supports a single .eq() (confirmed by reading
  /// the SDK source: SupabaseStreamFilterBuilder holds one `_streamFilter`,
  /// each further .eq() call overwrites rather than AND-combines the
  /// previous one). Filtering by department alone pulled the WHOLE
  /// department's rows over the wire before narrowing client-side — with
  /// PostgREST's default 1,000-row response cap, a department once it grows
  /// past that (CSE already has 1,854) silently truncates, sorted by
  /// start_time ascending, so LATER time slots across the whole department
  /// are the first to go missing. Confirmed live: a real batch's own
  /// Monday lab (a 02:30 slot) never reached the student's device even
  /// though the row was correctly in the database. `batch` alone is a far
  /// narrower scope (one intake's rows across every department, not one
  /// department's rows across every intake) and stays well under the cap.
  Stream<List<ClassSlot>> watchMyClassesAsStudent(String dept, String batch, String section, int day) {
    return cachedListStream(
      cacheKey: 'schedule_slots_student_${dept}_${batch}_${section}_$day',
      liveStream: () => _client
          .from('schedule_slots')
          .stream(primaryKey: ['id'])
          .eq('batch', batch)
          .order('start_time', ascending: true)
          .map((list) => list
              .where((s) =>
                  s['day_of_week'] == day &&
                  (s['department'] as String?)?.toLowerCase() == dept.toLowerCase() &&
                  (s['section'] as String?)?.toLowerCase() == section.toLowerCase())
              .map((s) => Map<String, dynamic>.from(s))
              .toList()),
    ).map((rows) => rows.map((s) => ClassSlot.fromJson(s)).toList());
  }

  /// Stream only the classes taught by this teacher (matched by the
  /// initials they set in Settings, as printed in the class routine PDF).
  Stream<List<ClassSlot>> watchMyClassesAsTeacher(String teacherInitial, int day) {
    return cachedListStream(
      cacheKey: 'schedule_slots_teacher_${teacherInitial}_$day',
      liveStream: () => _client
          .from('schedule_slots')
          .stream(primaryKey: ['id'])
          .eq('teacher_initial', teacherInitial)
          .order('start_time', ascending: true)
          .map((list) => list
              .where((s) => s['day_of_week'] == day)
              .map((s) => Map<String, dynamic>.from(s))
              .toList()),
    ).map((rows) => rows.map((s) => ClassSlot.fromJson(s)).toList());
  }

  Future<List<Map<String,dynamic>>> getExams(String dept, int semester) => cachedListFetch(
    cacheKey: 'exams_${dept}_$semester',
    liveFetch: () async {
      final res = await _client
          .from('exams')
          .select()
          .eq('department', dept)
          .eq('semester', semester)
          .order('exam_date', ascending: true) as List;
      return res.cast<Map<String, dynamic>>();
    },
  );

  /// Exams filtered to this student's own batch, or this teacher's own
  /// initials aren't tracked on exams — teachers see the full department
  /// exam routine since they may invigilate/teach across batches.
  Future<List<Map<String,dynamic>>> getMyExams({required String dept, String? batch}) => cachedListFetch(
    cacheKey: 'exams_my_${dept}_${batch ?? 'all'}',
    liveFetch: () async {
      var q = _client.from('exams').select().eq('department', dept);
      if (batch != null && batch.isNotEmpty) q = q.eq('batch', batch);
      final res = await q.order('exam_date', ascending: true) as List;
      return res.cast<Map<String, dynamic>>();
    },
  );

  /// Maps a teacher's routine-sheet initials (e.g. "FNN") to their real
  /// name and profile photo, so a class card can show who's actually
  /// teaching it instead of just the bare initials the PDF prints.
  Future<Map<String, ({String fullName, String? avatarUrl})>> getTeacherDirectory() async {
    final res = await _client.from('profiles')
        .select('full_name, avatar_url, teacher_initial')
        .not('teacher_initial', 'is', null) as List;
    final map = <String, ({String fullName, String? avatarUrl})>{};
    for (final row in res) {
      final initial = (row['teacher_initial'] as String?)?.trim();
      if (initial == null || initial.isEmpty) continue;
      map[initial.toLowerCase()] = (
        fullName: row['full_name'] as String? ?? initial,
        avatarUrl: row['avatar_url'] as String?,
      );
    }
    return map;
  }

  /// Resolves the Class Representative for a specific department+batch+
  /// section — lets a teacher message the CR directly from a class card
  /// ("if course match teacher can directly communicate ... by CR of that
  /// section and batch"), without needing the still-empty courses/
  /// course_offerings tables (schedule_slots already has real batch/
  /// section/department data, which is what this reuses).
  Future<Map<String, dynamic>?> findSectionCr(String departmentCode, String batch, String section) async {
    final res = await _client.rpc('find_section_cr', params: {
      'p_department_code': departmentCode, 'p_batch': batch, 'p_section': section,
    }) as List;
    return res.isNotEmpty ? res.first as Map<String, dynamic> : null;
  }

  /// Finds any class (retake included) by course code — how a student or
  /// teacher locates a retake session, which isn't in their normal
  /// batch/section view at all. Row counts per department are small enough
  /// (low hundreds) that a plain ilike scan doesn't need a trigram index.
  Future<List<ClassSlot>> searchByCourseCode(String code, {required String department}) async {
    if (code.trim().isEmpty) return [];
    final res = await _client.from('schedule_slots').select()
        .ilike('subject_code', '%${code.trim()}%').eq('department', department)
        .order('day_of_week', ascending: true).order('start_time', ascending: true) as List;
    return res.map((s) => ClassSlot.fromJson(Map<String, dynamic>.from(s))).toList();
  }

  /// Best-effort "here's your other lab half" lookup for a J1/J2-style
  /// split lab section — computed at display time (not parse time) so it
  /// stays correct even if only one subgroup's row changes on a later
  /// re-upload.
  Future<ClassSlot?> findLabCounterpart(ClassSlot slot) async {
    if (slot.labSubgroup == null || slot.subjectCode == null || slot.batch == null || slot.section == null) return null;
    final otherSubgroup = slot.labSubgroup == 1 ? 2 : 1;
    final res = await _client.from('schedule_slots').select()
        .eq('subject_code', slot.subjectCode as Object)
        .eq('batch', slot.batch as Object)
        .eq('section', slot.section as Object)
        .eq('department', slot.department)
        .eq('lab_subgroup', otherSubgroup)
        .limit(1) as List;
    return res.isEmpty ? null : ClassSlot.fromJson(Map<String, dynamic>.from(res.first));
  }

  /// "Add this retake course to my schedule" — a manually-pinned extra slot
  /// on top of the student's/teacher's regular batch/section-or-initial view.
  Future<void> pinSlot(String scheduleSlotId) async {
    final uid = SupabaseConfig.uid;
    if (uid == null) return;
    await _client.from('user_pinned_slots').upsert({'user_id': uid, 'schedule_slot_id': scheduleSlotId});
  }

  Future<void> unpinSlot(String scheduleSlotId) async {
    final uid = SupabaseConfig.uid;
    if (uid == null) return;
    await _client.from('user_pinned_slots').delete()
        .eq('user_id', uid).eq('schedule_slot_id', scheduleSlotId);
  }

  /// Pages through every schedule_slots row for a department, `select`ing
  /// only the given columns — see fetchDistinctRooms's comment for why this
  /// can't be a single unbounded .select().
  Future<List<Map<String, dynamic>>> _fetchAllRows(String columns, String department) async {
    final all = <Map<String, dynamic>>[];
    const pageSize = 1000;
    for (var from = 0; ; from += pageSize) {
      final page = await _client.from('schedule_slots').select(columns)
          .eq('department', department).range(from, from + pageSize - 1) as List;
      all.addAll(page.cast<Map<String, dynamic>>());
      if (page.length < pageSize) break;
    }
    return all;
  }

  /// Every distinct (building, room_number) in this department's routine —
  /// the room axis for the empty-room-availability view.
  ///
  /// Paginates via .range() rather than one unbounded .select() — PostgREST
  /// caps a single response at 1,000 rows by default, and a real
  /// department's routine (CSE alone is 1,854 rows) exceeds that, which
  /// silently dropped every room that only appeared in rows past the cutoff
  /// (same root cause as the routine-slot fetch fix in
  /// watchMyClassesAsStudent above).
  Future<List<Map<String, String>>> fetchDistinctRooms(String department) async {
    final res = await _fetchAllRows('building, room_number', department);
    final seen = <String>{};
    final rooms = <Map<String, String>>[];
    for (final r in res.cast<Map<String, dynamic>>()) {
      final building = r['building'] as String? ?? '';
      final roomNumber = r['room_number'] as String? ?? '';
      final key = '$building|$roomNumber';
      if (building.isEmpty || roomNumber.isEmpty || !seen.add(key)) continue;
      rooms.add({'building': building, 'room_number': roomNumber});
    }
    rooms.sort((a, b) => '${a['building']}${a['room_number']}'.compareTo('${b['building']}${b['room_number']}'));
    return rooms;
  }

  /// Every distinct time period in use across this department's routine —
  /// the period axis for the empty-room-availability view (self-adjusting
  /// if the university's period times ever change, rather than a hardcoded
  /// constant).
  Future<List<({String start, String end})>> fetchDistinctPeriods(String department) async {
    final res = await _fetchAllRows('start_time, end_time', department);
    final seen = <String>{};
    final periods = <({String start, String end})>[];
    for (final r in res.cast<Map<String, dynamic>>()) {
      final start = r['start_time'] as String? ?? '';
      final end = r['end_time'] as String? ?? '';
      final key = '$start|$end';
      if (start.isEmpty || !seen.add(key)) continue;
      periods.add((start: start, end: end));
    }
    periods.sort((a, b) => a.start.compareTo(b.start));
    return periods;
  }

  Future<List<ClassSlot>> fetchSlotsForDay(String department, int dayOfWeek) async {
    final res = await _client.from('schedule_slots').select()
        .eq('department', department).eq('day_of_week', dayOfWeek) as List;
    return res.map((s) => ClassSlot.fromJson(Map<String, dynamic>.from(s))).toList();
  }

  Future<List<Map<String, dynamic>>> fetchEmptyRoomRequests(String department, int dayOfWeek) async {
    final res = await _client.from('empty_room_requests').select('*, profiles!requester_id(full_name)')
        .eq('department', department).eq('day_of_week', dayOfWeek) as List;
    return res.cast<Map<String, dynamic>>();
  }

  Future<void> requestEmptyRoom({
    required String department, required String building, required String roomNumber,
    required int dayOfWeek, required String startTime, required String endTime, required String purpose,
  }) async {
    final uid = SupabaseConfig.uid;
    if (uid == null) return;
    await _client.from('empty_room_requests').insert({
      'requester_id': uid, 'department': department, 'building': building, 'room_number': roomNumber,
      'day_of_week': dayOfWeek, 'start_time': startTime, 'end_time': endTime, 'purpose': purpose,
    });
  }

  /// The PDF's own printed header (Version / Effective From / Prepared By),
  /// captured by parse-routine at upload time — one row per department+type.
  /// Null if nothing's ever been uploaded yet, or the uploaded file didn't
  /// print this metadata in a recognizable form.
  Future<Map<String, dynamic>?> fetchRoutineHeader(String department, String routineType) => cachedMapFetch(
    cacheKey: 'routine_header_${department}_$routineType',
    liveFetch: () async {
      final res = await _client.from('routine_uploads').select()
          .eq('department', department).eq('routine_type', routineType).maybeSingle();
      if (res == null) throw StateError('no routine header yet');
      return res;
    },
  );

  Stream<List<ClassSlot>> watchMyPinnedSlots() {
    final uid = SupabaseConfig.uid;
    if (uid == null) return Stream.value(const []);
    return cachedListStream(
      cacheKey: 'user_pinned_slots_$uid',
      liveStream: () => _client.from('user_pinned_slots')
          .stream(primaryKey: ['id'])
          .eq('user_id', uid)
          .map((rows) => rows.map((r) => Map<String, dynamic>.from(r)).toList()),
    ).asyncMap((rows) async {
      if (rows.isEmpty) return <ClassSlot>[];
      final ids = rows.map((r) => r['schedule_slot_id'] as String).toList();
      final slots = await _client.from('schedule_slots').select().inFilter('id', ids) as List;
      return slots.map((s) => ClassSlot.fromJson(Map<String, dynamic>.from(s))).toList();
    });
  }
}
