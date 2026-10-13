import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huim6_planning/widgets/practice_quiz_widgets.dart';

void main() {
  testWidgets(
    'visual option retains independent multiple selections and waits for caller validation',
    (tester) async {
      final selected = <int>{};
      var checked = false;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return PracticeQuizCard(
                  index: 0,
                  total: 10,
                  topic: 'imagerie',
                  question: 'Quels signes sur cette IRM ?',
                  options: [
                    for (var i = 0; i < 5; i++)
                      PracticeQuizOption(
                        index: i,
                        label: 'Proposition ${i + 1}',
                        selected: selected.contains(i),
                        showCorrection: checked,
                        isCorrect: i == 0 || i == 2,
                        onTap: checked
                            ? null
                            : () => setState(() {
                                selected.contains(i)
                                    ? selected.remove(i)
                                    : selected.add(i);
                              }),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('A'));
      await tester.tap(find.text('C'));
      await tester.pump();
      expect(selected, {0, 2});
      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
      update(() => checked = true);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(2));
      await tester.tap(find.text('B'));
      await tester.pump();
      expect(selected, {0, 2});
    },
  );
  testWidgets(
    'shared navigation respects disabled future transition and fits long batches on mobile',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      var previous = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PracticeQuizNavigation(
              index: 4,
              results: List<bool?>.filled(100, null),
              onPrevious: () => previous++,
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('QCM précédent'));
      await tester.tap(find.byTooltip('QCM suivant'));
      expect(previous, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('feedback toggles only presentation and retains content', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PracticeQuizFeedback(
            correct: true,
            child: Text('Explication médicale conservée'),
          ),
        ),
      ),
    );
    expect(find.text('Bonne réponse'), findsOneWidget);
    expect(find.text('Explication médicale conservée'), findsOneWidget);
    await tester.tap(find.text('EXPLICATION IA'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.expand_more_rounded), findsOneWidget);
    await tester.tap(find.text('EXPLICATION IA'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.expand_less_rounded), findsOneWidget);
    expect(find.text('Explication médicale conservée'), findsOneWidget);
  });
}
