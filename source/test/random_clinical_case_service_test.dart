import 'package:flutter_test/flutter_test.dart';
import 'package:huim6_planning/services/random_clinical_case_service.dart';

void main() {
  Map<String, dynamic> validPayload() => <String, dynamic>{
        'ok': true,
        'case': <String, dynamic>{
          'age': 54,
          'sex': 'F',
          'consultation_reason': '[SIMULATION IA] Douleur abdominale aiguë',
          'illness_history': 'Douleur croissante depuis 24 heures avec vomissements.',
          'clinical_exam': 'Température à 38,4 °C et défense en fosse iliaque droite.',
          'assessment': 'Appendicite aiguë probable, sans signe de choc.',
          'plan': 'Bilan biologique, imagerie adaptée et avis chirurgical urgent.',
          'location': 'Simulation pédagogique · Chirurgie viscérale',
          'specialist_opinion_requested': true,
        },
      };

  test('un cas fictif valide est utilisable dans le formulaire', () {
    final value = RandomClinicalCase.fromMap(validPayload());
    expect(value.age, 54);
    expect(value.sex, 'F');
    expect(value.text('location'), contains('Simulation pédagogique'));
    expect(value.flag('specialist_opinion_requested'), isTrue);
    expect(value.flag('discharged'), isFalse);
  });

  test('un cas incomplet est refusé avant remplissage du formulaire', () {
    final payload = validPayload();
    (payload['case'] as Map<String, dynamic>)['clinical_exam'] = '';
    expect(() => RandomClinicalCase.fromMap(payload), throwsFormatException);
  });

  test('un âge hors limites est refusé', () {
    final payload = validPayload();
    (payload['case'] as Map<String, dynamic>)['age'] = 130;
    expect(() => RandomClinicalCase.fromMap(payload), throwsFormatException);
  });
}
