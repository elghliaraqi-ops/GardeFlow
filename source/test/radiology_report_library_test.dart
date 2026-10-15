import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huim6_planning/screens/radiology_report_library_screen.dart';

void main() {
  testWidgets('CR library offers examination, indication and date filters',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: RadiologyReportLibraryScreen()),
    );
    expect(find.text('Bibliothèque des CR'), findsOneWidget);
    expect(find.text('Type d’examen'), findsOneWidget);
    expect(find.text('Rechercher par indication'), findsOneWidget);
    expect(find.text('Date du CR'), findsOneWidget);
    expect(find.text('Date d’examen'), findsOneWidget);
    expect(find.textContaining('Depuis :'), findsOneWidget);
    expect(find.textContaining('Jusqu’au :'), findsOneWidget);
  });

  testWidgets('saved CR opens as editable without regenerating Groq',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: RadiologyArchivedReportDetail(report: {
          'id': '11111111-2222-3333-4444-555555555555',
          'exam_type': 'TDM',
          'region': 'Thorax',
          'indication': 'Toux persistante',
          'exam_date': '2026-10-15',
          'report_text': 'INDICATION\nToux persistante.\nRÉSULTATS\nFoyer alvéolaire.',
        }),
      ),
    );
    expect(find.text('Compte rendu enregistré'), findsOneWidget);
    expect(find.text('TDM · Thorax'), findsOneWidget);
    expect(find.text('Enregistrer les modifications'), findsOneWidget);
    expect(find.text('Copier'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
  });
}
