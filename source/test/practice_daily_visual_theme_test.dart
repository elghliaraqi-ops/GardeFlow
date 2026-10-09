import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huim6_planning/screens/practice_daily_visual_theme.dart';

void main() {
  testWidgets('Practice dark gradient and readable primary/secondary buttons', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Theme(
            data: PracticeDailyVisualTheme.from(context),
            child: Scaffold(
              body: Column(
                children: [
                  FilledButton(
                    onPressed: () {},
                    child: const Text('Commencer'),
                  ),
                  OutlinedButton(
                    onPressed: () {},
                    child: const Text('Quitter le défi'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final theme = Theme.of(tester.element(find.text('Commencer')));
    expect(theme.scaffoldBackgroundColor, PracticeDailyVisualTheme.background);
    expect(
      theme.filledButtonTheme.style?.foregroundColor?.resolve(<WidgetState>{}),
      PracticeDailyVisualTheme.background,
    );
    expect(
      theme.filledButtonTheme.style?.backgroundColor?.resolve(<WidgetState>{}),
      PracticeDailyVisualTheme.mint,
    );
    expect(
      theme.outlinedButtonTheme.style?.foregroundColor?.resolve(
        <WidgetState>{},
      ),
      PracticeDailyVisualTheme.text,
    );
    expect(find.text('Quitter le défi'), findsOneWidget);
  });
  testWidgets('Explicit button styles remain high contrast when disabled', (
    tester,
  ) async {
    expect(
      PracticeDailyVisualTheme.primaryButtonStyle.backgroundColor!.resolve(
        <WidgetState>{},
      ),
      PracticeDailyVisualTheme.mint,
    );
    expect(
      PracticeDailyVisualTheme.primaryButtonStyle.foregroundColor!.resolve(
        <WidgetState>{},
      ),
      PracticeDailyVisualTheme.background,
    );
    expect(
      PracticeDailyVisualTheme.secondaryButtonStyle.foregroundColor!.resolve(
        <WidgetState>{},
      ),
      PracticeDailyVisualTheme.text,
    );
    expect(
      PracticeDailyVisualTheme.toolbarButtonStyle.foregroundColor!.resolve(
        <WidgetState>{},
      ),
      PracticeDailyVisualTheme.text,
    );
    expect(
      PracticeDailyVisualTheme.secondaryButtonStyle.foregroundColor!.resolve(
        <WidgetState>{WidgetState.disabled},
      ),
      isNot(Colors.transparent),
    );
  });
}
