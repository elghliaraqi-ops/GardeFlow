import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('R6 first reading is pdfrx 2.6.5, without automatic Groq', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final screen = File('lib/screens/official_planning_screen.dart')
        .readAsStringSync();
    expect(pubspec, contains('pdfrx: 2.6.5'));
    expect(screen, isNot(contains('allowRemoteVerification: true')));
    expect(screen, isNot(contains('allowRemoteVerification =')));
    expect(screen, contains('loadVerified: (version) => _backend.fetchOfficialRosterVerifiedRead('));
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

  test('Groq targets the one selected official PDF, not every hospital', () {
    final screen = File('lib/screens/official_planning_screen.dart')
        .readAsStringSync();
    final backend = File('lib/services/supabase_backend_service.dart')
        .readAsStringSync();
    final edge = File('supabase/functions/analyze-official-roster-pdf/index.ts')
        .readAsStringSync();
    expect(screen, contains('final selected = _resourceFor(slot.id);'));
    expect(screen, contains('selected.id != resource.id'));
    expect(screen, contains('Lire ce PDF avec Groq'));
    expect(screen, contains('selectedSlot: slot.id'));
    expect(screen, contains('selectedUpdatedAt: resource.updatedAt'));
    expect(screen, contains('manualGroqConfirmed: true'));
    expect(backend, contains("'selectedResourceId': resourceId"));
    expect(backend, contains("'manualGroqConfirmed': manualGroqConfirmed"));
    expect(edge, contains('validateGroqStoredSelection('));
    expect(edge, contains('validateGroqPreflightSelection('));
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
