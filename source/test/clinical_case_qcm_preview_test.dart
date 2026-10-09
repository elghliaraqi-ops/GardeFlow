import 'package:flutter_test/flutter_test.dart';
import 'package:huim6_planning/services/clinical_case_service.dart';

void main() {
  test('a preview exposes proposals but no correct answers', () {
    final preview = ClinicalQcmPreview.fromMap(<String, dynamic>{
      'preview_id': 'preview-1',
      'quantity': 5,
      'difficulty': 'intermediaire',
      'questions': List<Map<String, dynamic>>.generate(5, (i) => {
        'question': 'QCM ${i + 1}',
        'options': ['A', 'B', 'C', 'D'],
        'correct_index': 2,
        'correction': 'Hidden in preview',
      }),
    });
    expect(preview.quantity, 5);
    expect(preview.questions, hasLength(5));
    expect(preview.questions.first.options, hasLength(4));
    expect(preview.questions.first.question, 'QCM 1');
  });

  test('rejects truncated 10-QCM preview rather than publishing it', () {
    expect(
      () => ClinicalQcmPreview.fromMap(<String, dynamic>{
        'preview_id': 'preview-2',
        'quantity': 10,
        'questions': <Map<String, dynamic>>[
          {'question': 'Incomplete', 'options': ['A', 'B', 'C', 'D']},
        ],
      }),
      throwsStateError,
    );
  });
}
