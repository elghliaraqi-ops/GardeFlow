import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/widgets/practice_context_glossary.dart';
import '../lib/screens/visceral_radio_fiche_view.dart';

void main() {
  test('rich TNM stays site-specific, with all classification sections', () {
    final term = PracticeGlossaryTerm.fromMap({
      'term': 'TNM',
      'title': 'TNM du cancer du rectum',
      'category': 'classification',
      'definition': 'Classification spécifique au rectum',
      'sections': [
        {'title': 'T', 'items': ['T1 : sous-muqueuse', 'T2 : musculeuse']},
        {'title': 'N', 'items': ['N1 : ganglions régionaux']},
        {'title': 'M', 'items': ['M1 : métastases à distance']},
      ],
      'clinical_relevance': 'Bilan et traitement',
    });
    expect(term.title, contains('rectum'));
    expect(term.sections, hasLength(3));
    expect(term.sections.first.items, contains('T1 : sous-muqueuse'));
    expect(term.clinicalRelevance, 'Bilan et traitement');
  });

  test('rectum and pancreas keep distinct TNM titles and stage lists', () {
    final rectum = PracticeGlossaryTerm.fromMap({
      'term': 'TNM',
      'title': 'TNM du cancer du rectum',
      'category': 'classification',
      'definition': 'Rectum : profondeur d’invasion pariétale',
      'sections': [
        {'title': 'T', 'items': ['T2 : musculeuse propre']},
        {'title': 'N', 'items': ['N1 : ganglions régionaux']},
        {'title': 'M', 'items': ['M1 : extension à distance']},
      ],
    });
    final pancreas = PracticeGlossaryTerm.fromMap({
      'term': 'TNM',
      'title': 'TNM du cancer du pancréas',
      'category': 'classification',
      'definition': 'Pancréas : taille et axes vasculaires selon catégories',
      'sections': [
        {'title': 'T', 'items': ['Critères tumoraux pancréatiques']},
        {'title': 'N', 'items': ['Ganglions régionaux du pancréas']},
        {'title': 'M', 'items': ['Métastases à distance']},
      ],
    });
    expect(rectum.title, contains('rectum'));
    expect(pancreas.title, contains('pancréas'));
    expect(rectum.title, isNot(pancreas.title));
    expect(rectum.sections.first.items, isNot(pancreas.sections.first.items));
  });

  test('historic fiche excerpts retain TNM beyond paragraph beginning', () {
    final longText = '${'Introduction au cours. ' * 65} '
        'Stadification IRM : la classification TNM est déterminante ici.';
    final output = VisceralFicheView.teachingExcerpt(longText, limit: 450);
    expect(output, contains('TNM'));
  });

  test('anatomy supports origin, branches, relations and image query', () {
    final term = PracticeGlossaryTerm.fromMap({
      'term': 'artère mésentérique inférieure',
      'title': 'Artère mésentérique inférieure',
      'category': 'anatomie',
      'definition': 'Vaisseau digestif',
      'sections': [
        {'title': 'Origine', 'items': ['Aorte abdominale']},
        {'title': 'Branches et terminaison', 'items': ['Artère rectale supérieure']},
        {'title': 'Rapports', 'items': ['Uretère gauche']},
      ],
      'image_query': 'inferior mesenteric artery branches surgical anatomy',
    });
    expect(term.sections, hasLength(3));
    expect(term.imageQuery, contains('mesenteric'));
  });

  testWidgets('historic prose remains readable without a generated glossary', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: PracticeGlossaryText('Classification TNM du rectum')),
    ));
    expect(find.text('Classification TNM du rectum'), findsOneWidget);
  });
}
