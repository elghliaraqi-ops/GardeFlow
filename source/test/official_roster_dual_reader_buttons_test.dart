import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Official PDF card has separate manual pdfrx and Groq actions', () {
    final src = File('lib/screens/official_planning_screen.dart')
        .readAsStringSync();
    expect(src, contains("label: const Text('Relire avec pdfrx')"));
    expect(src, contains("label: const Text('Relire avec Groq')"));
    expect(src, contains('onRereadPdfrx: (r) => _rereadPdfrx(_slots[i], r)'));
    expect(src, contains('onRereadR6: (r) => _rereadR6(_slots[i], r)'));
    expect(src, contains('onPressed: busy ? null : () => onRereadPdfrx(r)'));
    expect(src, contains('onPressed: busy ? null : () => onRereadR6(r)'));
  });

  test('pdfrx reread downloads exactly one PDF and does not call Groq', () {
    final src = File('lib/screens/official_planning_screen.dart')
        .readAsStringSync();
    final localStart = src.indexOf('Future<void> _rereadPdfrx(');
    final remoteStart = src.indexOf('Future<void> _rereadR6(');
    expect(localStart, greaterThan(0));
    expect(remoteStart, greaterThan(localStart));
    final localHandler = src.substring(localStart, remoteStart);
    expect(localHandler, contains('final selected = _resourceFor(slot.id);'));
    expect(localHandler, contains('selected.id != resource.id'));
    expect(localHandler, contains('downloadSharedResource(resource.storagePath)'));
    expect(localHandler, contains('OfficialRosterImportService.parse('));
    expect(localHandler, contains('parsed.localCells'));
    expect(localHandler, isNot(contains('analyzeOfficialRosterResource(')));
    expect(localHandler, isNot(contains('GroqRosterVision')));
    expect(localHandler, isNot(contains('importOfficialEmergencyRoster(')));
    expect(localHandler, isNot(contains('saveOfficialRosterAnalysisR6(')));
  });

  test('Both administrator screens expose the two readers without auto-start', () {
    final console = File('lib/screens/admin_console_screen.dart')
        .readAsStringSync();
    final recalc = File('lib/screens/admin_roster_recalculation_screen.dart')
        .readAsStringSync();
    for (final source in [console, recalc]) {
      expect(source, contains('Relire avec pdfrx'));
      expect(source, contains('Relire avec Groq'));
      expect(source, contains('OfficialPlanningReader.pdfrx'));
      expect(source, contains('OfficialPlanningReader.groq'));
    }
  });
}
