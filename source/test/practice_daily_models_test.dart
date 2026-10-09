import 'package:flutter_test/flutter_test.dart';
import 'package:huim6_planning/models/practice_daily_models.dart';

void main() {
  Map<String, dynamic> question(int i) => <String, dynamic>{
    'question': 'Question $i',
    'options': <String>['A', 'B', 'C', 'D'],
    'topic': 'diagnostic',
  };
  test('a pending daily challenge has 10 QCM and hides corrections', () {
    final state = PracticeDailySession.fromMap(<String, dynamic>{
      'ready': true,
      'completed': false,
      'day': '2026-10-09',
      'mode': 'cours',
      'questions': List<Map<String, dynamic>>.generate(10, question),
    });
    expect(state.questions, hasLength(10));
    expect(
      state.questions.every(
        (q) => q.correctIndex == null && q.correction.isEmpty,
      ),
      isTrue,
    );
    expect(state.score, isNull);
  });
  test('a completed challenge retains score and selected responses', () {
    final state = PracticeDailySession.fromMap(<String, dynamic>{
      'ready': true,
      'completed': true,
      'day': '2026-10-09',
      'mode': 'cas_clinique',
      'score': 8,
      'case_title': 'Simulation IA',
      'case_stem': 'Cas fictif',
      'questions': List<Map<String, dynamic>>.generate(
        10,
        (i) => {
          ...question(i),
          'selected_index': i % 4,
          'correct_index': i % 4,
          'correction': 'Correction IA',
        },
      ),
    });
    expect(state.completed, isTrue);
    expect(state.score, 8);
    expect(state.questions.first.selectedIndex, 0);
    expect(state.questions.first.correction, 'Correction IA');
  });
  test('refuses incomplete challenge or premature answer keys', () {
    expect(
      () => PracticeDailySession.fromMap(<String, dynamic>{
        'ready': true,
        'completed': false,
        'day': '2026-10-09',
        'mode': 'cours',
        'questions': List<Map<String, dynamic>>.generate(9, question),
      }),
      throwsStateError,
    );
    expect(
      () => PracticeDailySession.fromMap(<String, dynamic>{
        'ready': true,
        'completed': false,
        'day': '2026-10-09',
        'mode': 'cours',
        'questions': List<Map<String, dynamic>>.generate(
          10,
          (i) => {...question(i), 'correct_index': 2},
        ),
      }),
      throwsStateError,
    );
  });
  test('parses monthly score without marking other days complete', () {
    final item = PracticeDailyCalendarEntry.fromMap(<String, dynamic>{
      'challenge_date': '2026-10-09',
      'mode': 'cours',
      'score': 7,
    });
    expect(item.day.day, 9);
    expect(item.score, 7);
  });

  test('progressive case contains four pedagogical disclosures', () {
    final stageNarrative = List<String>.filled(8, 'Dossier fictif. ').join();
    final session = PracticeDailySession.fromMap(<String, dynamic>{
      'ready': true,
      'completed': false,
      'day': '2026-10-09',
      'mode': 'cas_clinique',
      'case_title': 'Cas progressif fictif',
      'case_stem': '',
      'case_stages': List<Map<String, dynamic>>.generate(
        4,
        (i) => {'title': 'Étape ${i + 1}', 'narrative': stageNarrative},
      ),
      'questions': List<Map<String, dynamic>>.generate(10, question),
    });
    expect(session.isProgressiveCase, true);
    expect(session.caseStages, hasLength(4));
    expect(session.questions.every((q) => q.correctIndex == null), true);
  });

  test('progressive milestones unlock after all preceding answers', () {
    expect(PracticeDailyProgress.stageForQuestion(0), 0);
    expect(PracticeDailyProgress.stageForQuestion(1), 0);
    expect(PracticeDailyProgress.stageForQuestion(2), 1);
    expect(PracticeDailyProgress.stageForQuestion(5), 2);
    expect(PracticeDailyProgress.stageForQuestion(9), 3);
    final answers = List<int?>.filled(10, null);
    expect(PracticeDailyProgress.unlockedStage(answers), 0);
    expect(
      PracticeDailyProgress.canAdvance(
        currentQuestion: 1,
        answers: answers,
        progressive: true,
        completed: false,
      ),
      false,
    );
    answers[0] = 0;
    answers[1] = 2;
    expect(PracticeDailyProgress.unlockedStage(answers), 1);
    for (var i = 2; i < 5; i++) {
      answers[i] = 0;
    }
    expect(PracticeDailyProgress.unlockedStage(answers), 2);
    for (var i = 5; i < 8; i++) {
      answers[i] = 1;
    }
    expect(PracticeDailyProgress.unlockedStage(answers), 3);
    expect(
      PracticeDailyProgress.canAdvance(
        currentQuestion: 7,
        answers: answers,
        progressive: true,
        completed: false,
      ),
      true,
    );
  });

  test('legacy cases remain fully accessible without stages', () {
    final session = PracticeDailySession.fromMap(<String, dynamic>{
      'ready': true,
      'completed': false,
      'day': '2026-10-09',
      'mode': 'cas_clinique',
      'case_stem': 'Scénario historique',
      'questions': List<Map<String, dynamic>>.generate(10, question),
    });
    expect(session.isProgressiveCase, false);
    expect(
      PracticeDailyProgress.canAdvance(
        currentQuestion: 1,
        answers: List<int?>.filled(10, null),
        progressive: false,
        completed: false,
      ),
      true,
    );
  });

  test('archived replay has ten concealed correct answers', () {
    final replay = PracticeDailySession.fromMap(<String, dynamic>{
      'day': '2026-10-09',
      'mode': 'cas_clinique',
      'ready': true,
      'replay': true,
      'completed': false,
      'official_score': 8,
      'replay_count': 3,
      'case_title': 'Simulation complète',
      'case_stem': '',
      'questions': List<Map<String, dynamic>>.generate(10, question),
    });
    expect(replay.isReplay, true);
    expect(replay.officialScore, 8);
    expect(replay.replayCount, 3);
    expect(replay.score, isNull);
    expect(replay.questions.every((q) => q.correctIndex == null), isTrue);
  });

  test('replay result is separate from immutable official score', () {
    final replay = PracticeDailySession.fromMap(<String, dynamic>{
      'day': '2026-10-09',
      'mode': 'cas_clinique',
      'ready': true,
      'replay': true,
      'completed': true,
      'official_score': 8,
      'score': 5,
      'replay_count': 2,
      'replay_id': 'd1901d5d-0cb4-43b2-95ec-70c0f22f4938',
      'questions': List<Map<String, dynamic>>.generate(10, (i) => {
        ...question(i),
        'selected_index': 0,
        'correct_index': 1,
        'correction': 'Correction documentée',
      }),
    });
    expect(replay.officialScore, 8);
    expect(replay.score, 5);
    expect(replay.replayCount, 2);
    expect(replay.questions.first.correction, isNotEmpty);
  });

  test('history displays original and latest replay scores separately', () {
    final entry = PracticeDailyHistoryEntry.fromMap(<String, dynamic>{
      'challenge_date': '2026-10-08',
      'mode': 'cas_clinique',
      'case_title': 'Cas progressif · pneumologie',
      'official_score': 7,
      'replay_count': 4,
      'last_replay_score': 9,
      'last_replay_at': '2026-10-09T01:20:00Z',
    });
    expect(entry.officialScore, 7);
    expect(entry.lastReplayScore, 9);
    expect(entry.replayCount, 4);
    expect(entry.day.day, 8);
  });

  test('history fails closed on missing official score', () {
    expect(
      () => PracticeDailyHistoryEntry.fromMap(<String, dynamic>{
        'challenge_date': '2026-10-08',
        'mode': 'cours',
      }),
      throwsStateError,
    );
  });

}
