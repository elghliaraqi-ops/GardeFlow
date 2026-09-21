import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huim6_planning/widgets/admin_reason_dialog.dart';
import 'package:huim6_planning/widgets/month_navigation.dart';

void main() {
  testWidgets('Mois complet sur 320 px avec texte agrandi', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: MediaQuery(
      data: const MediaQueryData(size: Size(320, 640), textScaler: TextScaler.linear(1.4)),
      child: Scaffold(body: MonthNavigation(label: 'Septembre 2026',
        onPrevious: () {}, onNext: () {})),
    )));
    expect(find.text('Septembre 2026'), findsOneWidget);
    final text = tester.widget<Text>(find.text('Septembre 2026'));
    expect(text.overflow, isNot(TextOverflow.ellipsis));
    expect(tester.takeException(), isNull);
  });

  for (final action in ['Dévalider', 'Supprimer']) {
    testWidgets('$action : clavier, validation, fermeture et réouverture', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      String? result;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
        builder: (context) => TextButton(onPressed: () async {
          result = await showDialog<String>(context: context, builder: (_) => AdminReasonDialog(
            title: '$action ce calendrier ?', subject: 'Médecin au nom très long · Septembre 2026',
            explanation: List.filled(8, 'Cette action modifie le calendrier du médecin.').join(' '),
            actionLabel: action,
          ));
        }, child: const Text('Ouvrir')),
      ))));
      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(action));
      await tester.pumpAndSettle();
      expect(find.text('Saisissez au moins 3 caractères.'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('admin-reason')));
      await tester.enterText(find.byKey(const ValueKey('admin-reason')), 'Correction demandée');
      await tester.tap(find.text(action));
      await tester.pump(); // animation de sortie : le contrôleur doit rester valide
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(result, 'Correction demandée');
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(tester.takeException(), isNull);
    });
  }
}
