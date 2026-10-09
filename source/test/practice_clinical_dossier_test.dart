import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huim6_planning/models/practice_daily_models.dart';
import 'package:huim6_planning/widgets/practice_clinical_dossier.dart';

void main() {
  const stages = [
    PracticeDailyStage(title: 'Admission', narrative: 'Dossier initial'),
    PracticeDailyStage(title: 'Investigations', narrative: 'Bilan'),
    PracticeDailyStage(title: 'Traitement', narrative: 'Prise en charge'),
    PracticeDailyStage(title: 'Évolution', narrative: 'Suivi'),
  ];
  const patient = <String, dynamic>{
    'age': 58,
    'sex': 'M',
    'location': 'Simulation pédagogique · Cardiologie',
    'chief_complaint': 'Douleur thoracique d’effort',
    'consultation_reason': 'Douleur thoracique à l’effort.',
    'illness_history': 'Douleur depuis trois semaines.',
    'clinical_exam': 'TA 150/95 mmHg. FC 88 bpm.',
    'complementary_exams': 'ECG au repos : rythme sinusal.',
    'assessment': 'Coronaropathie multivaisseaux.',
    'plan': '1) Surveillance ECG. 2) Prévention secondaire.',
    'hospitalized': true,
    'hospitalization_service': 'Cardiologie',
  };

  testWidgets('Sections are readable and future information is hidden', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PracticeClinicalDossier(
            stages: stages,
            data: patient,
            unlocked: 0,
            current: 0,
            completed: false,
          ),
        ),
      ),
    ));
    expect(find.text('Motif de consultation'), findsOneWidget);
    expect(find.text('Histoire de la maladie'), findsOneWidget);
    expect(find.text('Constantes et examen clinique'), findsOneWidget);
    expect(find.text('Biologie et examens complémentaires'), findsNothing);
    expect(find.text('Synthèse et orientation diagnostique'), findsNothing);
    expect(find.textContaining('À débloquer'), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('After unlocking, follow-up does not duplicate the full plan', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PracticeClinicalDossier(
            stages: stages,
            data: patient,
            unlocked: 3,
            current: 3,
            completed: true,
          ),
        ),
      ),
    ));
    expect(find.text('Synthèse et orientation diagnostique'), findsOneWidget);
    expect(find.text('Décisions et stratégie thérapeutique'), findsOneWidget);
    expect(find.text('Surveillance et suivi documentés'), findsOneWidget);
    expect(find.textContaining('Hospitalisation en Cardiologie'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('External images reject non-Wikimedia URLs', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ExternalMedicalImagePreview(data: {
          'url': 'https://malicious.example/other',
          'preview_image_url': 'https://malicious.example/preview.png',
          'title': 'Untrusted image',
        }),
      ),
    ));
    expect(find.text('Untrusted image'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
