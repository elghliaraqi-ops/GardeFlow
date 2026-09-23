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

  test('Najid is Promo 5 and is third year while Promo 7 is first year', () {
    final najid = user('NAJID', 'Saad');
    expect(InternPromotions.numberFor(najid), 5);
    expect(
      InternPromotions.trainingYearForPromotion(
        5,
        firstYearPromotion: 7,
      ),
      3,
    );
    expect(
      InternPromotions.labelFor(
        najid,
        firstYearPromotion: 7,
      ),
      '3e année · Promo 5',
    );
  });

  test('current first year is isolated from every older promotion', () {
    final promo7 = user('A', 'Seven', promotion: 7);
    final promo6 = user('B', 'Six', promotion: 6);
    final promo5 = user('C', 'Five', promotion: 5);
    final promo4 = user('D', 'Four', promotion: 4);

    expect(
      InternPromotions.crossYearBlocked(
        promo7,
        promo6,
        firstYearPromotion: 7,
      ),
      isTrue,
    );
    expect(
      InternPromotions.crossYearBlocked(
        promo7,
        promo5,
        firstYearPromotion: 7,
      ),
      isTrue,
    );
    expect(
      InternPromotions.crossYearBlocked(
        promo6,
        promo5,
        firstYearPromotion: 7,
      ),
      isFalse,
    );
    expect(
      InternPromotions.crossYearBlocked(
        promo5,
        promo4,
        firstYearPromotion: 7,
      ),
      isFalse,
    );
  });

  test('when Promo 8 arrives, Promo 8 becomes first year automatically', () {
    final promo8 = user('A', 'Eight', promotion: 8);
    final promo7 = user('B', 'Seven', promotion: 7);
    final promo6 = user('C', 'Six', promotion: 6);

    expect(
      InternPromotions.trainingYearForPromotion(
        8,
        firstYearPromotion: 8,
      ),
      1,
    );
    expect(
      InternPromotions.trainingYearForPromotion(
        7,
        firstYearPromotion: 8,
      ),
      2,
    );
    expect(
      InternPromotions.crossYearBlocked(
        promo8,
        promo7,
        firstYearPromotion: 8,
      ),
      isTrue,
    );
    expect(
      InternPromotions.crossYearBlocked(
        promo7,
        promo6,
        firstYearPromotion: 8,
      ),
      isFalse,
    );
  });
}
