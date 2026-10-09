import '../models/practice_daily_gamification_models.dart';
import 'supabase_backend_service.dart';

class PracticeDailyGamificationService {
  PracticeDailyGamificationService._();

  static final instance = PracticeDailyGamificationService._();

  SupabaseBackendService get _backend => SupabaseBackendService.instance;

  String get currentUserId {
    if (!_backend.enabled) {
      throw StateError('Connexion nécessaire pour les défis quotidiens.');
    }
    final id = _backend.client.auth.currentUser?.id;
    if (id == null) throw StateError('Authentification requise.');
    return id;
  }

  Future<PracticeDailyGameProfile> profile() async {
    currentUserId;
    final response = await _backend.client.rpc('practice_daily_game_profile');
    if (response is! Map) {
      throw StateError('Progression des défis indisponible.');
    }
    return PracticeDailyGameProfile.fromMap(
      Map<String, dynamic>.from(response),
    );
  }

  Future<List<PracticeDailyGameRank>> leaderboard({
    String period = 'month',
    int limit = 30,
  }) async {
    currentUserId;
    if (period != 'month' && period != 'all') {
      throw ArgumentError('Période invalide.');
    }
    final response = await _backend.client.rpc(
      'practice_daily_game_leaderboard',
      params: <String, dynamic>{'p_period': period, 'p_limit': limit},
    );
    if (response is! List) {
      throw StateError('Classement des défis indisponible.');
    }
    return response
        .whereType<Map>()
        .map((row) {
          return PracticeDailyGameRank.fromMap(Map<String, dynamic>.from(row));
        })
        .toList(growable: false);
  }
}
