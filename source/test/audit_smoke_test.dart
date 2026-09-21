import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huim6_planning/config/business_rules.dart';
import 'package:huim6_planning/models/password_reset_request.dart';
import 'package:huim6_planning/services/supabase_backend_service.dart';
import 'package:huim6_planning/theme/app_theme.dart';

double contrastRatio(Color a, Color b) {
  final l1 = a.computeLuminance();
  final l2 = b.computeLuminance();
  final bright = l1 > l2 ? l1 : l2;
  final dark = l1 > l2 ? l2 : l1;
  return (bright + 0.05) / (dark + 0.05);
}

void main() {
  test('Moroccan phone normalization stays stable', () {
    expect(SupabaseBackendService.authPhone('0612345678'), '+212612345678');
    expect(SupabaseBackendService.authPhone('212612345678'), '+212612345678');
    expect(SupabaseBackendService.authPhone('+212612345678'), '+212612345678');
  });

  test('password reset request payload parses correctly', () {
    final request = PasswordResetRequest.fromJson({
      'request_id': 'request-1',
      'profile_id': 'profile-1',
      'requested_at': '2026-09-21T10:00:00Z',
      'full_name': 'Dr Test',
      'phone': '+212600000000',
      'hospital': 'Hospital',
      'service': 'Imagerie Médicale',
      'grade_label': 'Médecin junior',
    });
    expect(request.id, 'request-1');
    expect(request.profileId, 'profile-1');
    expect(request.service, 'Imagerie Médicale');
    expect(request.requestedAt.isUtc, isTrue);
  });

  test('cross-hospital exchanges remain forbidden globally', () {
    expect(BusinessRules.sameHospitalRequired, isTrue);
  });

  test('all application themes keep readable core text and actions', () {
    for (final theme in ['green', 'red', 'white', 'black']) {
      AppColors.setAppearanceTheme(theme);
      expect(
        contrastRatio(AppColors.ink, AppColors.paper),
        greaterThanOrEqualTo(4.5),
        reason: 'Core text contrast failed for $theme',
      );
      expect(
        contrastRatio(Colors.white, AppColors.brandDark),
        greaterThanOrEqualTo(4.5),
        reason: 'Action contrast failed for $theme',
      );
    }
    AppColors.setAppearanceTheme('green');
  });
}
