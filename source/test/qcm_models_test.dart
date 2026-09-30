import 'package:flutter_test/flutter_test.dart';
import 'package:huim6_planning/models/qcm_models.dart';

void main() {
  test('parses QCM statistics', () {
    final stats = QcmStats.fromMap({
      'answered': 12,
      'correct': 9,
      'accuracy': 75.0,
    });
    expect(stats.answered, 12);
    expect(stats.correct, 9);
    expect(stats.accuracy, 75.0);
  });

  test('parses QCM ranking context', () {
    final ranks = QcmRanks.fromMap({
      'answered': 7,
      'correct': 5,
      'accuracy': 71.4,
      'global_rank': 4,
      'promotion_rank': 2,
      'promotion_number': 6,
      'leaderboard_opt_in': true,
    });
    expect(ranks.globalRank, 4);
    expect(ranks.promotionRank, 2);
    expect(ranks.promotionNumber, 6);
    expect(ranks.leaderboardOptIn, isTrue);
  });

  test('parses first persisted QCM answer', () {
    final attempt = QcmAttemptResult.fromMap({
      'selected_index': 2,
      'is_correct': true,
      'answered_at': '2026-09-30T00:20:00Z',
    });
    expect(attempt.selectedIndex, 2);
    expect(attempt.isCorrect, isTrue);
    expect(attempt.answeredAt, isNotNull);
  });
}
