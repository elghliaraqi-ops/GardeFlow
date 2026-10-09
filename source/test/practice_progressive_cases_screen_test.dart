import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huim6_planning/screens/practice_progressive_cases_screen.dart';

void main() {
  testWidgets('Clinical simulator lives outside daily challenge, with exit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      const MaterialApp(home: PracticeProgressiveCasesScreen()),
    );
    expect(find.text('Cas cliniques progressifs'), findsOneWidget);
    expect(find.text('Générer un cas clinique progressif'), findsOneWidget);
    expect(find.text('Retour à Practice'), findsOneWidget);
    expect(
      find.textContaining('sans modifier le défi du jour'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
