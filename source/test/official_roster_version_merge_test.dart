import 'package:flutter_test/flutter_test.dart';
import 'package:huim6_planning/services/official_roster_import_service.dart';

OfficialRosterParseResult _result({
  required List<String> dates,
  required List<OfficialRosterAssignment> assignments,
  List<String> errors = const <String>[],
}) {
  return OfficialRosterParseResult(
    assignments: assignments,
    unmatchedCells: const <Map<String, dynamic>>[],
    disciplinaryMarks: const <OfficialRosterDisciplinaryMark>[],
    detectedRows: dates.length,
    detectedCells: dates.length * 2,
    correctedDates: 0,
    coveredDates: dates,
    validationErrors: errors,
  );
}

void main() {
  test('newest roster version wins only on dates it covers', () {
    final newest = _result(
      dates: const ['2026-10-05', '2026-10-06', '2026-10-07'],
      assignments: const [
        OfficialRosterAssignment(
          profileId: 'doctor',
          dateStr: '2026-10-05',
          shiftId: 'urg-nuit',
        ),
      ],
    );
    final older = _result(
      dates: const [
        '2026-10-01',
        '2026-10-02',
        '2026-10-03',
        '2026-10-04',
        '2026-10-05',
        '2026-10-06',
      ],
      assignments: const [
        OfficialRosterAssignment(
          profileId: 'doctor',
          dateStr: '2026-10-02',
          shiftId: 'urg-jour',
        ),
        OfficialRosterAssignment(
          profileId: 'doctor',
          dateStr: '2026-10-05',
          shiftId: 'urg-jour',
        ),
      ],
    );

    final merged =
        OfficialRosterImportService.mergeNewestFirst([newest, older]);

    expect(
      merged.coveredDates,
      const [
        '2026-10-01',
        '2026-10-02',
        '2026-10-03',
        '2026-10-04',
        '2026-10-05',
        '2026-10-06',
        '2026-10-07',
      ],
    );
    expect(merged.isComplete, isTrue);

    final oct2 = merged.assignments.singleWhere(
      (a) => a.dateStr == '2026-10-02',
    );
    expect(oct2.shiftId, 'urg-jour');

    final oct5 = merged.assignments.singleWhere(
      (a) => a.dateStr == '2026-10-05',
    );
    expect(oct5.shiftId, 'urg-nuit');
  });

  test('a gap between archived versions makes the composite fail closed', () {
    final newest = _result(
      dates: const ['2026-10-05', '2026-10-06'],
      assignments: const <OfficialRosterAssignment>[],
    );
    final older = _result(
      dates: const ['2026-10-01', '2026-10-02'],
      assignments: const <OfficialRosterAssignment>[],
    );

    final merged =
        OfficialRosterImportService.mergeNewestFirst([newest, older]);

    expect(merged.isComplete, isFalse);
    expect(
      merged.validationErrors.any((e) => e.contains('2026-10-03')),
      isTrue,
    );
    expect(
      merged.validationErrors.any((e) => e.contains('2026-10-04')),
      isTrue,
    );
  });

  test('an incomplete historical version is never allowed to override a valid one', () {
    final valid = _result(
      dates: const ['2026-10-01', '2026-10-02', '2026-10-03'],
      assignments: const [
        OfficialRosterAssignment(
          profileId: 'doctor',
          dateStr: '2026-10-02',
          shiftId: 'urg-nuit',
        ),
      ],
    );
    final invalidNewer = _result(
      dates: const ['2026-10-02'],
      assignments: const [
        OfficialRosterAssignment(
          profileId: 'doctor',
          dateStr: '2026-10-02',
          shiftId: 'urg-jour',
        ),
      ],
      errors: const ['Ligne incomplète'],
    );

    final merged = OfficialRosterImportService.mergeNewestFirst(
      [invalidNewer, valid],
    );

    expect(merged.isComplete, isTrue);
    expect(
      merged.assignments.singleWhere((a) => a.dateStr == '2026-10-02').shiftId,
      'urg-nuit',
    );
  });
}
