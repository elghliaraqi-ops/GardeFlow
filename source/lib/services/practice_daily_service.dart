import 'dart:math';

import '../models/practice_daily_models.dart';
import 'supabase_backend_service.dart';

class PracticeDailyService {
  PracticeDailyService._();
  static final instance = PracticeDailyService._();
  SupabaseBackendService get _backend => SupabaseBackendService.instance;
  String get _userId {
    if (!_backend.enabled) throw StateError('Connexion indisponible.');
    final id = _backend.client.auth.currentUser?.id;
    if (id == null) throw StateError('Authentification requise.');
    return id;
  }

  Future<PracticeDailySession> current({String mode = 'cours'}) async {
    _userId;
    final res = await _backend.client.rpc(
      'practice_daily_open',
      params: <String, dynamic>{'p_mode': mode},
    );
    if (res is! Map) throw StateError('Défi indisponible.');
    return PracticeDailySession.fromMap(Map<String, dynamic>.from(res));
  }

  Future<PracticeDailySession> start(String mode) async {
    _userId;
    if (!const <String>['cours', 'cas_clinique'].contains(mode))
      throw ArgumentError('Mode invalide.');
    final existing = await current(mode: mode);
    if (existing.ready) return existing;
    final result = await _backend.client.functions.invoke(
      'generate-practice-daily-challenge',
      body: <String, dynamic>{'mode': mode},
    );
    final body = result.data;
    if (body is! Map || body['ok'] != true)
      throw StateError(
        body is Map && body['error'] == 'generation_in_progress'
            ? 'Le défi est en préparation. Réessayez dans quelques instants.'
            : 'Création du défi momentanément indisponible.',
      );
    final after = await current(mode: mode);
    if (!after.ready) throw StateError('Défi en cours de préparation.');
    return after;
  }

  Future<PracticeDailySession> finish({
    required String mode,
    required List<int> answers,
  }) async {
    _userId;
    if (answers.length != 10 || answers.any((x) => x < 0 || x > 3))
      throw StateError('Répondez aux 10 questions.');
    final res = await _backend.client.rpc(
      'practice_daily_finish',
      params: <String, dynamic>{'p_mode': mode, 'p_answers': answers},
    );
    if (res is! Map) throw StateError('Score indisponible.');
    final session = PracticeDailySession.fromMap(
      Map<String, dynamic>.from(res),
    );
    if (!session.completed || session.score == null)
      throw StateError('Score non enregistré.');
    return session;
  }

  Future<List<PracticeDailyCalendarEntry>> calendar(DateTime month) async {
    _userId;
    final day =
        '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}-01';
    final res = await _backend.client.rpc(
      'practice_daily_calendar',
      params: <String, dynamic>{'p_month': day},
    );
    if (res is! List) return const <PracticeDailyCalendarEntry>[];
    return res
        .whereType<Map>()
        .map(
          (m) =>
              PracticeDailyCalendarEntry.fromMap(Map<String, dynamic>.from(m)),
        )
        .toList(growable: false);
  }

  /// Completed daily challenges only. Original scores never change.
  Future<List<PracticeDailyHistoryEntry>> history({
    int limit = 40,
    int offset = 0,
  }) async {
    _userId;
    final res = await _backend.client.rpc(
      'practice_daily_history',
      params: <String, dynamic>{'p_limit': limit, 'p_offset': offset},
    );
    if (res is! List) throw StateError('Historique indisponible.');
    return res
        .whereType<Map>()
        .map((item) {
          return PracticeDailyHistoryEntry.fromMap(
            Map<String, dynamic>.from(item),
          );
        })
        .toList(growable: false);
  }

  String _dayParam(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  /// Opens replay without the answer keys. The daily attempt must be completed.
  Future<PracticeDailySession> openReplay(DateTime day) async {
    _userId;
    final response = await _backend.client.rpc(
      'practice_daily_replay_open',
      params: <String, dynamic>{'p_day': _dayParam(day)},
    );
    if (response is! Map) throw StateError('Rejeu indisponible.');
    final session = PracticeDailySession.fromMap(
      Map<String, dynamic>.from(response),
    );
    if (!session.ready ||
        session.completed ||
        !session.isReplay ||
        session.officialScore == null) {
      throw StateError('Défi non éligible au rejeu.');
    }
    return session;
  }

  /// Creates an idempotent request ID: repeated network submissions
  /// cannot inflate replay counts or overwrite original scores.
  String createReplayRequestId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<PracticeDailySession> finishReplay({
    required DateTime day,
    required List<int> answers,
    required String requestId,
  }) async {
    _userId;
    if (answers.length != 10 ||
        answers.any((answer) => answer < 0 || answer > 3)) {
      throw StateError('Les dix QCM doivent être complétés.');
    }
    final response = await _backend.client.rpc(
      'practice_daily_replay_finish',
      params: <String, dynamic>{
        'p_day': _dayParam(day),
        'p_answers': answers,
        'p_replay_id': requestId,
      },
    );
    if (response is! Map) throw StateError('Résultat du rejeu indisponible.');
    final session = PracticeDailySession.fromMap(
      Map<String, dynamic>.from(response),
    );
    if (!session.isReplay ||
        !session.completed ||
        session.score == null ||
        session.officialScore == null) {
      throw StateError('Le résultat du rejeu n’a pas été confirmé.');
    }
    return session;
  }

  Future<bool> remindersEnabled() async {
    final id = _userId;
    final row = await _backend.client
        .from('practice_daily_reminders')
        .select('enabled')
        .eq('user_id', id)
        .maybeSingle();
    return row?['enabled'] != false;
  }

  Future<void> setRemindersEnabled(bool enabled) async {
    final id = _userId;
    await _backend.client.from('practice_daily_reminders').upsert(
      <String, dynamic>{
        'user_id': id,
        'enabled': enabled,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'user_id',
    );
  }
}
