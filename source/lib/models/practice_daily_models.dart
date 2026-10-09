class PracticeDailyQuestion {
  final String question, topic, correction;
  final List<String> options;
  final int? selectedIndex, correctIndex;
  const PracticeDailyQuestion({
    required this.question,
    required this.options,
    required this.topic,
    this.correction = '',
    this.selectedIndex,
    this.correctIndex,
  });
  factory PracticeDailyQuestion.fromMap(Map<String, dynamic> m) {
    final o = m['options'];
    return PracticeDailyQuestion(
      question: '${m['question'] ?? ''}',
      options: o is List
          ? o.map((x) => '$x').toList(growable: false)
          : const [],
      topic: '${m['topic'] ?? ''}',
      correction: '${m['correction'] ?? ''}',
      selectedIndex: int.tryParse('${m['selected_index'] ?? ''}'),
      correctIndex: int.tryParse('${m['correct_index'] ?? ''}'),
    );
  }
}

class PracticeDailySession {
  final bool ready, completed;
  final DateTime day;
  final String mode, caseTitle, caseStem;
  final List<PracticeDailyStage> caseStages;
  final List<PracticeDailyQuestion> questions;

  bool get isProgressiveCase =>
      mode == 'cas_clinique' && caseStages.length == 4;
  final int? score;
  const PracticeDailySession({
    required this.ready,
    required this.completed,
    required this.day,
    required this.mode,
    required this.caseTitle,
    required this.caseStem,
    this.caseStages = const <PracticeDailyStage>[],
    required this.questions,
    required this.score,
  });
  factory PracticeDailySession.fromMap(Map<String, dynamic> m) {
    final source = m['questions'];
    final q = source is List
        ? source
              .whereType<Map>()
              .map(
                (x) =>
                    PracticeDailyQuestion.fromMap(Map<String, dynamic>.from(x)),
              )
              .toList(growable: false)
        : <PracticeDailyQuestion>[];
    final rawStages = m['case_stages'];
    final stages = rawStages is List
        ? rawStages
              .whereType<Map>()
              .map(
                (row) =>
                    PracticeDailyStage.fromMap(Map<String, dynamic>.from(row)),
              )
              .toList(growable: false)
        : <PracticeDailyStage>[];
    if (stages.isNotEmpty &&
        (stages.length != 4 ||
            stages.any(
              (stage) => stage.title.isEmpty || stage.narrative.length < 120,
            ))) {
      throw StateError('Les étapes du cas clinique sont incomplètes.');
    }
    final ready = m['ready'] == true, completed = m['completed'] == true;
    if (ready && (q.length != 10 || q.any((x) => x.options.length != 4)))
      throw StateError('Le défi doit comporter exactement 10 QCM.');
    if (!completed &&
        q.any((x) => x.correctIndex != null || x.correction.isNotEmpty))
      throw StateError('Corrigé dévoilé avant la fin.');
    final day = DateTime.tryParse('${m['day'] ?? ''}');
    if (day == null) throw StateError('Date du défi invalide.');
    return PracticeDailySession(
      ready: ready,
      completed: completed,
      day: day,
      mode: '${m['mode'] ?? 'cours'}',
      caseTitle: '${m['case_title'] ?? ''}',
      caseStem: '${m['case_stem'] ?? ''}',
      caseStages: stages,
      questions: q,
      score: int.tryParse('${m['score'] ?? ''}'),
    );
  }
}

class PracticeDailyCalendarEntry {
  final DateTime day;
  final int score;
  final String mode;
  const PracticeDailyCalendarEntry({
    required this.day,
    required this.score,
    required this.mode,
  });
  factory PracticeDailyCalendarEntry.fromMap(Map<String, dynamic> m) {
    final day = DateTime.tryParse('${m['challenge_date'] ?? ''}');
    if (day == null) throw StateError('Jour invalide.');
    return PracticeDailyCalendarEntry(
      day: day,
      score: int.tryParse('${m['score'] ?? 0}') ?? 0,
      mode: '${m['mode'] ?? ''}',
    );
  }
}

/// Four gated clinical milestones, with 10 questions distributed 2/3/3/2.
class PracticeDailyStage {
  final String title;
  final String narrative;

  const PracticeDailyStage({required this.title, required this.narrative});

  factory PracticeDailyStage.fromMap(Map<String, dynamic> map) {
    return PracticeDailyStage(
      title: '${map['title'] ?? ''}'.trim(),
      narrative: '${map['narrative'] ?? ''}'.trim(),
    );
  }
}

abstract final class PracticeDailyProgress {
  static int stageForQuestion(int index) {
    if (index < 0 || index > 9) {
      throw RangeError.range(index, 0, 9, 'index');
    }
    if (index < 2) return 0;
    if (index < 5) return 1;
    if (index < 8) return 2;
    return 3;
  }

  /// To open a future stage, every QCM of preceding stages needs an answer.
  static int unlockedStage(List<int?> answers) {
    if (answers.length != 10) {
      throw ArgumentError('Exactly ten answers are required.');
    }
    if (answers.take(2).any((answer) => answer == null)) return 0;
    if (answers.take(5).any((answer) => answer == null)) return 1;
    if (answers.take(8).any((answer) => answer == null)) return 2;
    return 3;
  }

  static bool canAdvance({
    required int currentQuestion,
    required List<int?> answers,
    required bool progressive,
    required bool completed,
  }) {
    if (currentQuestion >= 9) return false;
    if (!progressive || completed) return true;
    return stageForQuestion(currentQuestion + 1) <= unlockedStage(answers);
  }
}
