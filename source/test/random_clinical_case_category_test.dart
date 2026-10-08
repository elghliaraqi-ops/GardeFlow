import 'package:flutter_test/flutter_test.dart';
import 'package:huim6_planning/models/clinical_case_post.dart';

void main() {
  ClinicalCasePost post(String presentation) {
    return ClinicalCasePost.fromMap(<String, dynamic>{
      'id': 'test-id',
      'presentation': presentation,
      'specialist_service': 'Cardiologie',
    });
  }

  test('a generated consultation reason is classified as fictional', () {
    expect(post('[SIMULATION IA] Douleur thoracique').isFictional, isTrue);
  });

  test('a generated chief complaint is classified as fictional', () {
    expect(post('[CAS FICTIF – IA] Dyspnée aiguë').isFictional, isTrue);
  });

  test('a clinical case without a synthetic marker remains real', () {
    expect(post('Dyspnée aiguë depuis deux jours').isFictional, isFalse);
  });
}
