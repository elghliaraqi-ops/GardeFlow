import 'package:flutter_test/flutter_test.dart';
import 'package:huim6_planning/config/business_rules.dart';

void main() {
  group('GardeFlow business-rule hardening', () {
    test('same hospital remains mandatory', () {
      expect(BusinessRules.sameHospitalRequired, isTrue);
      expect(BusinessRules.minimumRestHours, greaterThanOrEqualTo(0));
    });

    test('Service exchange requires same service when either guard is Service', () {
      expect(
        BusinessRules.exchangeRequiresSameService('service-jour', 'service-nuit'),
        isTrue,
      );
      expect(
        BusinessRules.exchangeRequiresSameService('service-jour', 'urg-nuit'),
        isTrue,
      );
      expect(
        BusinessRules.exchangeRequiresSameService('urg-jour', 'urg-nuit'),
        isFalse,
      );
    });

    test('first-year promotion scope is limited to Urgences requests', () {
      expect(BusinessRules.firstYearSamePromotionRequiredForEmergency, isTrue);
      expect(
        BusinessRules.requestInvolvesEmergency('urg-jour', null),
        isTrue,
      );
      expect(
        BusinessRules.requestInvolvesEmergency('service-jour', 'urg-nuit'),
        isTrue,
      );
      expect(
        BusinessRules.requestInvolvesEmergency('service-jour', 'service-24h'),
        isFalse,
      );
    });
  });
}
