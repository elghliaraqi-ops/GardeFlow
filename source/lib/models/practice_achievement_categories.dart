import 'practice_models.dart';

const practiceAchievementCategories = <String>[
  'Tous', 'QCM', 'Défis quotidiens', 'Cas cliniques',
  'Simulations IA', 'Assiduité', 'XP & niveaux',
];

String practiceAchievementCategory(PracticeAchievement achievement) {
  final key = achievement.key.toLowerCase();
  if (key.startsWith('qcm_') ||
      key.startsWith('v2_qcm_') ||
      key.startsWith('v2_réussite_') ||
      key.startsWith('v2_précision')) return 'QCM';
  if (key.startsWith('v2_quotidien_') ||
      key.startsWith('v2_sans-faute_') ||
      key.startsWith('v2_score-jour_')) return 'Défis quotidiens';
  if (key.startsWith('v2_progressif_') ||
      key.startsWith('v2_spécialités_')) return 'Simulations IA';
  if (key.startsWith('guards_') || key.startsWith('streak_') ||
      key.startsWith('v2_gardes_') || key.startsWith('v2_série_') ||
      key.startsWith('v2_assiduité_')) return 'Assiduité';
  if (key.startsWith('practice_xp_') || key.startsWith('v2_xp_')) {
    return 'XP & niveaux';
  }
  return 'Cas cliniques';
}
