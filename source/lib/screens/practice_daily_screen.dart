import 'package:flutter/material.dart';

import '../widgets/practice_qcm_medical_illustration.dart';

import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/practice_daily_models.dart';
import '../models/practice_external_medical_media_policy.dart';
import '../services/practice_daily_service.dart';
import '../services/notification_service.dart';
import '../services/push_notification_service.dart';
import 'practice_daily_history_screen.dart';
import 'practice_daily_visual_theme.dart';

class PracticeDailyScreen extends StatefulWidget {
  const PracticeDailyScreen({super.key, this.replayDay});

  /// Non-null opens a past completed challenge in unscored practice mode.
  final DateTime? replayDay;
  @override
  State<PracticeDailyScreen> createState() => _PracticeDailyScreenState();
}

class _PracticeDailyScreenState extends State<PracticeDailyScreen> {
  static const _bg = Color(0xFF071526),
      _card = Color(0xFF10243A),
      _text = Color(0xFFF5F8FF),
      _muted = Color(0xFFB9CBE0),
      _green = Color(0xFF5BE7B0),
      _gold = Color(0xFFFFD166);
  final _service = PracticeDailyService.instance;
  bool get _replayMode => widget.replayDay != null;
  late final String _replayRequestId;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  Map<int, PracticeDailyCalendarEntry> _days = {};
  PracticeDailySession? _session;
  List<int?> _selected = List<int?>.filled(10, null);
  int _current = 0;
  bool _busy = false, _enabled = true;
  String? _error;
  String? _lastMode;
  int? _legacyOfficialScore;

  @override
  void initState() {
    super.initState();
    _replayRequestId = _service.createReplayRequestId();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _busy = true);
    if (_replayMode) {
      try {
        final session = await _service.openReplay(widget.replayDay!);
        if (!mounted) return;
        setState(() {
          _session = session;
          _selected = List<int?>.filled(10, null);
          _current = 0;
          _error = null;
        });
      } catch (error) {
        if (mounted) {
          setState(() => _error = 'Rejeu indisponible : $error');
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }
    try {
      final parts = await Future.wait<dynamic>([
        _service.calendar(_month),
        _service.current(),
        _service.remindersEnabled(),
      ]);
      if (!mounted) return;
      final entries = parts[0] as List<PracticeDailyCalendarEntry>;
      final session = parts[1] as PracticeDailySession;
      setState(() {
        _days = {for (final d in entries) d.day.day: d};
        _session = session.ready ? session : null;
        _legacyOfficialScore = !session.ready ? session.officialScore : null;
        _enabled = parts[2] == true;
        _selected = session.completed
            ? session.questions
                  .map((q) => q.selectedIndex)
                  .toList(growable: false)
            : List<int?>.filled(10, null);
        _error = null;
      });
      await _scheduleReminders(entries);
    } catch (e) {
      if (mounted)
        setState(() => _error = 'Connexion Practice indisponible : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scheduleReminders(
    List<PracticeDailyCalendarEntry> entries,
  ) async {
    final localFallback =
        _enabled && !PushNotificationService.instance.hasActiveRemotePush;
    await NotificationService.instance.schedulePracticeDailyChallengeReminders(
      enabled: localFallback,
      completedDays: entries
          .map((e) => DateFormat('yyyy-MM-dd').format(e.day))
          .toSet(),
    );
  }

  Future<void> _changeMonth(int delta) async {
    if (_busy) return;
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _busy = true;
    });
    try {
      final entries = await _service.calendar(_month);
      if (mounted)
        setState(() => _days = {for (final e in entries) e.day.day: e});
    } catch (e) {
      if (mounted) setState(() => _error = 'Calendrier indisponible : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start(String mode) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _lastMode = mode;
      _error = null;
    });
    try {
      final session = await _service.start(mode);
      if (!mounted) return;
      setState(() {
        _session = session;
        _current = 0;
        _selected = session.completed
            ? session.questions
                  .map((q) => q.selectedIndex)
                  .toList(growable: false)
            : List<int?>.filled(10, null);
      });
    } catch (e) {
      if (mounted) {
        final raw = e.toString().toLowerCase();
        final message =
            raw.contains('groq_auth_failed') ||
                raw.contains('groq_configuration_missing')
            ? 'Le service de génération IA nécessite une vérification de sa configuration.'
            : raw.contains('groq_rate_limited')
            ? 'Le service IA a atteint sa limite temporaire. Réessayez plus tard.'
            : raw.contains('generation_in_progress')
            ? 'Le défi est en préparation. Réessayez dans quelques instants.'
            : 'La génération IA n’a pas abouti. Réessayez dans quelques instants.';
        setState(() => _error = message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish() async {
    final s = _session;
    if (s == null || _busy || _selected.any((x) => x == null)) return;
    setState(() => _busy = true);
    try {
      final updated = _replayMode
          ? await _service.finishReplay(
              day: widget.replayDay!,
              answers: _selected.cast<int>(),
              requestId: _replayRequestId,
            )
          : await _service.finish(mode: s.mode, answers: _selected.cast<int>());
      if (!mounted) return;
      setState(() {
        _session = updated;
        _current = 0;
        _error = null;
      });
      if (!_replayMode) {
        final entries = await _service.calendar(_month);
        if (!mounted) return;
        setState(() => _days = {for (final e in entries) e.day.day: e});
        await _scheduleReminders(entries);
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Validation du score échouée : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openReplay(DateTime day) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => PracticeDailyScreen(replayDay: day)),
    );
    if (mounted && !_replayMode) await _load();
  }

  Future<void> _openHistory() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const PracticeDailyHistoryScreen()),
    );
    if (mounted && !_replayMode) await _load();
  }

  void _replayAgain() {
    final day = widget.replayDay;
    if (day == null) return;
    Navigator.of(context).pushReplacement<void, void>(
      MaterialPageRoute(builder: (_) => PracticeDailyScreen(replayDay: day)),
    );
  }

  Future<void> _toggle(bool enabled) async {
    try {
      await _service.setRemindersEnabled(enabled);
      if (!mounted) return;
      setState(() => _enabled = enabled);
      await _scheduleReminders(_days.values.toList());
    } catch (e) {
      if (mounted) setState(() => _error = 'Rappels non modifiés : $e');
    }
  }

  Widget _box(Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: _card,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFF244B68)),
    ),
    child: child,
  );
  Widget _calendar() {
    final count = DateUtils.getDaysInMonth(_month.year, _month.month);
    final offset = DateTime(_month.year, _month.month, 1).weekday - 1;
    final today = DateUtils.dateOnly(DateTime.now());
    final cells = offset + count;
    final rows = ((cells + 6) ~/ 7) * 7;
    return _box(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_month_rounded, color: _gold),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  DateFormat('MMMM yyyy', 'fr').format(_month),
                  style: const TextStyle(
                    color: _text,
                    fontWeight: FontWeight.bold,
                    fontSize: 19,
                  ),
                ),
              ),
              IconButton(
                style: PracticeDailyVisualTheme.toolbarButtonStyle,
                onPressed: () => _changeMonth(-1),
                icon: const Icon(Icons.chevron_left, color: _text),
              ),
              IconButton(
                style: PracticeDailyVisualTheme.toolbarButtonStyle,
                onPressed: () => _changeMonth(1),
                icon: const Icon(Icons.chevron_right, color: _text),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final day in ['L', 'M', 'M', 'J', 'V', 'S', 'D'])
                Expanded(
                  child: Center(
                    child: Text(
                      day,
                      style: TextStyle(
                        color: _muted,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 6,
              crossAxisSpacing: 5,
              childAspectRatio: .82,
            ),
            itemCount: rows,
            itemBuilder: (context, i) {
              final day = i - offset + 1;
              if (day <= 0 || day > count) return const SizedBox.shrink();
              final date = DateTime(_month.year, _month.month, day);
              final entry = _days[day],
                  past = date.isBefore(today),
                  isToday = DateUtils.isSameDay(date, today);
              final color = entry != null
                  ? _green
                  : past
                  ? const Color(0xFFF28C8C)
                  : isToday
                  ? _gold
                  : _muted;
              return InkWell(
                onTap: entry == null
                    ? null
                    : () => showDialog<void>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: Text(DateFormat('d MMMM', 'fr').format(date)),
                          content: Text(
                            'Défi terminé : ${entry.score}/10\nFormat : ${entry.mode == 'cas_clinique' ? 'Ancien cas clinique' : 'QCM de cours'}',
                          ),
                          actions: [
                            TextButton(
                              style:
                                  PracticeDailyVisualTheme.clearTextButtonStyle,
                              onPressed: () => Navigator.pop(c),
                              child: const Text('Fermer'),
                            ),
                            FilledButton.icon(
                              style:
                                  PracticeDailyVisualTheme.primaryButtonStyle,
                              onPressed: () {
                                Navigator.pop(c);
                                _openReplay(date);
                              },
                              icon: const Icon(Icons.replay_rounded),
                              label: const Text('Rejouer'),
                            ),
                          ],
                        ),
                      ),
                child: Container(
                  decoration: BoxDecoration(
                    color: entry != null
                        ? _green.withOpacity(.12)
                        : isToday
                        ? _gold.withOpacity(.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withOpacity(.40)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$day',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                      if (entry != null)
                        Text(
                          '${entry.score}/10',
                          style: const TextStyle(
                            color: _green,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      else if (past)
                        const Icon(
                          Icons.close_rounded,
                          size: 13,
                          color: Color(0xFFF28C8C),
                        )
                      else if (isToday)
                        const Icon(Icons.bolt_rounded, size: 13, color: _gold),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 9),
          const Text(
            'Vert : terminé et noté · Rouge : non fait · Or : aujourd’hui',
            style: TextStyle(color: _muted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _options(PracticeDailyQuestion q, int index, bool completed) {
    return Column(
      children: [
        for (var i = 0; i < q.options.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: InkWell(
              onTap: completed
                  ? null
                  : () => setState(() => _selected[index] = i),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: (_selected[index] == i)
                      ? _green.withOpacity(.15)
                      : const Color(0xFF17314E),
                  border: Border.all(
                    color: completed && q.correctIndex == i
                        ? _green
                        : _selected[index] == i
                        ? _green
                        : const Color(0xFF244B68),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      '${String.fromCharCode(65 + i)}. ',
                      style: const TextStyle(
                        color: _gold,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        q.options[i],
                        style: const TextStyle(color: _text),
                      ),
                    ),
                    if (completed && q.correctIndex == i)
                      const Icon(Icons.check_circle_rounded, color: _green),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _explanation(String correction) {
    final sources = correction.split('§SOURCES§');
    final before = sources.first.split('§IMAGES§');
    final explanation = PracticeQcmImageMetadata.visibleText(correction);
    final lines = before.length > 1
        ? before[1].trim().split('\n')
        : const <String>[];
    final refs = sources.length > 1
        ? sources[1].trim().split('\n')
        : const <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        const Text(
          'Explication IA',
          style: TextStyle(color: _green, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(explanation, style: const TextStyle(color: _text, height: 1.5)),
        PracticeQcmMedicalIllustration(correction: correction),
        if (refs.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text(
            'Sources médicales',
            style: TextStyle(color: _gold, fontWeight: FontWeight.bold),
          ),
          for (final ref in refs)
            Builder(
              builder: (context) {
                final parts = ref.split('|||');
                final uri = Uri.tryParse(parts.length == 5 ? parts[4] : '');
                if (uri?.scheme != 'https') return const SizedBox.shrink();
                return TextButton.icon(
                  style: PracticeDailyVisualTheme.clearTextButtonStyle,
                  onPressed: () =>
                      launchUrl(uri!, mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.open_in_new, size: 14),
                  label: Text(
                    parts[1],
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              },
            ),
        ],
      ],
    );
  }

  Widget _challenge() {
    final s = _session;
    if (_replayMode && (s == null || !s.ready)) {
      return _box(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Rejouer un défi terminé',
              style: TextStyle(
                color: _text,
                fontWeight: FontWeight.bold,
                fontSize: 19,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _busy
                  ? 'Chargement du défi archivé…'
                  : 'Défi inaccessible ou non encore terminé.',
              style: const TextStyle(color: _muted),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: PracticeDailyVisualTheme.secondaryButtonStyle,
              onPressed: _busy ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      );
    }
    if (s == null || !s.ready)
      return _box(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Votre défi du jour · 10 QCM',
              style: TextStyle(
                color: _text,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Exactement 10 nouveaux QCM intégralement générés par IA. '
              'Les cas cliniques progressifs se trouvent dans la bibliothèque Practice.',
              style: TextStyle(color: _muted),
            ),
            if (_legacyOfficialScore != null) ...[
              const SizedBox(height: 10),
              Text(
                'Note historique : $_legacyOfficialScore/10. '
                'Ce nouveau défi IA sera un entraînement sans modifier cette note.',
                style: const TextStyle(color: _gold, fontSize: 12, height: 1.4),
              ),
            ],
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: PracticeDailyVisualTheme.primaryButtonStyle,
                onPressed: _busy ? null : () => _start('cours_ia'),
                icon: const Icon(Icons.school_rounded),
                label: const Text('Commencer · 10 QCM IA inédits'),
              ),
            ),
          ],
        ),
      );
    final index = _current.clamp(0, 9), q = s.questions[index];
    final stageIndex = PracticeDailyProgress.stageForQuestion(index);
    final unlockedStage = s.completed
        ? 3
        : PracticeDailyProgress.unlockedStage(_selected);
    final canAdvance = PracticeDailyProgress.canAdvance(
      currentQuestion: index,
      answers: _selected,
      progressive: s.isProgressiveCase,
      completed: s.completed,
    );
    return _box(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (s.completed) ...[
            Text(
              _replayMode || s.isReplay
                  ? 'Entraînement terminé · ${s.score}/10'
                  : 'Défi terminé · ${s.score}/10',
              style: const TextStyle(
                color: _green,
                fontSize: 23,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
          ],
          if ((_replayMode || s.isReplay) && s.officialScore != null) ...[
            Text(
              'Note officielle inchangée : ${s.officialScore}/10',
              style: const TextStyle(
                color: _gold,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (s.completed) ...[
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                style: PracticeDailyVisualTheme.secondaryButtonStyle,
                onPressed: _replayMode
                    ? _replayAgain
                    : () => _openReplay(s.day),
                icon: const Icon(Icons.replay_rounded),
                label: Text(_replayMode ? 'Rejouer encore' : 'Rejouer'),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Text(
            s.mode == 'cas_clinique'
                ? 'Ancien défi · cas clinique (historique)'
                : 'Défi du jour · 10 nouveaux QCM IA',
            style: const TextStyle(color: _gold, fontWeight: FontWeight.bold),
          ),
          if (s.isProgressiveCase) ...[
            const SizedBox(height: 10),
            Text(
              s.caseTitle,
              style: const TextStyle(
                color: _text,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Étape ${stageIndex + 1}/4 · Répondez aux QCM '
              'de chaque étape pour découvrir la suivante.',
              style: const TextStyle(color: _gold, fontSize: 12),
            ),
            const SizedBox(height: 10),
            for (var stage = 0; stage < 4; stage++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: stage <= unlockedStage
                    ? ExpansionTile(
                        key: ValueKey('practice-case-stage-$stage-$stageIndex'),
                        initiallyExpanded: stage == stageIndex,
                        tilePadding: const EdgeInsets.symmetric(horizontal: 9),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          12,
                          0,
                          12,
                          14,
                        ),
                        backgroundColor: const Color(0xFF17314E),
                        collapsedBackgroundColor: const Color(0xFF17314E),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        collapsedShape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        iconColor: _green,
                        collapsedIconColor: _gold,
                        title: Text(
                          '${stage + 1}. ${s.caseStages[stage].title}',
                          style: const TextStyle(
                            color: _text,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        children: [
                          Text(
                            s.caseStages[stage].narrative,
                            style: const TextStyle(color: _muted, height: 1.5),
                          ),
                        ],
                      )
                    : Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 13,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF17314E),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.lock_outline_rounded,
                              size: 18,
                              color: _muted,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Étape ${stage + 1} · À débloquer',
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
          ] else if (s.caseStem.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              s.caseTitle,
              style: const TextStyle(
                color: _text,
                fontWeight: FontWeight.bold,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              s.caseStem,
              style: const TextStyle(color: _muted, height: 1.45),
            ),
          ],
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: (index + 1) / 10,
                  minHeight: 6,
                  color: _green,
                  backgroundColor: const Color(0xFF244B68),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${index + 1}/10',
                style: const TextStyle(
                  color: _gold,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Text(
            q.question,
            style: const TextStyle(
              color: _text,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          _options(q, index, s.completed),
          if (s.completed) _explanation(q.correction),
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton(
                style: PracticeDailyVisualTheme.secondaryButtonStyle,
                onPressed: index == 0
                    ? null
                    : () => setState(() => _current = index - 1),
                child: const Text('Précédent'),
              ),
              const Spacer(),
              if (index < 9)
                FilledButton(
                  style: PracticeDailyVisualTheme.primaryButtonStyle,
                  onPressed: canAdvance
                      ? () => setState(() => _current = index + 1)
                      : null,
                  child: const Text('Suivant'),
                )
              else if (!s.completed)
                FilledButton(
                  style: PracticeDailyVisualTheme.primaryButtonStyle,
                  onPressed: _busy || _selected.any((x) => x == null)
                      ? null
                      : _finish,
                  child: const Text('Terminer · note sur 10'),
                )
              else
                const Icon(Icons.verified_rounded, color: _green),
            ],
          ),
          if (s.isProgressiveCase &&
              !s.completed &&
              index < 9 &&
              !canAdvance) ...[
            const SizedBox(height: 6),
            const Text(
              'Complétez les réponses de cette étape pour poursuivre.',
              style: TextStyle(color: _gold, fontSize: 12),
            ),
          ],
          if (!s.completed)
            Text(
              '${_selected.where((x) => x != null).length}/10 réponses sélectionnées',
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
        ],
      ),
    );
  }

  void _leavePractice() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    navigator.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: PracticeDailyVisualTheme.from(context),
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          foregroundColor: _text,
          title: Text(
            _replayMode ? 'Rejouer · Practice' : 'Défi quotidien · Practice',
            style: const TextStyle(
              color: PracticeDailyVisualTheme.text,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          actions: [
            IconButton(
              style: PracticeDailyVisualTheme.toolbarButtonStyle,
              tooltip: 'Quitter le défi et revenir à Practice',
              onPressed: _leavePractice,
              icon: const Icon(Icons.exit_to_app_rounded),
            ),
            if (!_replayMode)
              IconButton(
                style: PracticeDailyVisualTheme.toolbarButtonStyle,
                tooltip: 'Historique et rejouer',
                onPressed: _busy ? null : _openHistory,
                icon: const Icon(Icons.history_rounded),
              ),
            IconButton(
              style: PracticeDailyVisualTheme.toolbarButtonStyle,
              tooltip: 'Actualiser',
              onPressed: _busy ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: PracticeDailyVisualTheme.pageGradient,
          ),
          child: ListView(
            padding: const EdgeInsets.all(15),
            children: [
              if (_busy) ...[
                const LinearProgressIndicator(color: _green),
                const SizedBox(height: 12),
              ],
              if (_error != null) ...[
                _box(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.error_outline, color: Color(0xFFFF8D97)),
                          SizedBox(width: 8),
                          Text(
                            'Défi indisponible',
                            style: TextStyle(
                              color: PracticeDailyVisualTheme.text,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: PracticeDailyVisualTheme.text,
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        style: PracticeDailyVisualTheme.secondaryButtonStyle,
                        onPressed: _busy
                            ? null
                            : () => _lastMode == null
                                  ? _load()
                                  : _start(_lastMode!),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Réessayer'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              _challenge(),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: PracticeDailyVisualTheme.secondaryButtonStyle,
                  onPressed: _leavePractice,
                  icon: const Icon(Icons.exit_to_app_rounded),
                  label: const Text('Quitter le défi'),
                ),
              ),
              if (!_replayMode) ...[
                const SizedBox(height: 18),
                _box(
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: PracticeDailyVisualTheme.primaryButtonStyle,
                      onPressed: _openHistory,
                      icon: const Icon(Icons.history_rounded),
                      label: const Text('Historique · Rejouer mes défis'),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                _calendar(),
                const SizedBox(height: 16),
                _box(
                  SwitchListTile(
                    value: _enabled,
                    onChanged: _toggle,
                    activeColor: _green,
                    title: const Text(
                      'Rappel quotidien',
                      style: TextStyle(
                        color: _text,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: const Text(
                      'Notification FCM à 8 h (Casablanca) si le push est actif, '
                      'sinon rappel local sur mobile.',
                      style: TextStyle(color: _muted, fontSize: 12),
                    ),
                    secondary: const Icon(
                      Icons.notifications_active_rounded,
                      color: _gold,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                'Les corrections et les images externes apparaissent après validation des 10 réponses. '
                'Aucune image médicale n’est enregistrée sur les serveurs GardeFlow.',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
