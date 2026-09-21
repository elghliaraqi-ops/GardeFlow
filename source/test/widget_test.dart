import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huim6_planning/theme/app_theme.dart';
import 'package:huim6_planning/ui/components.dart';

void main() {
  testWidgets('a disabled primary action cannot fire', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: AppTheme.forAppearance('green'),
      home: const Scaffold(body: PrimaryButton(label: 'Transférer cette garde', onPressed: null))));
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
}
