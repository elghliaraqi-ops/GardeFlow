import 'package:flutter_test/flutter_test.dart';
import 'package:huim6_planning/models/practice_daily_gamification_models.dart';

void main() {
  test('daily challenge XP progression and badges parse', () {
    final result = PracticeDailyGameProfile.fromMap(<String, dynamic>{
      'total_xp': 380,
      'month_xp': 380,
      'days_completed': 3,
      'month_days': 3,
      'perfect_days': 1,
      'current_streak': 3,
      'best_streak': 3,
      'finished_today': true,
      'level': 2,
      'level_name': 'Explorateur',
      'level_floor_xp': 300,
      'next_level_xp': 800,
      'badges': [
        {'key': 'pioneer', 'title': 'Premier défi',
          'description': 'Premier défi terminé', 'icon': 'flag',
          'unlocked': true},
        {'key': 'week_streak', 'title': '7 jours de suite',
          'description': 'Série de 7', 'icon': 'fire',
          'unlocked': false},
      ],
    });
    expect(result.level, 2);
    expect(result.totalXp, 380);
    expect(result.currentStreak, 3);
    expect(result.unlockedCount, 1);
    expect(result.finishedToday, true);
    expect(result.levelProgress, closeTo(.16, .000001));
  });

  test('new doctors have zero challenge XP and first level', () {
    final profile = PracticeDailyGameProfile.fromMap(<String, dynamic>{
      'total_xp': 0,
      'level': 1,
      'next_level_xp': 300,
      'level_floor_xp': 0,
    });
    expect(profile.totalXp, 0);
    expect(profile.levelProgress, 0);
    expect(profile.unlockedCount, 0);
    expect(profile.daysCompleted, 0);
  });

  test('highest level has full progress without division by zero', () {
    final profile = PracticeDailyGameProfile.fromMap(<String, dynamic>{
      'total_xp': 19000,
      'level': 10,
      'level_floor_xp': 18000,
      'next_level_xp': 18000,
    });
    expect(profile.level, 10);
    expect(profile.levelProgress, 1.0);
  });

  test('daily ranking parses distinct XP and first attempts', () {
    final rank = PracticeDailyGameRank.fromMap(<String, dynamic>{
      'rank': 1,
      'user_id': 'sample',
      'display_name': 'Dr Example',
      'hospital': 'Hôpital universitaire',
      'xp': 380,
      'completed_days': 3,
      'perfect_days': 1,
    });
    expect(rank.rank, 1);
    expect(rank.xp, 380);
    expect(rank.completedDays, 3);
    expect(rank.perfectDays, 1);
  });
}
