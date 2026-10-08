import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('relecture of existing PDF is an explicit admin-only R6 action', () {
    final screen =
        File('lib/screens/official_planning_screen.dart').readAsStringSync();
    expect(screen, contains('_reverifyExistingPdfR6('));
    expect(screen, contains("resource.slot != slot.id"));
    expect(screen, contains('UserRole.admin'));
    expect(screen, contains('Relire avec R6'));
    expect(screen, contains('downloadSharedResource(resource.storagePath)'));
    expect(screen, contains('analyzeOfficialRosterResource('));
    expect(screen, contains('localEvidence: localEvidence'));
    expect(screen, contains('manualResolutions: resolutions'));
    expect(screen, contains("_OfficialRosterConflictReviewDialog(conflicts: conflicts)"));
    expect(screen, contains("extraction['document_scope'] != 'urgences'"));
    expect(screen, contains('verified.officialGuards.isEmpty'));
    expect(screen, contains('saveOfficialRosterAnalysisR6('));

    final start = screen.indexOf('Future<void> _reverifyExistingPdfR6(');
    final end = screen.indexOf('Future<void> _upload(', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final relecture = screen.substring(start, end);

    // Verifying source must never import calendars or replace the PDF.
    expect(relecture, isNot(contains('importOfficialEmergencyRoster(')));
    expect(relecture, isNot(contains('uploadOfficialPlanningPdf(')));
    expect(relecture, isNot(contains('registerOfficialDisciplinaryMarks(')));
    expect(relecture, isNot(contains('applyOfficialRosterRecalculation(')));
  });

  test('R6 controls direct admins from empty reports to original PDFs', () {
    final review = File('lib/screens/admin_official_roster_review_screen.dart')
        .readAsStringSync();
    final recalculation =
        File('lib/screens/admin_roster_recalculation_screen.dart')
            .readAsStringSync();
    expect(review, contains('Relire les PDF existants avec R6'));
    expect(recalculation, contains('Relire les PDF officiels avec R6'));
    expect(recalculation, contains('Aucun planning Urgences vérifié'));
    expect(recalculation, contains('Aucun calendrier n’a été modifié'));
  });

  test('remote R6 relecture supports targeted manual corrections', () {
    final backend = File('lib/services/supabase_backend_service.dart')
        .readAsStringSync();
    expect(backend, contains('manualResolutions:'));
    expect(backend, contains("'manualResolutions': manualResolutions"));
    expect(backend, contains('saveOfficialRosterAnalysisR6('));
  });
}
