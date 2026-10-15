import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huim6_planning/screens/radiology_report_screen.dart';

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
