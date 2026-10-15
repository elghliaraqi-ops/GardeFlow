import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

import '../services/supabase_backend_service.dart';
import '../widgets/practice_qcm_medical_illustration.dart';

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
  bool comparison = false, busy = false;
  int step = 0, position = 0;
  String? error;
  DateTime? retryAt;
  List<Map<String, dynamic>> questions = [], review = [];
  final Map<String, Map<String, dynamic>> answers = {};
  Map<String, dynamic>? report;
  List<String> warnings = [];

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
        });
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
      {int rows = 1, bool required = false, String? hint}) => TextFormField(
    controller: c,
    maxLines: rows,
    maxLength: rows > 1 ? 8500 : 180,
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
      field(region, 'Région anatomique *', required: true,
        hint: 'Ex. encéphale, thorax, abdomino-pelvien, rochers'),
      field(indication, 'Indication / question clinique *',
        rows: 3, required: true),
      field(technique, 'Protocole effectivement réalisé', rows: 2,
        hint: 'Avec/sans contraste, phases, séquences et limites'),
      field(clinical, 'Contexte / antécédents / bilan utiles', rows: 3),
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

  Widget questionsView() {
    final q = questions[position], a = response(q);
    final status = str(a['status']), kind = str(q['kind']);
    final checked = a['selected'] is List
        ? List<String>.from(a['selected'] as List) : <String>[];
    final choices = q['options'] is List
        ? (q['options'] as List).map(str).toList() : <String>[];
    final criteria = q['criteria'] is List
        ? (q['criteria'] as List).map(str).toList() : <String>[];
    return block(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('2 · Question ' + (position + 1).toString() +
        ' / ' + questions.length.toString(),
        style: const TextStyle(color: mint, fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      LinearProgressIndicator(value: (position + 1) / questions.length,
        minHeight: 5, color: mint, backgroundColor: line),
      const SizedBox(height: 10),
      if (str(q['section']).isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: Text(str(q['section']).toUpperCase(),
            style: const TextStyle(color: Color(0xFFFFD166),
              fontWeight: FontWeight.w800, letterSpacing: 0.7)),
        ),
      title(str(q['title'])),
      const SizedBox(height: 12),
      const Text('DÉFINITION', style: TextStyle(
        color: Color(0xFFFFD166), fontWeight: FontWeight.w800)),
      const SizedBox(height: 5),
      Text(str(q['definition']), style: const TextStyle(color: Colors.white)),
      const SizedBox(height: 12),
      const Text('CRITÈRES RADIOLOGIQUES', style: TextStyle(
        color: Color(0xFFFFD166), fontWeight: FontWeight.w800)),
      for (final x in criteria)
        Padding(padding: const EdgeInsets.only(top: 5),
          child: Text('• ' + x, style: const TextStyle(color: muted))),
      if (str(q['reference_query']).isNotEmpty)
        PracticeQcmMedicalIllustration(
          key: ValueKey(qid(q)),
          correction: PracticeQcmImageMetadata.imagingCorrection(
            str(q['reference_query']), exam + ' ' + region.text),
          question: str(q['title']),
          caseContext: exam + ' ' + region.text,
        ),
      const SizedBox(height: 12),
      if (kind == 'qcu')
        Wrap(spacing: 7, runSpacing: 7, children: [
          option('Présent', status == 'observed' && a['value'] == 'oui',
            () => change(q, {'status': 'observed', 'value': 'oui'})),
          option('Absent', status == 'observed' && a['value'] == 'non',
            () => change(q, {'status': 'observed', 'value': 'non'})),
          option('Non évaluable', status == 'not_evaluable',
            () => change(q, {'status': 'not_evaluable', 'value': ''})),
          option('Incertain', status == 'uncertain',
            () => change(q, {'status': 'uncertain', 'value': ''})),
        ]),
      if (kind == 'qcm') ...[
        const Text('Cochez uniquement les signes effectivement observés :',
          style: TextStyle(color: Colors.white)),
        for (final x in choices)
          Padding(padding: const EdgeInsets.only(top: 5),
            child: option(x, status == 'observed' && checked.contains(x), () {
              final next = [...checked];
              if (next.contains(x)) { next.remove(x); } else { next.add(x); }
              change(q, {'status': next.isEmpty ? 'unanswered' : 'observed',
                'selected': next});
            })),
        Wrap(spacing: 7, runSpacing: 7, children: [
          option('Aucun de ces signes', status == 'absent',
            () => change(q, {'status': 'absent', 'selected': <String>[]})),
          option('Non évaluable', status == 'not_evaluable',
            () => change(q, {'status': 'not_evaluable', 'selected': <String>[]})),
          option('Incertain', status == 'uncertain',
            () => change(q, {'status': 'uncertain', 'selected': <String>[]})),
        ]),
        const Text('Une option non cochée ne signifie pas absence.',
          style: TextStyle(color: muted, fontSize: 11)),
      ],
      if (kind == 'texte') ...[
        TextFormField(
          key: ValueKey('free-' + qid(q)),
          initialValue: str(a['value']),
          minLines: 2, maxLines: 6,
          style: const TextStyle(color: Colors.white),
          decoration: decor('Constatations / mesures', 'Localisation, unités...'),
          onChanged: (v) => change(q, {
            'status': v.trim().isEmpty ? 'unanswered' : 'observed', 'value': v,
          }),
        ),
        Wrap(spacing: 7, runSpacing: 7, children: [
          option('Non évaluable', status == 'not_evaluable',
            () => change(q, {'status': 'not_evaluable', 'value': ''})),
          option('Incertain', status == 'uncertain',
            () => change(q, {'status': 'uncertain', 'value': ''})),
        ]),
      ],
      const SizedBox(height: 13),
      TextFormField(
        key: ValueKey('notes-' + qid(q)),
        initialValue: str(a['notes']), maxLines: 3,
        style: const TextStyle(color: Colors.white),
        decoration: decor('Précisions complémentaires',
          'Mesures, topographie, rehaussement, comparaison...'),
        onChanged: (v) => change(q, {'notes': v}),
      ),
      const SizedBox(height: 13),
      Wrap(spacing: 7, runSpacing: 7, children: [
        button(position == 0 ? 'Modifier le contexte' : 'Précédent',
          () => setState(() {
            if (position == 0) { step = 0; } else { position--; }
          }), secondary: true, icon: Icons.arrow_back_rounded),
        button(position == questions.length - 1
            ? 'Rédiger le compte rendu' : 'Suivante', () {
          if (position == questions.length - 1) {
            generate('report');
          } else {
            setState(() => position++);
          }
        }, icon: Icons.description_outlined),
      ]),
      if (status == 'unanswered') const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text('Non renseigné : cette question ne sera pas considérée '
          'comme normale.', style: TextStyle(color: muted, fontSize: 12))),
    ]));
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
          style: const TextStyle(color: Colors.white, height: 1.5),
          decoration: decor('Compte rendu radiologique')),
        const SizedBox(height: 11),
        Wrap(spacing: 8, runSpacing: 8, children: [
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
      backgroundColor: bg, foregroundColor: Colors.white),
    body: SafeArea(child: ListView(
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
        if (step == 1 && questions.isNotEmpty) questionsView(),
        if (step == 2 && report != null) reportView(),
        if (step == 3) reviewView(),
      ],
    )),
  );
}
