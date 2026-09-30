class QcmAttemptResult {
  final int selectedIndex;
  final bool isCorrect;
  final DateTime? answeredAt;
  final int? correctIndex;
  final String correction;
  final String? postId;
  final int caseAnswered;
  final int caseCorrect;

  const QcmAttemptResult({
    required this.selectedIndex,
    required this.isCorrect,
    this.answeredAt,
    this.correctIndex,
    this.correction = '',
    this.postId,
    this.caseAnswered = 0,
    this.caseCorrect = 0,
  });

  factory QcmAttemptResult.fromMap(Map<String, dynamic> map) =>
      QcmAttemptResult(
        selectedIndex: int.tryParse('${map['selected_index'] ?? 0}') ?? 0,
        isCorrect: map['is_correct'] == true,
        answeredAt: DateTime.tryParse('${map['answered_at'] ?? ''}')?.toLocal(),
        correctIndex: map['correct_index'] == null
            ? null
            : int.tryParse('${map['correct_index']}'),
        correction: '${map['correction'] ?? ''}'.trim(),
        postId: map['post_id']?.toString(),
        caseAnswered: int.tryParse('${map['case_answered'] ?? 0}') ?? 0,
        caseCorrect: int.tryParse('${map['case_correct'] ?? 0}') ?? 0,
      );
}

class QcmStats {
  final int answered;
  final int correct;
  final double accuracy;

  const QcmStats({this.answered = 0, this.correct = 0, this.accuracy = 0});

  factory QcmStats.fromMap(Map<String, dynamic> map) => QcmStats(
        answered: int.tryParse('${map['answered'] ?? 0}') ?? 0,
        correct: int.tryParse('${map['correct'] ?? 0}') ?? 0,
        accuracy: double.tryParse('${map['accuracy'] ?? 0}') ?? 0,
      );
}

class QcmRanks extends QcmStats {
  final int? globalRank;
  final int? promotionRank;
  final int? promotionNumber;
  final bool leaderboardOptIn;

  const QcmRanks({
    super.answered,
    super.correct,
    super.accuracy,
    this.globalRank,
    this.promotionRank,
    this.promotionNumber,
    this.leaderboardOptIn = true,
  });

  factory QcmRanks.fromMap(Map<String, dynamic> map) => QcmRanks(
        answered: int.tryParse('${map['answered'] ?? 0}') ?? 0,
        correct: int.tryParse('${map['correct'] ?? 0}') ?? 0,
        accuracy: double.tryParse('${map['accuracy'] ?? 0}') ?? 0,
        globalRank: int.tryParse('${map['global_rank'] ?? ''}'),
        promotionRank: int.tryParse('${map['promotion_rank'] ?? ''}'),
        promotionNumber: int.tryParse('${map['promotion_number'] ?? ''}'),
        leaderboardOptIn: map['leaderboard_opt_in'] != false,
      );
}

class QcmLeaderboardEntry {
  final int rank;
  final String userId;
  final String displayName;
  final int? promotionNumber;
  final int correct;
  final int answered;
  final double accuracy;

  const QcmLeaderboardEntry({
    required this.rank,
    required this.userId,
    required this.displayName,
    this.promotionNumber,
    required this.correct,
    required this.answered,
    required this.accuracy,
  });

  factory QcmLeaderboardEntry.fromMap(Map<String, dynamic> map) =>
      QcmLeaderboardEntry(
        rank: int.tryParse('${map['rank'] ?? 0}') ?? 0,
        userId: '${map['user_id'] ?? ''}',
        displayName: '${map['display_name'] ?? 'Médecin'}'.trim(),
        promotionNumber: int.tryParse('${map['promotion_number'] ?? ''}'),
        correct: int.tryParse('${map['correct'] ?? 0}') ?? 0,
        answered: int.tryParse('${map['answered'] ?? 0}') ?? 0,
        accuracy: double.tryParse('${map['accuracy'] ?? 0}') ?? 0,
      );
}
