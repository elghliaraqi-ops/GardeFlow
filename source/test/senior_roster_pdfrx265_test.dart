import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:huim6_planning/services/senior_roster_pdf_evidence_service.dart';

void main() {
  test('Senior PDF evidence identifies pdfrx 2.6.5 and keeps page metadata', () {
    const evidence = SeniorRosterPdfEvidence(
      resourceId: 'pdf-1',
      resourceUpdatedAt: '2026-10-08T10:00:00Z',
      pageCount: 2,
      pagesRead: 2,
      extractedFragments: 1,
      structuredText: '=== PAGE 1 / 2 ===\nx=10.0 y=30.5 | Dr Bensalem',
      truncated: false,
    );
    expect(evidence.hasSelectableText, isTrue);
    expect(evidence.toJson()['extractor'], 'pdfrx-2.6.5');
    expect(evidence.toJson()['sourceResourceId'], 'pdf-1');
    expect(evidence.toJson()['pageCount'], 2);
    expect(evidence.toJson()['truncated'], isFalse);
  });

  test('A scanned PDF without text cannot be marked as text-readable', () {
    const evidence = SeniorRosterPdfEvidence(
      resourceId: 'scan-1',
      resourceUpdatedAt: '2026-10-08T10:00:00Z',
      pageCount: 1,
      pagesRead: 1,
      extractedFragments: 0,
      structuredText: '=== PAGE 1 / 1 ===\n',
      truncated: false,
    );
    expect(evidence.hasSelectableText, isFalse);
  });

  test('Astreinte photos use OCR; pdfrx is limited to senior PDF resources', () {
    final review = File('lib/screens/senior_roster_review_screen.dart')
        .readAsStringSync();
    final images = File('lib/screens/astreinte_screen.dart')
        .readAsStringSync();
    final backend = File('lib/services/supabase_backend_service.dart')
        .readAsStringSync();
    expect(review, contains("widget.resource.mimeType.toLowerCase() =="));
    expect(review, contains("'application/pdf'"));
    expect(review, contains('SeniorRosterPdfEvidenceService.extract('));
    expect(backend, contains("if (pdfEvidence != null) 'pdfEvidence': pdfEvidence"));
    expect(images, contains('imageQuality: 85'));
    expect(images, contains('maxWidth: 2400'));
  });
}
