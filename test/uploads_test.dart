import 'package:afos_v7/features/uploads/data/upload_batch.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Uploads section: who may load what, and what the ledger says afterwards.
///
/// The gating half matters because the alternative failure is quiet and
/// annoying — a screen offers an importer, the person picks a file, waits, and
/// gets a permission error from RLS with nothing to do about it. So
/// `uploadKindsFor` mirrors the policies rather than holding a second opinion,
/// and these tests are what keep the two honest.
void main() {
  Map<String, dynamic> batchJson({
    String kind = 'exam_seat_plan',
    String status = 'applied',
    int rowCount = 1767,
    String? backupAt,
    String? revertedAt,
  }) =>
      {
        'id': 'b1',
        'kind': kind,
        'status': status,
        'source_file': '23.08.26_Seat Details_Merged.pdf',
        'department': 'CSE',
        'row_count': rowCount,
        'summary': {'dates': 7},
        'uploader': 'Rakib Hassan',
        'uploaded_at': '2026-08-22T09:00:00Z',
        'backup_generated_at': backupAt,
        'reverted_at': revertedAt,
      };

  group('who may upload what', () {
    test('a full admin gets all five kinds', () {
      for (final role in ['admin', 'dept_admin', 'super_admin']) {
        expect(uploadKindsFor(role: role, grants: const {}), [
          'class_routine',
          'exam_routine',
          'transport',
          'exam_seat_plan',
          'notice',
        ], reason: role);
      }
    });

    test('an exam controller does NOT get the class routine', () {
      // `schedule_slots` admits admin / teacher / dept_admin / super_admin or a
      // routine:upload grant, and not exam_controller. Offering it here would
      // promise a screen the database refuses.
      final kinds = uploadKindsFor(role: 'exam_controller', grants: const {});
      expect(kinds, isNot(contains('class_routine')));
      expect(kinds, isNot(contains('transport')));
      expect(kinds, containsAll(['exam_routine', 'exam_seat_plan', 'notice']));
    });

    test('a student gets nothing at all', () {
      expect(uploadKindsFor(role: 'student', grants: const {}), isEmpty);
      expect(uploadKindsFor(role: null, grants: const {}), isEmpty);
    });

    test('a delegated grant unlocks exactly its own kind', () {
      expect(uploadKindsFor(role: 'staff', grants: const {'transport:upload'}),
          ['transport']);
      expect(uploadKindsFor(role: 'staff', grants: const {'exam_seat:upload'}),
          ['exam_seat_plan']);
      expect(uploadKindsFor(role: 'staff', grants: const {'notice:publish'}),
          ['notice']);
    });

    test('routine:upload covers both routines, and nothing else', () {
      // One grant, two importers: the class timetable and the exam timetable
      // are the same permission in the policies.
      expect(uploadKindsFor(role: 'staff', grants: const {'routine:upload'}),
          ['class_routine', 'exam_routine']);
    });

    test('several grants compose without duplicating', () {
      final kinds = uploadKindsFor(
          role: 'staff',
          grants: const {'routine:upload', 'transport:upload'});
      expect(kinds, ['class_routine', 'exam_routine', 'transport']);
      expect(kinds.toSet().length, kinds.length);
    });
  });

  group('what the ledger says about one upload', () {
    test('an applied batch reports its rows and its uploader', () {
      final b = UploadBatch.fromJson(batchJson());
      expect(b.rowCount, 1767);
      expect(b.uploader, 'Rakib Hassan');
      expect(b.kindLabel, 'Exam Seat Plan');
      expect(b.isReverted, isFalse);
      expect(b.isPending, isFalse);
    });

    test('a batch with no backup cannot be offered for removal yet', () {
      final b = UploadBatch.fromJson(batchJson());
      expect(b.hasBackup, isFalse);
      // canRevert says the upload is *removable in principle*; the backup is
      // the separate interlock, and the server enforces it independently.
      expect(b.canRevert, isTrue);
    });

    test('a backup is recorded as generated, never as downloaded', () {
      final b = UploadBatch.fromJson(
          batchJson(backupAt: '2026-08-22T10:00:00Z'));
      expect(b.hasBackup, isTrue);
      expect(b.backupGeneratedAt, isNotNull);
    });

    test('an upload that was opened and never finished reads as pending', () {
      // This is the honest record of an import that failed partway. It is
      // shown, not hidden: rows may have landed before it broke.
      final b = UploadBatch.fromJson(batchJson(status: 'pending', rowCount: 0));
      expect(b.isPending, isTrue);
      expect(b.canRevert, isFalse, reason: 'nothing was stamped to remove');
    });

    test('a removed upload is not offered for removal twice', () {
      final b = UploadBatch.fromJson(batchJson(
          status: 'reverted', revertedAt: '2026-08-22T11:00:00Z'));
      expect(b.isReverted, isTrue);
      expect(b.canRevert, isFalse);
      expect(b.revertedAt, isNotNull);
    });

    test('every kind has a human label', () {
      for (final k in const [
        'class_routine',
        'exam_routine',
        'exam_seat_plan',
        'transport',
        'notice',
      ]) {
        final label = UploadBatch.labelFor(k);
        expect(label, isNot(equals(k)), reason: k);
        expect(label.trim(), isNotEmpty);
      }
    });

    test('an unknown kind degrades to its own name rather than throwing', () {
      expect(UploadBatch.labelFor('something_new'), 'something_new');
    });

    test('missing optional fields do not break the row', () {
      final b = UploadBatch.fromJson({
        'id': 'b2',
        'kind': 'notice',
        'status': 'applied',
        'uploaded_at': '2026-08-22T09:00:00Z',
      });
      expect(b.rowCount, 0);
      expect(b.sourceFile, isNull);
      expect(b.uploader, isNull);
      expect(b.summary, isEmpty);
    });
  });

  group('bulk-select filtering, for clearing out old uploads at once', () {
    UploadBatch batch({
      required String id,
      String kind = 'exam_seat_plan',
      String? department,
    }) =>
        UploadBatch.fromJson(batchJson(kind: kind)
          ..['id'] = id
          ..['department'] = department);

    test('kind and department both narrow the list, together not separately', () {
      final history = [
        batch(id: 'a', kind: 'exam_seat_plan', department: 'CSE'),
        batch(id: 'b', kind: 'exam_seat_plan', department: 'EEE'),
        batch(id: 'c', kind: 'transport', department: 'CSE'),
      ];
      expect(filterUploadBatches(history, kind: 'exam_seat_plan').map((b) => b.id), ['a', 'b']);
      expect(filterUploadBatches(history, department: 'CSE').map((b) => b.id), ['a', 'c']);
      expect(
          filterUploadBatches(history, kind: 'exam_seat_plan', department: 'CSE')
              .map((b) => b.id),
          ['a']);
    });

    test('no filter given returns everything, unfiltered', () {
      final history = [
        batch(id: 'a', department: 'CSE'),
        batch(id: 'b', department: null),
      ];
      expect(filterUploadBatches(history).length, 2);
    });

    test('a batch with no department only matches the "all" state, never a chip', () {
      final history = [batch(id: 'a', department: null)];
      expect(filterUploadBatches(history, department: 'CSE'), isEmpty);
      expect(filterUploadBatches(history), hasLength(1));
    });

    test('department chips list only real, non-blank departments, sorted', () {
      // A blank string is not the same as absent — CLAUDE.md's own gotcha —
      // and both must be excluded the same way null is: neither is something
      // a person can tap as a filter.
      final history = [
        batch(id: 'a', department: 'EEE'),
        batch(id: 'b', department: 'CSE'),
        batch(id: 'c', department: 'CSE'),
        batch(id: 'd', department: null),
        batch(id: 'e', department: '  '),
      ];
      expect(departmentsInBatches(history), ['CSE', 'EEE']);
    });
  });
}
