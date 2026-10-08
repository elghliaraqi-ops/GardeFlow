import 'package:flutter_test/flutter_test.dart';
import 'package:huim6_planning/data/intern_promotions.dart';
import 'package:huim6_planning/models/app_user.dart';

AppUser profile({
  MedicalPosition? medicalPosition,
  MedicalGrade grade = MedicalGrade.junior,
  int? promotion,
  int? trainingYear,
}) =>
    AppUser(
      id: 'test-user',
      nom: 'Zaghrari',
      prenom: 'Mohammed Dahmane',
      phone: '0600000000',
      passwordHash: '',
      passwordSalt: '',
      service: 'Imagerie médicale',
      grade: grade,
      medicalPosition: medicalPosition,
      trainingYear: trainingYear,
      hospital: 'Test',
      promotionNumber: promotion,
    );

void main() {
  test('five position labels appear in requested order', () {
    expect(MedicalPosition.values.map((value) => value.label).toList(), [
      'Médecin Externe',
      'Médecin FFI',
      'Médecin Interne',
      'Médecin Résident',
      'Professeur',
    ]);
  });

  test('all positions except professor retain junior permissions', () {
    for (final position in MedicalPosition.values) {
      expect(
        position.grade,
        position == MedicalPosition.professeur
            ? MedicalGrade.senior
            : MedicalGrade.junior,
      );
    }
  });

  test('year picker accepts only years relevant to each position', () {
    expect(MedicalPosition.externe.trainingYears, [1, 2, 3, 4, 5]);
    expect(MedicalPosition.ffi.trainingYears, [6, 7]);
    expect(MedicalPosition.resident.trainingYears, [1, 2, 3, 4, 5]);
    expect(MedicalPosition.interne.trainingYears, isEmpty);
    expect(MedicalPosition.professeur.trainingYears, isEmpty);
    expect(MedicalPosition.ffi.acceptsTrainingYear(5), isFalse);
    expect(MedicalPosition.ffi.acceptsTrainingYear(6), isTrue);
    expect(MedicalPosition.externe.acceptsTrainingYear(null), isFalse);
    expect(MedicalPosition.professeur.acceptsTrainingYear(null), isTrue);
  });

  test('only interns have a promotion selector', () {
    expect(MedicalPosition.interne.requiresPromotion, isTrue);
    for (final position in MedicalPosition.values) {
      if (position != MedicalPosition.interne) {
        expect(position.requiresPromotion, isFalse);
      }
    }
  });

  test('new position and training year survive local JSON roundtrip', () {
    final user = profile(
      medicalPosition: MedicalPosition.ffi,
      trainingYear: 7,
    );
    final loaded = AppUser.fromJson(user.toJson());
    expect(loaded.medicalPosition, MedicalPosition.ffi);
    expect(loaded.trainingYear, 7);
    expect(loaded.grade, MedicalGrade.junior);
    expect(loaded.promotionNumber, isNull);
  });

  test('historical junior accounts keep their inferred internship promotion', () {
    expect(InternPromotions.numberFor(profile()), 6);
    expect(
      InternPromotions.numberFor(profile(medicalPosition: MedicalPosition.externe)),
      isNull,
    );
    expect(
      InternPromotions.numberFor(profile(medicalPosition: MedicalPosition.interne)),
      6,
    );
  });

  test('professors remain senior, without academic year or promotion', () {
    final user = profile(
      medicalPosition: MedicalPosition.professeur,
      grade: MedicalGrade.senior,
    );
    final loaded = AppUser.fromJson(user.toJson());
    expect(loaded.grade, MedicalGrade.senior);
    expect(loaded.medicalPosition, MedicalPosition.professeur);
    expect(loaded.trainingYear, isNull);
    expect(InternPromotions.numberFor(loaded), isNull);
  });
}
