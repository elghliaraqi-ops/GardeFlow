import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huim6_planning/screens/practice_visceral_radio_screen.dart';

void main() {
  testWidgets('Viscéral Radio is inaccessible without the owner session', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PracticeVisceralRadioScreen()));
    await tester.pump();
    expect(find.textContaining('Espace privé'), findsOneWidget);
    expect(find.text('Générer une fiche surprise'), findsNothing);
  });
}
