import 'package:flutter/material.dart';

import '../models/practice_daily_models.dart';
import '../services/supabase_backend_service.dart';
import 'practice_daily_visual_theme.dart';

/// Standalone clinical practice. Its answers and scores never enter the
/// official daily challenge, leaderboard, streak or XP.
class PracticeProgressiveCasesScreen extends StatefulWidget {
  const PracticeProgressiveCasesScreen({super.key});

  @override
  State<PracticeProgressiveCasesScreen> createState() =>
      _PracticeProgressiveCasesScreenState();
}

class _PracticeProgressiveCasesScreenState
    extends State<PracticeProgressiveCasesScreen> {
  bool _busy = false;
  bool _submitted = false;
  String? _error;
  String _title = '';
  String _stem = '';
  List<PracticeDailyStage> _stages = const [];
  List<PracticeDailyQuestion> _questions = const [];
  List<int?> _answers = List<int?>.filled(10, null);
  int _question = 0;

  int get _score {
    var sum = 0;
    for (var i = 0; i < _questions.length; i++) {
      if (_answers[i] == _questions[i].correctIndex) sum++;
    }
    return sum;
  }

  Future<void> _generate() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final backend = SupabaseBackendService.instance;
      if (!backend.enabled || backend.client.auth.currentUser == null) {
        throw StateError('Authentification requise.');
      }
      final response = await backend.client.functions.invoke(
        'generate-practice-progressive-case',
        body: <String, dynamic>{},
      );
      if (response.data is! Map) {
        throw StateError('Réponse IA indisponible.');
      }
      final map = Map<String, dynamic>.from(response.data as Map);
      if (map['ok'] != true)
        throw StateError('${map['error'] ?? 'generation_failed'}');
      final rawStages = map['case_stages'];
      final rawQuestions = map['questions'];
      if (rawStages is! List ||
          rawStages.length != 4 ||
          rawQuestions is! List ||
          rawQuestions.length != 10) {
        throw StateError('Le cas généré est incomplet.');
      }
      final stages = rawStages
          .whereType<Map>()
          .map((x) => PracticeDailyStage.fromMap(Map<String, dynamic>.from(x)))
          .toList();
      final questions = rawQuestions
          .whereType<Map>()
          .map(
            (x) => PracticeDailyQuestion.fromMap(Map<String, dynamic>.from(x)),
          )
          .toList();
      if (stages.length != 4 ||
          stages.any((x) => x.title.isEmpty || x.narrative.length < 120) ||
          questions.length != 10 ||
          questions.any(
            (x) =>
                x.options.length != 4 ||
                x.correctIndex == null ||
                x.correction.isEmpty,
          )) {
        throw StateError('Le cas généré est incomplet.');
      }
      if (!mounted) return;
      setState(() {
        _title = '${map['case_title'] ?? 'Cas clinique fictif'}';
        _stem = '${map['case_stem'] ?? ''}';
        _stages = stages;
        _questions = questions;
        _answers = List<int?>.filled(10, null);
        _question = 0;
        _submitted = false;
      });
    } catch (e) {
      if (!mounted) return;
      final reason = e.toString().toLowerCase();
      setState(() {
        _error =
            reason.contains('groq_auth') || reason.contains('configuration')
            ? 'La configuration du service IA doit être vérifiée.'
            : reason.contains('rate_limited')
            ? 'L’IA est momentanément saturée. Réessayez dans quelques instants.'
            : 'Le cas clinique ne peut pas être généré maintenant. Réessayez.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _replay() {
    setState(() {
      _submitted = false;
      _answers = List<int?>.filled(10, null);
      _question = 0;
    });
  }

  void _quit() {
    Navigator.of(context).maybePop();
  }

  Widget _panel(Widget content) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: PracticeDailyVisualTheme.surface,
      border: Border.all(color: PracticeDailyVisualTheme.border),
      borderRadius: BorderRadius.circular(20),
    ),
    child: content,
  );

  Widget _stagePanel() {
    final stageIndex = PracticeDailyProgress.stageForQuestion(_question);
    final unlocked = _submitted
        ? 3
        : PracticeDailyProgress.unlockedStage(_answers);
    return Column(
      children: [
        for (var stage = 0; stage < 4; stage++) ...[
          _panel(
            stage <= unlocked
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${stage + 1}. ${_stages[stage].title}',
                        style: const TextStyle(
                          color: PracticeDailyVisualTheme.gold,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _stages[stage].narrative,
                        style: const TextStyle(
                          color: PracticeDailyVisualTheme.text,
                          height: 1.45,
                          fontSize: 13,
                        ),
                      ),
                      if (!_submitted && stage == stageIndex) ...[
                        const SizedBox(height: 10),
                        const Text(
                          'Étape en cours · répondez aux questions avant de poursuivre',
                          style: TextStyle(
                            color: PracticeDailyVisualTheme.mint,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  )
                : Row(
                    children: [
                      const Icon(
                        Icons.lock_outline_rounded,
                        color: PracticeDailyVisualTheme.muted,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Étape ${stage + 1} · À débloquer',
                        style: const TextStyle(
                          color: PracticeDailyVisualTheme.muted,
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _quiz() {
    final i = _question;
    final q = _questions[i];
    final canNext = PracticeDailyProgress.canAdvance(
      currentQuestion: i,
      answers: _answers,
      progressive: true,
      completed: _submitted,
    );
    return _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'QUESTION ${i + 1}/10 · ${q.topic.toUpperCase()}',
            style: const TextStyle(
              color: PracticeDailyVisualTheme.mint,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 11),
          Text(
            q.question,
            style: const TextStyle(
              color: PracticeDailyVisualTheme.text,
              fontSize: 16,
              height: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 15),
          for (var choice = 0; choice < q.options.length; choice++) ...[
            InkWell(
              onTap: _submitted
                  ? null
                  : () => setState(() => _answers[i] = choice),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: _answers[i] == choice
                      ? PracticeDailyVisualTheme.mint.withOpacity(.14)
                      : PracticeDailyVisualTheme.elevated,
                  border: Border.all(
                    width: _answers[i] == choice ? 2 : 1,
                    color:
                        (_submitted && q.correctIndex == choice) ||
                            _answers[i] == choice
                        ? PracticeDailyVisualTheme.mint
                        : PracticeDailyVisualTheme.border,
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      '${String.fromCharCode(65 + choice)}. ',
                      style: const TextStyle(
                        color: PracticeDailyVisualTheme.gold,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        q.options[choice],
                        style: const TextStyle(
                          color: PracticeDailyVisualTheme.text,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (_submitted && q.correctIndex == choice)
                      const Icon(
                        Icons.check_circle,
                        color: PracticeDailyVisualTheme.mint,
                        size: 20,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (_submitted) ...[
            const SizedBox(height: 11),
            const Text(
              'EXPLICATION IA',
              style: TextStyle(
                color: PracticeDailyVisualTheme.gold,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              q.correction,
              style: const TextStyle(
                color: PracticeDailyVisualTheme.text,
                height: 1.5,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: PracticeDailyVisualTheme.secondaryButtonStyle,
                  onPressed: i == 0
                      ? null
                      : () => setState(() => _question = i - 1),
                  icon: const Icon(Icons.chevron_left_rounded),
                  label: const Text('Précédent'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  style: PracticeDailyVisualTheme.primaryButtonStyle,
                  onPressed: i < 9
                      ? (canNext
                            ? () => setState(() => _question = i + 1)
                            : null)
                      : (!_submitted &&
                                _answers.every((answer) => answer != null)
                            ? () => setState(() {
                                _submitted = true;
                                _question = 0;
                              })
                            : null),
                  icon: Icon(
                    i < 9 ? Icons.chevron_right_rounded : Icons.check_rounded,
                  ),
                  label: Text(i < 9 ? 'Suivant' : 'Terminer'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: PracticeDailyVisualTheme.from(context),
      child: Scaffold(
        backgroundColor: PracticeDailyVisualTheme.background,
        appBar: AppBar(
          title: const Text(
            'Cas cliniques progressifs',
            style: TextStyle(
              color: PracticeDailyVisualTheme.text,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'Quitter les cas progressifs',
              style: PracticeDailyVisualTheme.toolbarButtonStyle,
              onPressed: _quit,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: PracticeDailyVisualTheme.pageGradient,
          ),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(15, 16, 15, 28),
            children: [
              Container(
                padding: const EdgeInsets.all(17),
                decoration: BoxDecoration(
                  gradient: PracticeDailyVisualTheme.cardGradient,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SIMULATION CLINIQUE · IA',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        letterSpacing: 1.1,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Un dossier qui évolue en 4 étapes',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 21,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      '10 QCM liés à un seul cas fictif. '
                      'Entraînement libre, sans modifier le défi du jour, les XP ou le classement.',
                      style: TextStyle(color: Colors.white, height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (_busy) ...[
                const LinearProgressIndicator(
                  color: PracticeDailyVisualTheme.mint,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Génération IA du cas et de ses 10 QCM…',
                  style: TextStyle(color: PracticeDailyVisualTheme.text),
                ),
              ],
              if (_error != null) ...[
                _panel(
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: Color(0xFFFFB2B2),
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (_questions.isEmpty) ...[
                FilledButton.icon(
                  style: PracticeDailyVisualTheme.primaryButtonStyle,
                  onPressed: _busy ? null : _generate,
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: const Text('Générer un cas clinique progressif'),
                ),
              ] else ...[
                Text(
                  _title,
                  style: const TextStyle(
                    color: PracticeDailyVisualTheme.text,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                if (_submitted) ...[
                  _panel(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Résultat d’entraînement : $_score/10',
                          style: const TextStyle(
                            fontSize: 19,
                            color: PracticeDailyVisualTheme.mint,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _stem,
                          style: const TextStyle(
                            color: PracticeDailyVisualTheme.text,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: PracticeDailyVisualTheme.secondaryButtonStyle,
                          onPressed: _replay,
                          icon: const Icon(Icons.replay_rounded),
                          label: const Text('Rejouer'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          style: PracticeDailyVisualTheme.primaryButtonStyle,
                          onPressed: _generate,
                          icon: const Icon(Icons.auto_awesome_rounded),
                          label: const Text('Nouveau cas'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                _stagePanel(),
                _quiz(),
              ],
              const SizedBox(height: 15),
              OutlinedButton.icon(
                style: PracticeDailyVisualTheme.secondaryButtonStyle,
                onPressed: _quit,
                icon: const Icon(Icons.exit_to_app_rounded),
                label: const Text('Retour à Practice'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
