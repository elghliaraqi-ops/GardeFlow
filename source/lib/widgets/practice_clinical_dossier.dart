import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/practice_daily_models.dart';
import '../screens/practice_daily_visual_theme.dart';

/// Purely presentational: the source dossier is fictional, already generated
/// and saved. Nothing in this widget changes QCM answers or stage unlocking.
class PracticeClinicalDossier extends StatelessWidget {
  const PracticeClinicalDossier({
    super.key,
    required this.stages,
    required this.data,
    required this.unlocked,
    required this.current,
    required this.completed,
  });
  final List<PracticeDailyStage> stages;
  final Map<String, dynamic> data;
  final int unlocked;
  final int current;
  final bool completed;

  String field(String name) {
    final value = data[name];
    return value is String ? value.trim() : '';
  }

  static List<String> observations(String raw) {
    final source = raw.trim();
    if (source.isEmpty) return [];
    final numbered = source.replaceAllMapped(
      RegExp(r'(?<!\d)\d{1,2}[.)]\s+(?=\S)'),
      (match) => '|' + match.group(0)!,
    ).split('|').map((text) => text.trim()).where((text) => text.isNotEmpty).toList();
    if (numbered.length > 1) return numbered;
    return source.split(RegExp(r';\s*|(?<=\.)\s+(?=[A-ZÀ-ÖØ-Þ])'))
        .map((text) => text.trim()).where((text) => text.isNotEmpty).toList();
  }

  Widget section(String label, IconData icon, List<String> source,
      {bool numbered = false}) {
    final items = source.expand(observations).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 11),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PracticeDailyVisualTheme.elevated.withOpacity(.7),
        border: Border.all(color: PracticeDailyVisualTheme.border),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 18, color: PracticeDailyVisualTheme.mint),
          const SizedBox(width: 9),
          Expanded(child: Text(label, style: const TextStyle(
            color: PracticeDailyVisualTheme.gold,
            fontSize: 13, fontWeight: FontWeight.w900,
          ))),
        ]),
        const SizedBox(height: 10),
        for (var i = 0; i < items.length; i++) ...[
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 23, child: numbered
              ? Text((i + 1).toString() + '.', style: const TextStyle(
                  color: PracticeDailyVisualTheme.mint,
                  fontWeight: FontWeight.w900, fontSize: 12))
              : const Padding(padding: EdgeInsets.only(top: 7),
                  child: Icon(Icons.circle, size: 5,
                      color: PracticeDailyVisualTheme.mint))),
            Expanded(child: Text(
              items[i].replaceFirst(RegExp(r'^\d{1,2}[.)]\s*'), ''),
              style: const TextStyle(
                color: PracticeDailyVisualTheme.text,
                fontSize: 13.5, height: 1.5),
            )),
          ]),
          if (i + 1 < items.length) const SizedBox(height: 9),
        ],
      ]),
    );
  }

  List<String> fields(List<String> keys) => [
    for (final key in keys) if (field(key).isNotEmpty) field(key)
  ];

  Widget overview() {
    final age = data['age'];
    final sex = field('sex');
    final specialty = field('location')
        .replaceFirst('Simulation pédagogique · ', '');
    final complaint = field('chief_complaint');
    final facts = <String>[
      if (age is num) age.toString() + ' ans',
      if (sex.isNotEmpty) 'Sexe : ' + sex,
      if (specialty.isNotEmpty) specialty,
    ];
    if (facts.isEmpty && complaint.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(17),
      margin: const EdgeInsets.only(bottom: 13),
      decoration: BoxDecoration(
        gradient: PracticeDailyVisualTheme.cardGradient,
        borderRadius: BorderRadius.circular(19)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('DOSSIER CLINIQUE · SIMULATION FICTIVE',
          style: TextStyle(color: Colors.white70, fontSize: 11,
              fontWeight: FontWeight.w900, letterSpacing: .6)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final fact in facts) Chip(
            label: Text(fact),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            side: const BorderSide(color: Colors.white30),
            backgroundColor: Colors.black26,
            labelStyle: const TextStyle(color: Colors.white,
                fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ]),
        if (complaint.isNotEmpty) ...[
          const SizedBox(height: 7),
          Text(complaint, style: const TextStyle(color: Colors.white,
              height: 1.4, fontWeight: FontWeight.w800, fontSize: 15)),
        ],
      ]),
    );
  }

  List<Widget> clinicalSections(int stage) {
    if (data.isEmpty) return [
      section('Éléments du dossier', Icons.notes_rounded,
          [stages[stage].narrative]),
    ];
    switch (stage) {
      case 0:
        return [
          section('Motif de consultation',
              Icons.medical_information_outlined, fields(['consultation_reason'])),
          section('Histoire de la maladie', Icons.history_rounded,
              fields(['illness_history','interrogatoire'])),
          section('Antécédents et facteurs de risque', Icons.person_outline_rounded,
              fields(['personal_medical_history','personal_surgical_history',
                  'family_medical_history','family_surgical_history'])),
          section('Constantes et examen clinique', Icons.monitor_heart_outlined,
              fields(['clinical_exam'])),
        ];
      case 1:
        return [
          section('Biologie et examens complémentaires', Icons.science_outlined,
              fields(['complementary_exams'])),
          section('Imagerie et interprétation', Icons.image_search_outlined,
              fields(['imaging_conclusion'])),
        ];
      case 2:
        return [
          section('Synthèse et orientation diagnostique',
              Icons.fact_check_outlined, fields(['assessment'])),
          section('Décisions et stratégie thérapeutique',
              Icons.medication_outlined, fields(['plan']), numbered: true),
        ];
      default:
        final destination = data['hospitalized'] == true
            ? 'Hospitalisation' + (field('hospitalization_service').isNotEmpty
                ? ' en ' + field('hospitalization_service') : '')
            : data['discharged'] == true
                ? 'Retour à domicile'
                : data['waiting'] == true ? 'Surveillance en cours' : '';
        // Unlike the old narrative, never duplicate the complete prescription.
        final followUp = observations(field('plan')).where((line) =>
          RegExp(r'suivi|surveillance|contrôle|réévaluation|prévention|éducation|arrêt du tabac',
              caseSensitive: false).hasMatch(line)).toList();
        return [
          section('Orientation', Icons.local_hospital_outlined,
              [if (destination.isNotEmpty) destination]),
          section('Surveillance et suivi documentés',
              Icons.event_available_outlined, followUp),
          if (destination.isEmpty && followUp.isEmpty)
            section('Évolution clinique', Icons.info_outline_rounded,
              ['Aucune évolution supplémentaire documentée dans ce dossier fictif.']),
        ];
    }
  }

  List<Map<String, String>> images(int stage) {
    final raw = data['external_media'];
    if (raw is! List) return const [];
    return raw.whereType<Map>().expand((item) {
      final target = int.tryParse(item['stage']?.toString() ?? '');
      if (target != stage) return <Map<String,String>>[];
      return [item.map((key,value) => MapEntry(key.toString(), value.toString()))];
    }).take(2).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (stages.length != 4) return const SizedBox.shrink();
    return Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1020),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        overview(),
        for (var i = 0; i < 4; i++) Container(
          margin: const EdgeInsets.only(bottom: 11),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: PracticeDailyVisualTheme.surface,
            border: Border.all(color: i == current && !completed
                ? PracticeDailyVisualTheme.purple
                : PracticeDailyVisualTheme.border),
            borderRadius: BorderRadius.circular(20),
          ),
          child: i > unlocked
            ? Row(children: [
                const Icon(Icons.lock_outline_rounded,
                    color: PracticeDailyVisualTheme.muted),
                const SizedBox(width: 9),
                Expanded(child: Text('Étape ' + (i + 1).toString() + '/4 · À débloquer',
                  style: const TextStyle(color: PracticeDailyVisualTheme.muted,
                      fontWeight: FontWeight.w800))),
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: PracticeDailyVisualTheme.purple.withOpacity(.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text((i + 1).toString() + '/4',
                      style: const TextStyle(color: PracticeDailyVisualTheme.gold,
                          fontWeight: FontWeight.w900)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(stages[i].title,
                    style: const TextStyle(color: PracticeDailyVisualTheme.gold,
                        fontSize: 16, fontWeight: FontWeight.w900))),
                ]),
                ...clinicalSections(i),
                for (final item in images(i))
                  Padding(padding: const EdgeInsets.only(top: 12),
                      child: ExternalMedicalImagePreview(data: item)),
                if (!completed && i == current)
                  const Padding(padding: EdgeInsets.only(top: 11),
                      child: Text('Répondez aux QCM pour débloquer la suite.',
                        style: TextStyle(color: PracticeDailyVisualTheme.mint,
                            fontSize: 12))),
              ]),
        ),
      ]),
    ));
  }
}

/// External Wikimedia URLs only: no image bytes in database or Storage.
class ExternalMedicalImagePreview extends StatelessWidget {
  const ExternalMedicalImagePreview({super.key, required this.data});
  final Map<String, String> data;

  @override
  Widget build(BuildContext context) {
    final image = Uri.tryParse(data['preview_image_url'] ?? '');
    final source = Uri.tryParse(data['url'] ?? '');
    if (image?.scheme != 'https' || image?.host != 'upload.wikimedia.org' ||
        source?.scheme != 'https' || source?.host != 'commons.wikimedia.org') {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: PracticeDailyVisualTheme.background.withOpacity(.7),
        border: Border.all(color: PracticeDailyVisualTheme.border),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.image_outlined, color: PracticeDailyVisualTheme.mint, size: 17),
          SizedBox(width: 8),
          Expanded(child: Text('ILLUSTRATION MÉDICALE EXTERNE',
            style: TextStyle(color: PracticeDailyVisualTheme.gold,
                fontSize: 11, fontWeight: FontWeight.w900))),
        ]),
        const SizedBox(height: 10),
        ClipRRect(borderRadius: BorderRadius.circular(12),
          child: Image.network(image.toString(), height: 175,
            width: double.infinity, fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Text(
              'Aperçu externe indisponible · consulter la source.',
              style: TextStyle(color: PracticeDailyVisualTheme.muted)))),
        const SizedBox(height: 8),
        Text(data['title'] ?? 'Illustration pédagogique',
          style: const TextStyle(color: PracticeDailyVisualTheme.text,
              fontWeight: FontWeight.w800)),
        const SizedBox(height: 5),
        const Text('Exemple illustratif, pas un examen du patient fictif.',
          style: TextStyle(color: PracticeDailyVisualTheme.muted, fontSize: 11)),
        Text('Wikimedia Commons · ' + (data['license'] ?? ''),
          style: const TextStyle(color: PracticeDailyVisualTheme.muted,
              fontSize: 10)),
        TextButton.icon(
          style: PracticeDailyVisualTheme.clearTextButtonStyle,
          onPressed: () => launchUrl(source!, mode: LaunchMode.externalApplication),
          icon: const Icon(Icons.open_in_new_rounded, size: 16),
          label: const Text('Voir la source'),
        ),
      ]),
    );
  }
}
