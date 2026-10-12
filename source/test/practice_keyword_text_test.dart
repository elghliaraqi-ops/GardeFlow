import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huim6_planning/widgets/practice_keyword_text.dart';

void main() {
  testWidgets('historic and generated keywords keep question text and clickable spans', (tester) async {
    for (final question in ['Fièvre et douleur abdominale, quelle conduite ?', '**Pneumopéritoine** : quel examen ?']) {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: PracticeKeywordText(question))));
      final rich = tester.widget<RichText>(find.descendant(of: find.byType(PracticeKeywordText), matching: find.byType(RichText)));
      expect(rich.text.toPlainText(), question.replaceAll('**', ''));
      final root = rich.text as TextSpan;
      final clickable = root.children!.whereType<TextSpan>().where((s) => s.recognizer != null);
      expect(clickable, isNotEmpty);
      expect(clickable.every((s) => s.style?.decoration == TextDecoration.underline), isTrue);
    }
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
