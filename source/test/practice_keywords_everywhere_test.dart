import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huim6_planning/models/practice_daily_models.dart';
import 'package:huim6_planning/screens/visceral_radio_fiche_view.dart';
import 'package:huim6_planning/widgets/practice_clinical_dossier.dart';
import 'package:huim6_planning/widgets/practice_keyword_text.dart';

List<String> clickableWords(WidgetTester tester) {
  final words = <String>[];
  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    rich.text.visitChildren((span) {
      if (span is TextSpan && span.recognizer != null)
        words.add(span.text ?? '');
      return true;
    });
  }
  return words;
}

void main() {
  testWidgets(
    'stored fiche headings, summary, anatomy, radiology and core points link keywords without editing JSON',
    (tester) async {
      const fiche = {
        'title': 'Cancer du rectum',
        'summary': 'IRM et scanner pour le bilan.',
        'sections': [
          {
            'key': 'anatomy',
            'title': 'Anatomie du rectum',
            'content': 'Le mésorectum entoure le rectum.',
            'key_points': ['Respect du sphincter.'],
            'image_requests': [],
          },
          {
            'key': 'radio',
            'title': 'IRM T2',
            'content': 'Hypersignal et restriction de diffusion.',
            'key_points': [],
            'image_requests': [],
          },
        ],
        'study_core': ['La CRP mesure un phénomène inflammatoire.'],
        'references': [],
      };
      final before = jsonEncode(fiche);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: VisceralFicheView(fiche: fiche, sessionId: 'existing'),
            ),
          ),
        ),
      );
      final words = clickableWords(tester).map((s) => s.toLowerCase()).toList();
      for (final word in [
        'cancer',
        'rectum',
        'irm',
        'scanner',
        'mésorectum',
        'hypersignal',
        'diffusion',
        'crp',
      ])
        expect(words, contains(word));
      expect(jsonEncode(fiche), before);
    },
  );
  testWidgets(
    'clinical narratives gain links and locked future findings remain hidden',
    (tester) async {
      const stages = [
        PracticeDailyStage(title: 'Admission', narrative: 'Douleur abdominale'),
        PracticeDailyStage(title: 'Bilan', narrative: 'IRM'),
        PracticeDailyStage(title: 'Traitement', narrative: 'Résection'),
        PracticeDailyStage(title: 'Suivi', narrative: 'CRP'),
      ];
      const data = {
        'chief_complaint': 'Douleur thoracique avec dyspnée.',
        'illness_history': 'Dyspnée récente.',
        'clinical_exam': 'Tachycardie.',
        'complementary_exams': 'Troponine et ECG.',
      };
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PracticeClinicalDossier(
                stages: stages,
                data: data,
                unlocked: 0,
                current: 0,
                completed: false,
              ),
            ),
          ),
        ),
      );
      final words = clickableWords(tester).map((s) => s.toLowerCase()).toList();
      expect(words, contains('douleur thoracique'));
      expect(words, contains('dyspnée'));
      expect(words, contains('tachycardie'));
      expect(words, isNot(contains('troponine')));
      expect(find.textContaining('À débloquer'), findsNWidgets(3));
    },
  );
  testWidgets(
    'ordinary words are not automatically treated as medical keywords',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PracticeKeywordText(
              'Une suite simple et une conduite habituelle.',
            ),
          ),
        ),
      );
      expect(clickableWords(tester), isEmpty);
    },
  );
}
