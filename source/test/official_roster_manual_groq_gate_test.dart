import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('R6 first reading is pdfrx 2.6.5, without automatic Groq', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final screen = File('lib/screens/official_planning_screen.dart')
        .readAsStringSync();
    expect(pubspec, contains('pdfrx: 2.6.5'));
    expect(screen, contains('allowRemoteVerification: false'));
    expect(screen, contains('_OfficialRosterReadChoice.pdfrx'));
    expect(screen, contains('Valider la lecture pdfrx'));
  });

  test('R6 Groq is explicitly selected by administrator', () {
    final screen = File('lib/screens/official_planning_screen.dart')
        .readAsStringSync();
    expect(screen, contains('showDialog<_OfficialRosterReadChoice>'));
    expect(screen, contains('_OfficialRosterReadChoice.groq'));
    expect(screen, contains('Corriger avec Groq'));
    expect(screen, contains('forceReread: true'));
  });

  test('Backend bypasses Groq cache only for admin-requested correction', () {
    final backend = File('lib/services/supabase_backend_service.dart')
        .readAsStringSync();
    final edge = File('supabase/functions/analyze-official-roster-pdf/index.ts')
        .readAsStringSync();
    expect(backend, contains("if (forceReread) 'forceReread': true"));
    expect(edge, contains('const forceReread = body?.forceReread === true'));
    expect(edge, contains('const cached = forceReread'));
    expect(edge, contains('cExecuted = true'));
  });
}
