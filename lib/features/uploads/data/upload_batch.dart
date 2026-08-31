import '../../../config/supabase_config.dart';

/// One import made through the app, and the record it leaves behind.
///
/// Before this existed the app could import a routine, a seat plan or a
/// transport sheet and leave no trace of who did it, when, from which file, or
/// what it wrote. `routine_uploads` recorded a little of that for routines
/// only, held one row, and named nothing it had written — so nothing could be
/// undone except by hand, against the wrong rows, from memory.
///
/// The lifecycle is deliberately two-phase. The batch is OPENED before the
/// import runs so every row can carry its id as it is written; it is CLOSED
/// afterwards, at which point the server COUNTS the stamped rows rather than
/// believing the client's tally. A batch that is opened and never closed stays
/// `pending`, and the history shows it as an import that did not finish —
/// which is worth seeing, not worth hiding.
class UploadBatch {
  final String id;
  final String kind;
  final String status;
  final String? sourceFile;
  final String? department;
  final String? termId;
  final String? note;
  final int rowCount;
  final Map<String, dynamic> summary;
  final String? uploader;
  final String? reverter;
  final DateTime uploadedAt;
  final DateTime? backupGeneratedAt;
  final DateTime? revertedAt;

  const UploadBatch({
    required this.id,
    required this.kind,
    required this.status,
    required this.rowCount,
    required this.uploadedAt,
    this.sourceFile,
    this.department,
    this.termId,
    this.note,
    this.summary = const {},
    this.uploader,
    this.reverter,
    this.backupGeneratedAt,
    this.revertedAt,
  });

  static DateTime? _at(Object? v) =>
      v == null ? null : DateTime.tryParse('$v')?.toLocal();

  factory UploadBatch.fromJson(Map<String, dynamic> j) => UploadBatch(
        id: '${j['id']}',
        kind: '${j['kind']}',
        status: '${j['status'] ?? 'applied'}',
        sourceFile: j['source_file'] as String?,
        department: j['department'] as String?,
        termId: j['term_id'] as String?,
        note: j['note'] as String?,
        rowCount: (j['row_count'] as num?)?.toInt() ?? 0,
        summary: (j['summary'] as Map?)?.cast<String, dynamic>() ?? const {},
        uploader: j['uploader'] as String?,
        reverter: j['reverter'] as String?,
        uploadedAt: _at(j['uploaded_at']) ?? DateTime.now(),
        backupGeneratedAt: _at(j['backup_generated_at']),
        revertedAt: _at(j['reverted_at']),
      );

  bool get isReverted => status == 'reverted';
  bool get isPending => status == 'pending';

  /// Whether a backup PDF has been produced for this batch. Named for what is
  /// actually known: the server can see that a file was generated and stored,
  /// never that a person downloaded it.
  bool get hasBackup => backupGeneratedAt != null;

  /// Removing it is only offered once a backup exists and nothing has been
  /// removed already.
  bool get canRevert => !isReverted && rowCount > 0;

  static String labelFor(String kind) => switch (kind) {
        'class_routine' => 'Class Routine',
        'exam_routine' => 'Exam Routine',
        'exam_seat_plan' => 'Exam Seat Plan',
        'transport' => 'Transport Routes',
        'notice' => 'University Notice',
        _ => kind,
      };

  String get kindLabel => labelFor(kind);
}

/// Which upload kinds a given person may actually use, in the order the hub
/// lists them.
///
/// MIRRORS THE RLS, deliberately, rather than being a second opinion about it.
/// A screen that offers an importer the database will refuse is worse than one
/// that hides it: the person picks a file, waits, and gets a permission error
/// with nothing to do about it.
///
///  - `schedule_slots` admits admin / teacher / dept_admin / super_admin or a
///    `routine:upload` grant — and NOT exam_controller, so an exam controller
///    does not get the class routine.
///  - `exams` and `exam_terms` admit the admin tier INCLUDING exam_controller,
///    or `routine:upload` / `exam_seat:upload`.
///  - `exam_room_allocations` and `notices` likewise.
///  - transport is its own `transport:upload` grant.
List<String> uploadKindsFor({
  required String? role,
  required Set<String> grants,
}) {
  const fullAdmin = {'admin', 'dept_admin', 'super_admin'};
  final isFullAdmin = fullAdmin.contains(role);
  final isExamController = role == 'exam_controller';
  bool granted(String r, String a) => grants.contains('$r:$a');

  return [
    if (isFullAdmin || granted('routine', 'upload')) 'class_routine',
    if (isFullAdmin || isExamController || granted('routine', 'upload'))
      'exam_routine',
    if (isFullAdmin || granted('transport', 'upload')) 'transport',
    if (isFullAdmin || isExamController || granted('exam_seat', 'upload'))
      'exam_seat_plan',
    if (isFullAdmin || isExamController || granted('notice', 'publish'))
      'notice',
  ];
}

/// Batches matching an optional kind and department, both AND'd together —
/// the same predicate the Uploads Hub's bulk-select filter chips apply.
/// Pulled out as a pure function, the same reason `uploadKindsFor` is one:
/// so the filter can be pinned by a test without building the screen.
List<UploadBatch> filterUploadBatches(
  List<UploadBatch> history, {
  String? kind,
  String? department,
}) =>
    history.where((b) {
      if (kind != null && b.kind != kind) return false;
      if (department != null && (b.department ?? '') != department) return false;
      return true;
    }).toList();

/// Distinct, non-blank departments actually present in the ledger, sorted —
/// what the Hub offers as department filter chips. Blank/null departments
/// (uploads made before a kind captured one, or ones that never do) are
/// deliberately excluded from the chip list: an "All departments" chip
/// already covers them, and a chip labelled with nothing is not a filter
/// anyone can tap.
List<String> departmentsInBatches(List<UploadBatch> history) => history
    .map((b) => b.department)
    .whereType<String>()
    .map((d) => d.trim())
    .where((d) => d.isNotEmpty)
    .toSet()
    .toList()
  ..sort();

/// The client half of the upload record. Every call is a SECURITY DEFINER
/// function: `upload_batches` has a read policy and deliberately no write
/// policy, so there is no way to write one except through these.
class UploadBatchService {
  UploadBatchService._();

  /// Opens a batch. Call BEFORE writing anything, and stamp the returned id
  /// onto every row the import inserts.
  static Future<String> open({
    required String kind,
    String? sourceFile,
    String? department,
    String? termId,
    String? note,
  }) async {
    final res = await SupabaseConfig.client.rpc('record_upload_batch', params: {
      'p_kind': kind,
      'p_source_file': sourceFile,
      'p_department': department,
      'p_term_id': termId,
      'p_note': note,
    });
    return '$res';
  }

  /// Closes a batch. The row count in the result is the server's own count of
  /// stamped rows, so it is the number that actually landed.
  static Future<UploadBatch> finalize(
    String id, {
    Map<String, dynamic> summary = const {},
  }) async {
    final res = await SupabaseConfig.client.rpc('finalize_upload_batch',
        params: {'p_id': id, 'p_summary': summary});
    return UploadBatch.fromJson((res as Map).cast<String, dynamic>());
  }

  static Future<List<UploadBatch>> list({int limit = 50}) async {
    final res = await SupabaseConfig.client
        .rpc('list_upload_batches', params: {'p_limit': limit});
    return ((res as List?) ?? const [])
        .map((r) => UploadBatch.fromJson((r as Map).cast<String, dynamic>()))
        .toList();
  }

  /// Every row the batch wrote, across all six tables, for the backup PDF.
  static Future<Map<String, dynamic>> contents(String id) async {
    final res = await SupabaseConfig.client
        .rpc('upload_batch_contents', params: {'p_id': id});
    return (res as Map).cast<String, dynamic>();
  }

  static Future<UploadBatch> markBackup(String id, String path) async {
    final res = await SupabaseConfig.client.rpc('mark_upload_backup_generated',
        params: {'p_id': id, 'p_path': path});
    return UploadBatch.fromJson((res as Map).cast<String, dynamic>());
  }

  /// Deletes exactly the rows this batch wrote. The server refuses until a
  /// backup exists, so this throws a readable message rather than silently
  /// doing nothing when the interlock has not been satisfied.
  static Future<UploadBatch> revert(String id) async {
    final res = await SupabaseConfig.client
        .rpc('revert_upload_batch', params: {'p_id': id});
    return UploadBatch.fromJson((res as Map).cast<String, dynamic>());
  }
}
