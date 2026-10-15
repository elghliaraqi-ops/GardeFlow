import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huim6_planning/screens/radiology_report_screen.dart';
import 'package:huim6_planning/data/radiology_exam_regions.dart';

void main() {
  testWidgets('radiology report opens at clinical context stage',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: RadiologyReportScreen()),
    );
    expect(find.text('Assistant CR Radiologie'), findsOneWidget);
    expect(find.text('1 · Renseignements cliniques'), findsOneWidget);
    expect(find.text('Démarrer les questions'), findsOneWidget);
    expect(find.text('Type d’examen'), findsOneWidget);
  });

  testWidgets('region dropdown follows modality and resets after changing exam',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: RadiologyReportScreen()),
    );
    expect(find.byKey(const ValueKey('radiology-region-picker-TDM')),
      findsOneWidget);
    expect(find.text('Région anatomique *'), findsOneWidget);
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('radiology-region-picker-TDM')),
      find.byType(ListView), const Offset(0, -200),
    );
    await tester.tap(
      find.byKey(const ValueKey('radiology-region-picker-TDM')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sinus de la face').last);
    await tester.pumpAndSettle();
    expect(find.text('Sinus de la face'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('radiology-exam-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('radiology-exam-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('IRM').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('radiology-region-picker-IRM')),
      findsOneWidget);
    expect(find.text('Sinus de la face'), findsNothing,
      reason: 'The region is cleared when switching imaging modality');
    await tester.dragUntilVisible(
      find.text('Démarrer les questions'),
      find.byType(ListView), const Offset(0, -250),
    );
    await tester.tap(find.text('Démarrer les questions'));
    await tester.pump();
    expect(find.text('Choisissez une région anatomique'), findsOneWidget);
  });

  testWidgets('exceptional region can still be entered explicitly',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: RadiologyReportScreen()),
    );
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('radiology-region-picker-TDM')),
      find.byType(ListView), const Offset(0, -200),
    );
    await tester.tap(
      find.byKey(const ValueKey('radiology-region-picker-TDM')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text(RadiologyExamRegions.customRegion),
      300,
      scrollable: find.byType(Scrollable).last,
      maxScrolls: 20,
    );
    await tester.tap(find.text(RadiologyExamRegions.customRegion).last);
    await tester.pumpAndSettle();
    expect(find.text('Précisez la région anatomique *'), findsOneWidget);
  });

  testWidgets('comparison requests an earlier report', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: RadiologyReportScreen()),
    );
    await tester.dragUntilVisible(
      find.text('Examen comparatif'), find.byType(ListView),
      const Offset(0, -250),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Examen comparatif'));
    await tester.pumpAndSettle();
    expect(find.text('Ancien(s) compte(s) rendu(s) *'), findsOneWidget);
  });

  testWidgets('empty clinical context cannot start generation',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: RadiologyReportScreen()),
    );
    await tester.dragUntilVisible(
      find.text('Démarrer les questions'), find.byType(ListView),
      const Offset(0, -250),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Démarrer les questions'));
    await tester.pump();
    expect(find.text('Champ obligatoire'), findsWidgets);
    expect(find.text('1 · Renseignements cliniques'), findsOneWidget);
  });
}
