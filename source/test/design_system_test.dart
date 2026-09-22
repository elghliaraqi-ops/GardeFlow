import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huim6_planning/models/planning_month.dart';
import 'package:huim6_planning/theme/app_theme.dart';
import 'package:huim6_planning/ui/components.dart';

double ratio(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return ((x > y ? x : y) + .05) / ((x < y ? x : y) + .05);
}
void main() {
  for (final name in ['green', 'red', 'white', 'black']) {
    test('$name: readable semantic color pairs', () {
      final c = AppTheme.schemeFor(name);
      for (final pair in [
        [c.onSurface, c.surface], [c.onSurfaceVariant, c.surfaceContainer],
        [c.onSurfaceVariant, c.surfaceContainerHigh], [c.onPrimary, c.primary],
        [c.onPrimaryContainer, c.primaryContainer], [c.onErrorContainer, c.errorContainer],
        [c.onTertiaryContainer, c.tertiaryContainer],
      ]) { expect(ratio(pair[0], pair[1]), greaterThanOrEqualTo(4.5)); }
      final shifts = AppTheme.forAppearance(name).extension<AppShiftTheme>()!;
      for (final tone in shifts.tones.values) {
        expect(ratio(tone.foreground, tone.background), greaterThanOrEqualTo(4.5));
      }
      AppColors.setAppearanceTheme(name);
      for (final foreground in [AppColors.danger, AppColors.success, AppColors.warning]) {
        expect(ratio(foreground, c.surfaceContainer), greaterThanOrEqualTo(4.5));
      }
    });
    testWidgets('$name: reopened status remains legible at 200% text', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.forAppearance(name), home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: const Scaffold(body: ListView(padding: EdgeInsets.all(16), children: [
          StatusBadge(status: PlanningMonthStatus.draft, reopened: true),
          DoctorTile(name: 'Dr ARAQI HOUSSAINI Elghali', subtitle: 'Imagerie Médicale · HUIM6 Bouskoura'),
          PrimaryButton(label: 'Envoyer la demande de transfert', onPressed: null),
        ])),
      )));
      expect(find.text('Rouvert'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
