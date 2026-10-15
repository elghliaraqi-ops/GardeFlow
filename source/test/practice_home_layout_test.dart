import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huim6_planning/widgets/practice_hub_cards.dart';

void main() {
  testWidgets('Practice navigation switches visibly between 3 clear sections',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) {
          return _NavigationHarness(onSelect: (section) {
            setState(() => _NavigationHarness.current = section);
          });
        }),
      ),
    ));
    expect(find.text('Apprendre'), findsOneWidget);
    expect(find.text('Ma garde'), findsOneWidget);
    expect(find.text('Bilan'), findsOneWidget);
    expect(find.byType(PracticeHomeNavigation), findsOneWidget);
    await tester.tap(find.text('Ma garde'));
    await tester.pumpAndSettle();
    expect(_NavigationHarness.current, PracticeHomeSection.guard);
    await tester.tap(find.text('Bilan'));
    await tester.pumpAndSettle();
    expect(_NavigationHarness.current, PracticeHomeSection.results);
    await tester.tap(find.text('Apprendre'));
    await tester.pumpAndSettle();
    expect(_NavigationHarness.current, PracticeHomeSection.learning);
  });

  testWidgets('compact Practice hero remains usable on narrow phones',
      (tester) async {
    tester.view.physicalSize = const Size(320, 680);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    var openedCases = 0;
    var openedRanking = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PracticeHomeHero(
            answered: 26,
            accuracy: 72,
            xp: 150,
            streak: 3,
            level: 2,
            loading: false,
            onStart: () => openedCases++,
            onQcmRanking: () => openedRanking++,
          ),
        ),
      ),
    ));
    expect(find.text('PRACTICE'), findsOneWidget);
    expect(find.text('Cas & QCM'), findsOneWidget);
    expect(find.text('Classement'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cas & QCM'));
    await tester.tap(find.text('Classement'));
    expect(openedCases, 1);
    expect(openedRanking, 1);
  });

  testWidgets('compact Practice actions keep their navigation handlers',
      (tester) async {
    var opened = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(children: [
            PracticeCompactModeCard(
              icon: Icons.note_add,
              title: 'Cas rencontré',
              subtitle: 'Documenter un cas',
              label: 'DOCUMENTATION',
              accent: Colors.blue,
              onTap: () => opened++,
            ),
            PracticeInlineNavigation(
              icon: Icons.folder,
              title: 'Mes comptes rendus radiologiques',
              subtitle: 'Archives privées',
              onTap: () => opened++,
            ),
          ]),
        ),
      ),
    ));
    await tester.tap(find.text('Cas rencontré'));
    await tester.tap(find.text('Mes comptes rendus radiologiques'));
    expect(opened, 2);
    expect(tester.takeException(), isNull);
  });
}

class _NavigationHarness extends StatelessWidget {
  static PracticeHomeSection current = PracticeHomeSection.learning;
  final ValueChanged<PracticeHomeSection> onSelect;
  const _NavigationHarness({required this.onSelect});

  @override
  Widget build(BuildContext context) => PracticeHomeNavigation(
    selected: current,
    onSelect: onSelect,
  );
}
