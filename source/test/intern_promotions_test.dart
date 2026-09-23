import 'package:flutter_test/flutter_test.dart';
import 'package:huim6_planning/data/intern_promotions.dart';
import 'package:huim6_planning/models/app_user.dart';

AppUser user(String nom, String prenom, {int? promotion}) => AppUser(
      id: '$nom-$prenom',
      nom: nom,
      prenom: prenom,
      phone: '0600000000',
      passwordHash: '',
      passwordSalt: '',
      service: 'Imagerie médicale',
      grade: MedicalGrade.junior,
      hospital: 'Test',
      promotionNumber: promotion,
    );

void main() {
  test('Zaghrari account is Promo 6 and recognizes PDF short identity', () {
    final zaghrari = user('zaghrari', 'mohammed dahmane');
    expect(InternPromotions.numberFor(zaghrari), 6);
    expect(
      InternPromotions.officialRosterAliasesFor(zaghrari),
      contains('dahmane zaghrari'),
    );
  });

  test('Najid is Promo 5 and automatic training year is third year', () {
    final najid = user('NAJID', 'Saad');
    expect(InternPromotions.numberFor(najid), 5);
    expect(InternPromotions.trainingYearForPromotion(5), 3);
    expect(InternPromotions.labelFor(najid), '3e année · Promo 5');
  });

  test('Urgences isolates first year but allows older cohorts together', () {
    final promo7 = user('A', 'Seven', promotion: 7);
    final promo6 = user('B', 'Six', promotion: 6);
    final promo5 = user('C', 'Five', promotion: 5);
    final promo4 = user('D', 'Four', promotion: 4);

    expect(InternPromotions.crossYearBlocked(promo7, promo6), isTrue);
    expect(InternPromotions.crossYearBlocked(promo7, promo5), isTrue);
    expect(InternPromotions.crossYearBlocked(promo6, promo5), isFalse);
    expect(InternPromotions.crossYearBlocked(promo5, promo4), isFalse);
  });
}
