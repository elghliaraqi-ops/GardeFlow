import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huim6_planning/widgets/practice_surgical_techniques.dart';

void main() {
  testWidgets(
    'technique cards display name, indications, ordered steps and video links',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PracticeSurgicalTechniques(
                techniques: [
                  {
                    'name': 'Appendicectomie laparoscopique',
                    'indications': 'Indication adaptée au cas.',
                    'steps': [
                      'Installation',
                      'Exploration',
                      'Résection',
                      'Fermeture',
                    ],
                  },
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text('Appendicectomie laparoscopique'), findsOneWidget);
      expect(find.text('Indication adaptée au cas.'), findsOneWidget);
      expect(find.text('1. Installation'), findsOneWidget);
      expect(find.text('4. Fermeture'), findsOneWidget);
      expect(find.textContaining('Voir la vidéo'), findsOneWidget);
      expect(
        find.text('Rechercher une démonstration sur YouTube'),
        findsOneWidget,
      );
    },
  );
  test('video selection never assigns laparoscopic appendectomy to the open technique', () {
    expect(surgicalVideo('Appendicectomie par laparotomie'), isNull);
    expect(
      surgicalVideo('Appendicectomie laparoscopique')?.url,
      contains('Blpd8qJPoKU'),
    );
    expect(surgicalVideo('Cure TAPP')?.url, contains('h7pLrMoxoOs'));
  });
}
