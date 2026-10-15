import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

import '../services/supabase_backend_service.dart';
import '../services/radiology_report_archive_service.dart';
import 'radiology_report_library_screen.dart';
import '../widgets/practice_qcm_medical_illustration.dart';
import '../widgets/practice_quiz_widgets.dart';
import '../widgets/practice_keyword_text.dart';
import 'practice_daily_visual_theme.dart';

/// Guided observations are not scored quizzes. The physician validates every
/// finding and the final report. Nothing is saved by this screen.
class RadiologyReportScreen extends StatefulWidget {
  const RadiologyReportScreen({super.key});
  @override
  State<RadiologyReportScreen> createState() => _RadiologyReportScreenState();
}

class _RadiologyReportScreenState extends State<RadiologyReportScreen> {
  static const bg = Color(0xFF071526), panel = Color(0xFF10243A);
  static const line = Color(0xFF244B68), mint = Color(0xFF5BE7B0);
  static const muted = Color(0xFFB9CBE0);
  final formKey = GlobalKey<FormState>();
  final region = TextEditingController(), indication = TextEditingController();
  final clinical = TextEditingController(), technique = TextEditingController();
  final previous = TextEditingController(), reportText = TextEditingController();
  String exam = 'TDM';
  String sex = 'unknown';
  bool sexChosen = false;
  String? clinicalPlanWarning;
  bool comparison = false, busy = false;
  int step = 0, position = 0;
  String? error;
  DateTime? retryAt;
  List<Map<String, dynamic>> questions = [], review = [];
  final Map<String, Map<String, dynamic>> answers = {};
  Map<String, dynamic>? report;
  List<String> warnings = [];
  DateTime? examDate;
  String? savedReportId, saveError;
  bool savingToArchive = false, unsavedEdits = false;

  Map<String, dynamic> obj(dynamic x) =>
      x is Map ? Map<String, dynamic>.from(x) : <String, dynamic>{};
  List<Map<String, dynamic>> records(dynamic x) => x is List
      ? x.whereType<Map>().map((v) => Map<String, dynamic>.from(v)).toList()
      : <Map<String, dynamic>>[];
  String str(dynamic v) => v?.toString() ?? '';
  String qid(Map<String, dynamic> q) => str(q['id']);
  Map<String, dynamic> response(Map<String, dynamic> q) => answers.putIfAbsent(
    qid(q), () => {'status': 'unanswered', 'value': '',
      'selected': <String>[], 'notes': ''},
  );
  Map<String, dynamic> get contextData => {
    'exam': exam, 'region': region.text.trim(),
    'indication': indication.text.trim(), 'clinical': clinical.text.trim(),
    'technique': technique.text.trim(), 'comparative': comparison,
    'sex': sex,
    'oldReports': comparison ? previous.text.trim() : '',
  };
  String get reportTitle {
    final r = region.text.toLowerCase();
    final x = exam.toLowerCase();
    if ((x.contains('tdm') || x.contains('scanner')) && r.contains('sinus')) {
      return 'SCANNER DES SINUS';
    }
    return (exam + ' ' + region.text).trim().toUpperCase();
  }

  @override
  void dispose() {
    for (final c in [region, indication, clinical, technique, previous, reportText]) {
      c.dispose();
    }
    super.dispose();
  }
  void change(Map<String, dynamic> q, Map<String, dynamic> values) {
    setState(() {
      response(q).addAll(values);
      report = null;
      review = [];
      warnings = [];
    });
  }

  Future<void> generate(String action) async {
    if (busy) return;
    if (retryAt != null && DateTime.now().isBefore(retryAt!)) {
      setState(() => error = 'Quota Groq : attendez la fin du délai de reprise. '
          'Les réponses sont conservées.');
      return;
    }
    setState(() { busy = true; error = null; });
    try {
      final backend = SupabaseBackendService.instance;
      if (!backend.enabled || backend.client.auth.currentUser == null) {
        throw StateError('Connexion GardeFlow requise.');
      }
      final responseData = await backend.client.functions.invoke(
        'generate-radiology-report',
        body: {
          'action': action, 'clinical': contextData,
          if (action == 'plan') 'max_questions': 48,
          if (action == 'report') 'questions': questions,
          if (action == 'report') 'answers': {
            for (final q in questions) qid(q): response(q),
          },
        },
      );
      final data = obj(responseData.data);
      if (data['error'] != null) throw StateError(str(data['error']));
      if (!mounted) return;
      if (action == 'plan') {
        final received = records(data['questions']);
        if (received.length < 5 || received.length > 48) {
          throw StateError('Grille de questions invalide (' +
              received.length.toString() + ' questions reçues).');
        }
        setState(() {
          clinicalPlanWarning = str(data['clinical_coverage_warning']).isNotEmpty
              ? str(data['clinical_coverage_warning']) : null;
          questions = received;
          answers.clear();
          position = 0;
          step = 1;
        });
      } else {
        final result = obj(data['report']);
        if (str(result['results']).isEmpty ||
            str(result['conclusion']).isEmpty) {
          throw StateError('Compte rendu incomplet.');
        }
        setState(() {
          report = result;
          review = records(data['review']);
          warnings = data['quality_warnings'] is List
              ? (data['quality_warnings'] as List).map(str)
                  .where((v) => v.isNotEmpty).toList()
              : [];
          reportText.text = [
            reportTitle, '',
            'INDICATION', str(result['indication']), '',
            'TECHNIQUE', str(result['technique']), '',
            'RÉSULTATS', str(result['results']), '',
            'CONCLUSION', str(result['conclusion']),
          ].join('\n');
          step = 2;
          unsavedEdits = true;
        });
        // A storage failure must never erase the generated report.
        await saveCurrentReport();
      }
    } on FunctionException catch (e) {
      final details = obj(e.details);
      final delay = int.tryParse(str(details['retry_after_seconds']));
      if (delay != null && delay > 0) {
        retryAt = DateTime.now().add(Duration(seconds: delay));
      }
      if (mounted) setState(() => error = str(details['detail']).isNotEmpty
          ? str(details['detail'])
          : 'Service indisponible (' + str(e.status) + '). '
            'Les réponses ont été conservées.');
    } catch (e) {
      if (mounted) setState(() => error =
          'Génération impossible : ' + e.toString() +
          '. Les données saisies restent conservées.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> saveCurrentReport() async {
    if (savingToArchive || reportText.text.trim().isEmpty) return;
    setState(() { savingToArchive = true; saveError = null; });
    try {
      final id = await RadiologyReportArchiveService.instance.save(
        id: savedReportId,
        examType: exam, region: region.text,
        indication: indication.text, examDate: examDate,
        reportText: reportText.text,
      );
      if (!mounted) return;
      setState(() {
        savedReportId = id;
        unsavedEdits = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        saveError = 'Enregistrement impossible : $e. '
          'Le compte rendu reste disponible pour un nouvel essai.';
      });
    } finally {
      if (mounted) setState(() => savingToArchive = false);
    }
  }

  Future<void> chooseExamDate() async {
    final today = DateTime.now();
    final chosen = await showDatePicker(
      context: context,
      initialDate: examDate ?? today,
      firstDate: DateTime(1990),
      lastDate: DateTime(today.year + 2, 12, 31),
      helpText: 'Date de l’examen',
    );
    if (chosen != null && mounted) {
      setState(() => examDate = chosen);
    }
  }

  Future<void> openArchive() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const RadiologyReportLibraryScreen(),
    ));
  }

  InputDecoration decor(String label, [String? hint]) => InputDecoration(
    labelText: label, hintText: hint,
    labelStyle: const TextStyle(color: muted),
    hintStyle: const TextStyle(color: muted),
    counterStyle: const TextStyle(color: muted),
    filled: true, fillColor: bg,
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: line)),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: mint)),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  );
  Widget field(TextEditingController c, String label,
      {int rows = 1, bool required = false, String? hint,
       int? maxChars}) => TextFormField(
    controller: c,
    maxLines: rows,
    maxLength: maxChars ?? (rows > 1 ? 8500 : 180),
    style: const TextStyle(color: Colors.white),
    decoration: decor(label, hint),
    validator: required
        ? (v) => v == null || v.trim().isEmpty ? 'Champ obligatoire' : null
        : null,
  );
  Widget block(Widget child) => Container(
    width: double.infinity, padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(color: panel,
      borderRadius: BorderRadius.circular(19),
      border: Border.all(color: line)),
    child: child,
  );
  Widget button(String label, VoidCallback action,
      {bool secondary = false, IconData icon = Icons.arrow_forward_rounded}) =>
      ElevatedButton.icon(
        onPressed: busy ? null : action,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
          backgroundColor: secondary ? const Color(0xFF21405C) : mint,
          foregroundColor: secondary ? Colors.white : bg,
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13))),
      );
  Widget option(String label, bool active, VoidCallback callback) => FilterChip(
    selected: active,
    showCheckmark: true,
    checkmarkColor: bg,
    selectedColor: mint,
    backgroundColor: const Color(0xFF1B3954),
    side: BorderSide(color: active ? mint : line),
    label: Text(label, style: TextStyle(
      color: active ? bg : Colors.white, fontWeight: FontWeight.w600)),
    onSelected: busy ? null : (_) => callback(),
  );

  void begin() {
    if (!formKey.currentState!.validate()) return;
    if (comparison && previous.text.trim().isEmpty) {
      setState(() => error = 'Collez les anciens comptes rendus du comparatif.');
      return;
    }
    // A pelvic interpretation needs an explicit choice of organ anatomy.
    final scope = (exam + ' ' + region.text + ' ' + technique.text).toLowerCase();
    if (RegExp(r'abdom|pelv|\btap\b|bassin|uro|rein').hasMatch(scope)
        && !sexChosen) {
      setState(() => error = 'Précisez le sexe/anatomie pelvienne '
          'pour orienter les diagnostics différentiels.');
      return;
    }
    // Starting a new guided reading must never overwrite the previous
    // patient's saved report, even if the form was reused.
    savedReportId = null;
    generate('plan');
  }
  Widget setup() => block(Form(
    key: formKey,
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      title('1 · Renseignements cliniques'),
      const SizedBox(height: 7),
      const Text('N’incluez aucun nom, numéro de dossier, date de naissance '
        'ou autre identifiant du patient.', style: TextStyle(color: muted)),
      const SizedBox(height: 15),
      DropdownButtonFormField<String>(
        value: exam, dropdownColor: panel,
        decoration: decor('Type d’examen'),
        style: const TextStyle(color: Colors.white),
        items: [
          for (final x in ['TDM', 'IRM', 'Échographie', 'Radiographie',
            'Doppler', 'Angio-TDM', 'Angio-IRM', 'Autre'])
            DropdownMenuItem(value: x, child: Text(x)),
        ],
        onChanged: (x) => setState(() => exam = x ?? 'TDM'),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: chooseExamDate,
        icon: const Icon(Icons.event_outlined),
        label: Text(examDate == null
            ? 'Date de l’examen (facultative)'
            : 'Examen du ' + examDate!.day.toString().padLeft(2, '0') +
              '/' + examDate!.month.toString().padLeft(2, '0') +
              '/' + examDate!.year.toString()),
      ),
      if (examDate != null)
        TextButton(
          onPressed: () => setState(() => examDate = null),
          child: const Text('Effacer la date'),
        ),
      const SizedBox(height: 10),
      Material(
        type: MaterialType.transparency,
        child: DropdownButtonFormField<String>(
          value: sexChosen ? sex : null,
          isExpanded: true,
          dropdownColor: panel,
          decoration: decor('Sexe / anatomie pelvienne *',
            'Sélection utile pour les diagnostics différentiels'),
          style: const TextStyle(color: Colors.white),
          items: const [
            DropdownMenuItem(value: 'female', child: Text('Féminin · utérus / annexes')),
            DropdownMenuItem(value: 'male', child: Text('Masculin · prostate')),
            DropdownMenuItem(value: 'other', child: Text('Autre / anatomie non précisée')),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() { sex = value; sexChosen = true; });
          },
        ),
      ),
      const SizedBox(height: 12),
      field(region, 'Région anatomique *', required: true,
        hint: 'Ex. encéphale, thorax, abdomino-pelvien, rochers'),
      field(indication, 'Indication / question clinique *',
        rows: 3, required: true, maxChars: 1800),
      field(technique, 'Protocole effectivement réalisé', rows: 2,
        hint: 'Avec/sans contraste, phases, séquences et limites'),
      field(clinical, 'Antécédents / traitements / facteurs de risque', rows: 3,
        hint: 'Ex. ACFA, anticoagulants, chirurgie antérieure, cancer, '
          'immunodépression, pathologies chroniques, bilan biologique...'),
      Material(
        type: MaterialType.transparency,
        child: SwitchListTile.adaptive(
        value: comparison, activeColor: mint, contentPadding: EdgeInsets.zero,
        title: const Text('Examen comparatif',
          style: TextStyle(color: Colors.white)),
        subtitle: const Text('Joindre les rapports antérieurs',
          style: TextStyle(color: muted)),
        onChanged: (v) => setState(() => comparison = v),
        ),
      ),
      if (comparison)
        field(previous, 'Ancien(s) compte(s) rendu(s) *',
          rows: 6, required: true,
          hint: 'Date et compte rendu de chaque examen précédent'),
      button('Démarrer les questions', begin,
        icon: Icons.auto_awesome_rounded),
    ]),
  ));

  Widget title(String text) => Text(text,
    style: const TextStyle(color: Colors.white, fontSize: 19,
      fontWeight: FontWeight.w900));

  /// Same visual language as progressive clinical cases and Viscéral × Radio.
  /// Only presentation is shared: radiological findings are never scored.
  Widget _teachingPanel(Map<String, dynamic> q, List<String> criteria) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: PracticeDailyVisualTheme.surface.withOpacity(.70),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: PracticeDailyVisualTheme.blue.withOpacity(.32),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.menu_book_rounded,
                color: PracticeDailyVisualTheme.gold, size: 17),
              SizedBox(width: 7),
              Text('DÉFINITION', style: TextStyle(
                color: PracticeDailyVisualTheme.gold,
                fontWeight: FontWeight.w900, fontSize: 11)),
            ]),
            const SizedBox(height: 7),
            PracticeKeywordText(
              str(q['definition']),
              style: const TextStyle(
                color: PracticeDailyVisualTheme.text, height: 1.45,
                fontSize: 13),
            ),
            const SizedBox(height: 13),
            const Row(children: [
              Icon(Icons.fact_check_outlined,
                color: PracticeDailyVisualTheme.gold, size: 17),
              SizedBox(width: 7),
              Expanded(child: Text('CRITÈRES RADIOLOGIQUES', style: TextStyle(
                color: PracticeDailyVisualTheme.gold,
                fontWeight: FontWeight.w900, fontSize: 11))),
            ]),
            const SizedBox(height: 6),
            for (final criterion in criteria)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: PracticeKeywordText(
                  '• ' + criterion,
                  style: const TextStyle(
                    color: PracticeDailyVisualTheme.muted, fontSize: 12.5,
                    height: 1.4),
                ),
              ),
            if (str(q['reference_query']).isNotEmpty)
              PracticeQcmMedicalIllustration(
                key: ValueKey(qid(q)),
                correction: PracticeQcmImageMetadata.imagingCorrection(
                  str(q['reference_query']), exam + ' ' + region.text),
                question: str(q['title']),
                caseContext: exam + ' ' + region.text,
              ),
          ],
        ),
      );

  Widget questionsView() {
    final q = questions[position], answer = response(q);
    final status = str(answer['status']), kind = str(q['kind']);
    final selected = answer['selected'] is List
        ? List<String>.from(answer['selected'] as List) : <String>[];
    final choices = q['options'] is List
        ? (q['options'] as List).map(str).toList() : <String>[];
    final criteria = q['criteria'] is List
        ? (q['criteria'] as List).map(str).toList() : <String>[];
    final topic = str(q['section']).trim();
    final qcuChoices = <String>[
      'Présent', 'Absent', 'Non évaluable', 'Incertain',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PracticeQuizCard(
          index: position,
          total: questions.length,
          headerLabel: 'QUESTION',
          topic: (kind == 'qcm' ? 'QCM · signes observés'
              : kind == 'qcu' ? 'QCU · présence du signe'
              : 'Constatations libres') +
              (topic.isEmpty ? '' : ' · ' + topic),
          question: str(q['title']),
          afterQuestion: _teachingPanel(q, criteria),
          options: [
            if (kind == 'qcu')
              for (var i = 0; i < qcuChoices.length; i++)
                PracticeQuizOption(
                  index: i,
                  label: qcuChoices[i],
                  selected: i == 0
                      ? status == 'observed' && answer['value'] == 'oui'
                      : i == 1
                      ? status == 'observed' && answer['value'] == 'non'
                      : i == 2
                      ? status == 'not_evaluable'
                      : status == 'uncertain',
                  showCorrection: false,
                  isCorrect: false,
                  onTap: busy ? null : () {
                    if (i == 0 || i == 1) {
                      change(q, {
                        'status': 'observed',
                        'value': i == 0 ? 'oui' : 'non',
                      });
                    } else {
                      change(q, {
                        'status': i == 2 ? 'not_evaluable' : 'uncertain',
                        'value': '',
                      });
                    }
                  },
                ),
            if (kind == 'qcm') ...[
              for (var i = 0; i < choices.length; i++)
                PracticeQuizOption(
                  index: i,
                  label: choices[i],
                  selected: status == 'observed' &&
                      selected.contains(choices[i]),
                  showCorrection: false,
                  isCorrect: false,
                  onTap: busy ? null : () {
                    final next = [...selected];
                    if (next.contains(choices[i])) {
                      next.remove(choices[i]);
                    } else {
                      next.add(choices[i]);
                    }
                    change(q, {
                      'status': next.isEmpty ? 'unanswered' : 'observed',
                      'selected': next,
                    });
                  },
                ),
            ],
            if (kind == 'texte')
              TextFormField(
                key: ValueKey('free-' + qid(q)),
                initialValue: str(answer['value']),
                minLines: 2, maxLines: 6,
                style: const TextStyle(color: Colors.white),
                decoration: decor('Constatations / mesures',
                  'Localisation, unités...'),
                onChanged: (v) => change(q, {
                  'status': v.trim().isEmpty ? 'unanswered' : 'observed',
                  'value': v,
                }),
              ),
          ],
          trailing: [
            const SizedBox(height: 13),
            if (kind == 'qcm') ...[
              const Text(
                'Cochez uniquement les signes réellement présents.',
                style: TextStyle(
                  color: PracticeDailyVisualTheme.muted, fontSize: 12),
              ),
              const SizedBox(height: 9),
              Wrap(spacing: 7, runSpacing: 7, children: [
                option('Aucun de ces signes', status == 'absent',
                  () => change(q, {
                    'status': 'absent', 'selected': <String>[],
                  })),
                option('Non évaluable', status == 'not_evaluable',
                  () => change(q, {
                    'status': 'not_evaluable', 'selected': <String>[],
                  })),
                option('Incertain', status == 'uncertain',
                  () => change(q, {
                    'status': 'uncertain', 'selected': <String>[],
                  })),
              ]),
              const SizedBox(height: 6),
              const Text(
                'Une option non cochée ne signifie pas absence.',
                style: TextStyle(
                  color: PracticeDailyVisualTheme.muted, fontSize: 11),
              ),
            ],
            if (kind == 'texte')
              Wrap(spacing: 7, runSpacing: 7, children: [
                option('Non évaluable', status == 'not_evaluable',
                  () => change(q, {
                    'status': 'not_evaluable', 'value': '',
                  })),
                option('Incertain', status == 'uncertain',
                  () => change(q, {
                    'status': 'uncertain', 'value': '',
                  })),
              ]),
            const SizedBox(height: 13),
            const Divider(color: PracticeDailyVisualTheme.border),
            const SizedBox(height: 9),
            TextFormField(
              key: ValueKey('notes-' + qid(q)),
              initialValue: str(answer['notes']), maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: decor('Précisions complémentaires',
                'Mesures, topographie, rehaussement, comparaison...'),
              onChanged: (v) => change(q, {'notes': v}),
            ),
            if (status == 'unanswered')
              const Padding(
                padding: EdgeInsets.only(top: 9),
                child: Text(
                  'Non renseigné : cette question ne sera pas '
                  'considérée comme normale.',
                  style: TextStyle(
                    color: PracticeDailyVisualTheme.muted, fontSize: 12),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        PracticeQuizNavigation(
          index: position,
          // These are unscored observations; never display red/green
          // correctness indicators as in educational QCMs.
          results: List<bool?>.filled(questions.length, null),
          onPrevious: position == 0
              ? null : () => setState(() => position--),
          onSelect: busy ? null : (i) => setState(() => position = i),
          onNext: position + 1 < questions.length
              ? () => setState(() => position++)
              : null,
          nextLabel: 'Question suivante',
        ),
        const SizedBox(height: 12),
        if (position == 0)
          Align(
            alignment: Alignment.centerLeft,
            child: button('Modifier le contexte', () =>
              setState(() => step = 0),
              secondary: true, icon: Icons.edit_outlined),
          ),
        if (position == questions.length - 1)
          button('Rédiger le compte rendu', () => generate('report'),
            icon: Icons.description_outlined),
      ],
    );
  }

  Widget reportView() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      block(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        title('3 · Compte rendu'),
        const SizedBox(height: 6),
        const Text('Projet modifiable, à vérifier et valider médicalement.',
          style: TextStyle(color: muted)),
        const SizedBox(height: 12),
        TextField(controller: reportText, minLines: 15, maxLines: null,
          onChanged: (_) => setState(() => unsavedEdits = true),
          style: const TextStyle(color: Colors.white, height: 1.5),
          decoration: decor('Compte rendu radiologique')),
        const SizedBox(height: 11),
        if (savedReportId != null && !unsavedEdits)
          const Text('CR enregistré dans votre bibliothèque',
            style: TextStyle(color: mint, fontWeight: FontWeight.w800)),
        if (savingToArchive)
          const LinearProgressIndicator(color: mint),
        if (saveError != null)
          Text(saveError!,
            style: const TextStyle(color: Color(0xFFFFD166))),
        Wrap(spacing: 8, runSpacing: 8, children: [
          button('Enregistrer le CR', saveCurrentReport,
            icon: Icons.save_outlined),
          button('Ma bibliothèque', openArchive,
            secondary: true, icon: Icons.folder_copy_outlined),
          button('Copier', () async {
            await Clipboard.setData(ClipboardData(text: reportText.text));
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Compte rendu copié.')));
          }, icon: Icons.copy_rounded),
          button('Bilan du cas', () => setState(() => step = 3),
            secondary: true, icon: Icons.school_rounded),
        ]),
      ])),
      if (warnings.isNotEmpty) ...[
        const SizedBox(height: 10),
        block(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Points non documentés', style: TextStyle(
            color: Color(0xFFFFD166), fontWeight: FontWeight.w800)),
          for (final warning in warnings)
            Text('• ' + warning, style: const TextStyle(color: muted)),
        ])),
      ],
      const SizedBox(height: 10),
      button('Revoir mes réponses', () => setState(() {
        step = 1; position = 0;
      }), secondary: true, icon: Icons.edit_note_rounded),
    ],
  );

  Widget reviewView() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      block(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        title('4 · Bilan pédagogique'),
        const SizedBox(height: 6),
        const Text('Statuts, définitions, critères de diagnostic et révision.',
          style: TextStyle(color: muted)),
      ])),
      const SizedBox(height: 10),
      for (final item in review) ...[
        block(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(str(item['sign']), style: const TextStyle(
            color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 7),
          Text('Statut : ' + str(item['status']), style:
            const TextStyle(color: mint, fontWeight: FontWeight.w800)),
          const SizedBox(height: 7),
          Text('Définition : ' + str(item['definition']),
            style: const TextStyle(color: muted)),
          const SizedBox(height: 7),
          Text('Critères : ' + str(item['criteria']),
            style: const TextStyle(color: muted)),
          const SizedBox(height: 7),
          Text('À retenir : ' + str(item['takeaway']),
            style: const TextStyle(color: Colors.white)),
        ])),
        const SizedBox(height: 9),
      ],
      if (review.isEmpty)
        block(const Text('Bilan structuré indisponible. Reprenez les '
          'questions pour revoir les signes.', style: TextStyle(color: muted))),
      button('Retour au compte rendu', () => setState(() => step = 2),
        icon: Icons.description_rounded),
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: bg,
    appBar: AppBar(title: const Text('Assistant CR Radiologie'),
      backgroundColor: bg, foregroundColor: Colors.white,
      actions: [
        IconButton(
          tooltip: 'Mes comptes rendus',
          icon: const Icon(Icons.folder_copy_outlined),
          onPressed: openArchive,
        ),
      ]),
    body: Container(
      decoration: BoxDecoration(
        gradient: step == 1 ? PracticeDailyVisualTheme.pageGradient : null,
      ),
      child: SafeArea(child: ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
      children: [
        Row(children: [
          for (var i = 0; i < 4; i++) ...[
            Expanded(child: Container(height: 5,
              decoration: BoxDecoration(
                color: i <= step ? mint : line,
                borderRadius: BorderRadius.circular(4)))),
            if (i < 3) const SizedBox(width: 7),
          ],
        ]),
        const SizedBox(height: 13),
        if (error != null) ...[
          block(Text(error!, style: const TextStyle(
            color: Color(0xFFFFD166)))),
          const SizedBox(height: 10),
        ],
        if (busy) ...[
          const LinearProgressIndicator(color: mint),
          const SizedBox(height: 7),
          const Text('Génération Groq en cours…',
            style: TextStyle(color: muted)),
          const SizedBox(height: 12),
        ],
        if (step == 0) setup(),
        if (step == 1 && clinicalPlanWarning != null) ...[
          block(Text(clinicalPlanWarning!,
            style: const TextStyle(color: Color(0xFFFFD166)))),
          const SizedBox(height: 10),
        ],
        if (step == 1 && questions.isNotEmpty) questionsView(),
        if (step == 2 && report != null) reportView(),
        if (step == 3) reviewView(),
      ],
    )),
    ),
  );
}
