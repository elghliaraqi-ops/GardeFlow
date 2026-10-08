import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('admin console keeps every historical administration entry point', () {
    final source = File('lib/screens/admin_console_screen.dart').readAsStringSync();

    expect(source, contains("import 'admin_screen.dart';"));
    expect(source, contains('const AdminScreen()'));
    expect(source, contains('const AdminPasswordResetScreen()'));
    expect(source, contains('const AdminDisciplinaryAssignmentScreen()'));
    expect(source, contains('const OfficialPlanningScreen()'));
    expect(source, contains('const NotificationsScreen(initialIndex: 1)'));
    expect(source, contains('const NotificationsScreen(initialIndex: 2)'));
    expect(source, contains('const AuditScreen()'));
    expect(source, contains('const ApplicationSettingsScreen()'));

    expect(source, contains('Médecins et utilisateurs'));
    expect(source, contains('Plannings officiels'));
    expect(source, contains('Calendriers et superpositions'));
    expect(source, contains('Échanges, transferts et demandes'));
    expect(source, contains('Validations et notifications'));
    expect(source, contains('Gardes disciplinaires'));
    expect(source, contains('Logs et traçabilité'));
    expect(source, contains('Paramètres et maintenance'));
  });

  test('R6 admin console exposes targeted roster review and recalculation', () {
    final source = File('lib/screens/admin_console_screen.dart').readAsStringSync();

    expect(source, contains('AdminOfficialRosterReviewScreen'));
    expect(source, contains('AdminRosterRecalculationScreen'));
    expect(source, contains('Recalcul individuel / global'));
    expect(source, contains('Identités du planning'));
    expect(source, contains('Rapports d’import'));
    expect(source, contains('Vue Admin historique complète'));
  });

  test('primary admin navigation no longer bypasses the modular console', () {
    final profile = File('lib/screens/profile_screen.dart').readAsStringSync();
    final home = File('lib/screens/home_screen.dart').readAsStringSync();

    expect(profile, contains('AdminConsoleScreen'));
    expect(home, contains('AdminConsoleScreen'));
    expect(profile, isNot(contains("import 'admin_screen.dart';")));
    expect(home, isNot(contains("import 'admin_screen.dart';")));
  });
}
