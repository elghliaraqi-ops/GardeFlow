import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huim6_planning/models/practice_models.dart';
import 'package:huim6_planning/models/practice_achievement_categories.dart';
import 'package:huim6_planning/widgets/practice_hub_cards.dart';

void main() {
  test('All achievement kinds map to an explicit collection', () {
    final examples = <String, String>{
      'qcm_25': 'QCM',
      'v2_précision50_80': 'QCM',
      'v2_quotidien_10': 'Défis quotidiens',
      'v2_sans-faute_3': 'Défis quotidiens',
      'first_guard': 'Cas cliniques',
      'v2_hors-garde_5': 'Cas cliniques',
      'v2_progressif_10': 'Simulations IA',
      'v2_spécialités_7': 'Simulations IA',
      'streak_3': 'Assiduité',
      'v2_assiduité_7': 'Assiduité',
      'practice_xp_500': 'XP & niveaux',
    };
    for (final example in examples.entries) {
      final badge = PracticeAchievement(
        key: example.key,
        name: 'Test',
        description: 'Test',
        threshold: 10,
        icon: 'quiz',
        progress: 0,
      );
      expect(practiceAchievementCategory(badge), example.value);
    }
  });

  testWidgets('QCM stats are integrated into Practice home', (tester) async {
    tester.view.physicalSize = const Size(380, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    var open = 0;
    var ranking = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(
        child: PracticeHomeHero(
          answered: 88,
          accuracy: 73.4,
          xp: 420,
          streak: 3,
          level: 7,
          loading: false,
          onStart: () => open++,
          onQcmRanking: () => ranking++,
        ),
      )),
    ));
    expect(find.text('88'), findsOneWidget);
    expect(find.text('73%'), findsOneWidget);
    expect(find.text('Explorer les cas et leurs QCM'), findsOneWidget);
    await tester.tap(find.text('Explorer les cas et leurs QCM'));
    expect(open, 1);
    await tester.tap(find.text('Stats et classement QCM'));
    expect(ranking, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Clinical modes have real tap targets', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: PracticeCompactModeCard(
        icon: Icons.auto_awesome,
        title: 'Cas IA aléatoire',
        subtitle: 'Créer un cas fictif',
        label: 'CRÉATION IA',
        accent: Colors.amber,
        onTap: () => tapped++,
      )),
    ));
    await tester.tap(find.text('Cas IA aléatoire'));
    expect(tapped, 1);
    expect(tester.takeException(), isNull);
  });
}
