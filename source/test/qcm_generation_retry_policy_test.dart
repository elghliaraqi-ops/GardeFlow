import 'package:flutter_test/flutter_test.dart';
import 'package:huim6_planning/services/qcm_generation_retry_policy.dart';

void main() {
  group('QcmGenerationRetryPolicy', () {
    test('uses bounded exponential schedule', () {
      expect(QcmGenerationRetryPolicy.delayForFailure(1),
          const Duration(minutes: 1));
      expect(QcmGenerationRetryPolicy.delayForFailure(2),
          const Duration(minutes: 5));
      expect(QcmGenerationRetryPolicy.delayForFailure(3),
          const Duration(minutes: 15));
      expect(QcmGenerationRetryPolicy.delayForFailure(4),
          const Duration(hours: 1));
      expect(QcmGenerationRetryPolicy.delayForFailure(20),
          const Duration(hours: 1));
    });

    test('never automatically retries permanent client/auth failures', () {
      for (final status in <int>[400, 401, 403, 404]) {
        expect(QcmGenerationRetryPolicy.isPermanentHttpStatus(status), isTrue);
        expect(QcmGenerationRetryPolicy.isRetryableHttpStatus(status), isFalse);
      }
    });

    test('allows bounded retries for in-progress, rate limit and outages', () {
      for (final status in <int>[202, 408, 429, 502, 503]) {
        expect(QcmGenerationRetryPolicy.isRetryableHttpStatus(status), isTrue);
      }
    });
  });
}
