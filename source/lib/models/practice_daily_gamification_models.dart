/// Gamification of first, official daily attempts only.
/// Replays contribute zero XP and do not affect streaks.
class PracticeDailyBadge {
  final String key;
  final String title;
  final String description;
  final String icon;
  final bool unlocked;

  const PracticeDailyBadge({
    required this.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.unlocked,
  });

  factory PracticeDailyBadge.fromMap(Map<String, dynamic> map) =>
      PracticeDailyBadge(
        key: '${map['key'] ?? ''}',
        title: '${map['title'] ?? ''}',
        description: '${map['description'] ?? ''}',
        icon: '${map['icon'] ?? ''}',
        unlocked: map['unlocked'] == true,
      );
}

class PracticeDailyGameProfile {
  final int totalXp;
  final int monthXp;
  final int daysCompleted;
  final int monthDays;
  final int perfectDays;
  final int currentStreak;
  final int bestStreak;
  final bool finishedToday;
  final int level;
  final String levelName;
  final int levelFloorXp;
  final int nextLevelXp;
  final List<PracticeDailyBadge> badges;

  const PracticeDailyGameProfile({
    this.totalXp = 0,
    this.monthXp = 0,
    this.daysCompleted = 0,
    this.monthDays = 0,
    this.perfectDays = 0,
    this.currentStreak = 0,
    this.bestStreak = 0,
    this.finishedToday = false,
    this.level = 1,
    this.levelName = 'Découvreur',
    this.levelFloorXp = 0,
    this.nextLevelXp = 300,
    this.badges = const <PracticeDailyBadge>[],
  });

  static int _number(dynamic value) => int.tryParse('$value') ?? 0;

  factory PracticeDailyGameProfile.fromMap(Map<String, dynamic> map) {
    final items = map['badges'];
    return PracticeDailyGameProfile(
      totalXp: _number(map['total_xp']),
      monthXp: _number(map['month_xp']),
      daysCompleted: _number(map['days_completed']),
      monthDays: _number(map['month_days']),
      perfectDays: _number(map['perfect_days']),
      currentStreak: _number(map['current_streak']),
      bestStreak: _number(map['best_streak']),
      finishedToday: map['finished_today'] == true,
      level: _number(map['level']).clamp(1, 10),
      levelName: '${map['level_name'] ?? 'Découvreur'}',
      levelFloorXp: _number(map['level_floor_xp']),
      nextLevelXp: _number(map['next_level_xp']),
      badges: items is List
          ? items
                .whereType<Map>()
                .map(
                  (item) => PracticeDailyBadge.fromMap(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList(growable: false)
          : const <PracticeDailyBadge>[],
    );
  }

  int get unlockedCount => badges.where((badge) => badge.unlocked).length;

  /// Percent towards the next daily challenge level.
  double get levelProgress {
    final remaining = nextLevelXp - levelFloorXp;
    if (remaining <= 0) return 1;
    return ((totalXp - levelFloorXp) / remaining).clamp(0.0, 1.0);
  }
}

class PracticeDailyGameRank {
  final int rank;
  final String userId;
  final String displayName;
  final String hospital;
  final int xp;
  final int completedDays;
  final int perfectDays;

  const PracticeDailyGameRank({
    required this.rank,
    required this.userId,
    required this.displayName,
    required this.hospital,
    required this.xp,
    required this.completedDays,
    required this.perfectDays,
  });

  factory PracticeDailyGameRank.fromMap(Map<String, dynamic> map) =>
      PracticeDailyGameRank(
        rank: int.tryParse('${map['rank']}') ?? 0,
        userId: '${map['user_id'] ?? ''}',
        displayName: '${map['display_name'] ?? 'Médecin'}',
        hospital: '${map['hospital'] ?? ''}',
        xp: int.tryParse('${map['xp']}') ?? 0,
        completedDays: int.tryParse('${map['completed_days']}') ?? 0,
        perfectDays: int.tryParse('${map['perfect_days']}') ?? 0,
      );
}
