import 'package:flutter_test/flutter_test.dart';
import 'package:huim6_planning/models/clinical_case_post.dart';

void main() {
  test('parses a clinical case QCM feed row', () {
    final post = ClinicalCasePost.fromMap(<String, dynamic>{
      'id': 'post-1',
      'age_band': '30–44 ans',
      'sex': 'F',
      'presentation': 'Douleur abdominale',
      'qcm_question': 'Quelle conduite a été documentée ?',
      'qcm_options': <String>['A', 'B', 'C', 'D'],
      'correct_index': 2,
      'correction': 'Correction issue du cas.',
      'question_topic': 'prise_en_charge',
      'generation_source': 'openai',
      'published_at': '2026-09-30T10:00:00Z',
    });

    expect(post.options, hasLength(4));
    expect(post.correctIndex, 2);
    expect(post.demographicLabel, '30–44 ans · F');
    expect(post.topicLabel, 'Prise en charge');
    expect(post.generationSource, 'openai');
  });

  test('keeps anonymized fallback labels when demographics are absent', () {
    final post = ClinicalCasePost.fromMap(<String, dynamic>{
      'id': 'post-2',
      'qcm_question': 'Question',
      'qcm_options': <String>['A', 'B', 'C', 'D'],
      'correct_index': 0,
      'correction': 'Correction',
      'question_topic': 'motif',
    });

    expect(post.demographicLabel, 'Patient anonymisé');
    expect(post.topicLabel, 'Motif');
  });
  test('preserves all ten AI questions in chronological position order', () {
    final row = <String, dynamic>{
      'id': 'post-more-qcms',
      'can_edit': true,
      'qcm_question': 'Question historique',
      'qcm_options': <String>['A', 'B', 'C', 'D'],
      'qcms': List<Map<String, dynamic>>.generate(10, (index) {
        return <String, dynamic>{
          'id': 'question-$index',
          'position': 10 - index,
          'question': 'Question pédagogique numéro $index',
          'options': <String>['A', 'B', 'C', 'D'],
          'topic': 'imagerie',
          'generation_source': 'openai',
          'my_selected_index': index == 0 ? 2 : null,
          'my_is_correct': index == 0 ? true : null,
        };
      }),
    };
    final post = ClinicalCasePost.fromMap(row);
    expect(post.canEdit, isTrue);
    expect(post.qcms, hasLength(10));
    expect(post.qcms.map((q) => q.position).toList(),
        List<int>.generate(10, (i) => i + 1));
    expect(post.qcms.where((q) => q.answered), hasLength(1));
  });
}
