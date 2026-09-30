import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/clinical_case_post.dart';
import '../models/qcm_models.dart';
import 'supabase_backend_service.dart';

class ClinicalCaseService {
  ClinicalCaseService._();
  static final ClinicalCaseService instance = ClinicalCaseService._();

  final ValueNotifier<int> revision = ValueNotifier<int>(0);
  final Set<String> _enrichmentRequested = <String>{};

  SupabaseBackendService get _backend => SupabaseBackendService.instance;

  void notifyChanged() => revision.value = revision.value + 1;

  Future<List<ClinicalCasePost>> fetchFeed({
    int offset = 0,
    int limit = 20,
  }) async {
    if (!_backend.enabled || _backend.client.auth.currentUser == null) {
      return const <ClinicalCasePost>[];
    }
    final response = await _backend.client.rpc(
      'clinical_case_feed',
      params: <String, dynamic>{
        'p_offset': offset,
        'p_limit': limit,
      },
    );
    if (response is! List) return const <ClinicalCasePost>[];
    final posts = response
        .whereType<Map>()
        .map((row) => ClinicalCasePost.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);

    // Les anciens cas/fallbacks sont enrichis en arrière-plan à la première
    // consultation. La requête est dédupliquée pour toute la session.
    for (final post in posts) {
      final needsAi = post.qcms.length < 5 ||
          post.qcms.any((qcm) => qcm.generationSource != 'openai');
      if (needsAi && _enrichmentRequested.add(post.id)) {
        unawaited(enrichQcmForPost(post.id));
      }
    }
    return posts;
  }

  /// Nouveau RPC : chaque cas dispose de cinq QCM indépendants. La correction
  /// IA et l'index correct ne sont renvoyés qu'après l'enregistrement du choix.
  Future<QcmAttemptResult> submitQcmAnswer({
    required String qcmId,
    required int selectedIndex,
  }) async {
    if (!_backend.enabled || _backend.client.auth.currentUser == null) {
      throw StateError('Authentification requise.');
    }

    final startedAt = DateTime.now();
    final beforeXp = await _practiceXp();
    final response = await _backend.client.rpc(
      'clinical_case_submit_qcm_answer',
      params: <String, dynamic>{
        'p_qcm_id': qcmId,
        'p_selected_index': selectedIndex,
      },
    );
    if (response is! List || response.isEmpty || response.first is! Map) {
      throw StateError('Réponse QCM non enregistrée.');
    }
    final result = QcmAttemptResult.fromMap(
      Map<String, dynamic>.from(response.first as Map),
    );
    notifyChanged();
    unawaited(_notifyAfterQcmAnswer(result, beforeXp, startedAt));
    return result;
  }

  /// Compatibilité avec l'ancien client mono-QCM. Ce chemin reste disponible
  /// tant que toutes les installations n'ont pas migré.
  Future<QcmAttemptResult> submitAnswer({
    required String postId,
    required int selectedIndex,
  }) async {
    if (!_backend.enabled || _backend.client.auth.currentUser == null) {
      throw StateError('Authentification requise.');
    }
    final response = await _backend.client.rpc(
      'clinical_case_submit_answer',
      params: <String, dynamic>{
        'p_post_id': postId,
        'p_selected_index': selectedIndex,
      },
    );
    if (response is! List || response.isEmpty || response.first is! Map) {
      throw StateError('Réponse QCM non enregistrée.');
    }
    final result = QcmAttemptResult.fromMap(
      Map<String, dynamic>.from(response.first as Map),
    );
    notifyChanged();
    return result;
  }

  Future<QcmStats> qcmSummary({String period = 'month'}) async {
    if (!_backend.enabled || _backend.client.auth.currentUser == null) {
      return const QcmStats();
    }
    final response = await _backend.client.rpc(
      'clinical_case_qcm_summary',
      params: <String, dynamic>{'p_period': period},
    );
    if (response is! List || response.isEmpty || response.first is! Map) {
      return const QcmStats();
    }
    return QcmStats.fromMap(Map<String, dynamic>.from(response.first as Map));
  }

  Future<QcmRanks> qcmRanks({String period = 'month'}) async {
    if (!_backend.enabled || _backend.client.auth.currentUser == null) {
      return const QcmRanks();
    }
    final response = await _backend.client.rpc(
      'clinical_case_qcm_my_ranks',
      params: <String, dynamic>{'p_period': period},
    );
    if (response is! List || response.isEmpty || response.first is! Map) {
      return const QcmRanks();
    }
    return QcmRanks.fromMap(Map<String, dynamic>.from(response.first as Map));
  }

  Future<List<QcmLeaderboardEntry>> qcmLeaderboard({
    String period = 'month',
    int? promotion,
  }) async {
    if (!_backend.enabled || _backend.client.auth.currentUser == null) {
      return const <QcmLeaderboardEntry>[];
    }
    final response = await _backend.client.rpc(
      'clinical_case_qcm_leaderboard',
      params: <String, dynamic>{
        'p_period': period,
        'p_promotion': promotion,
      },
    );
    if (response is! List) return const <QcmLeaderboardEntry>[];
    return response
        .whereType<Map>()
        .map((row) =>
            QcmLeaderboardEntry.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<void> enrichQcmForPracticeCase(String practiceCaseId) async {
    if (!_backend.enabled ||
        _backend.client.auth.currentUser == null ||
        practiceCaseId.trim().isEmpty) {
      return;
    }
    try {
      final response = await _backend.client.functions.invoke(
        'generate-clinical-case-qcm',
        body: <String, dynamic>{'practice_case_id': practiceCaseId.trim()},
      );
      final data = response.data;
      if (data is Map && data['count'] == 5) {
        unawaited(_triggerPush('practice_qcm_ready', practiceCaseId.trim()));
      }
      notifyChanged();
    } catch (_) {
      // Cinq fallbacks serveur existent déjà. L'enrichissement IA est best
      // effort et ne doit jamais bloquer l'enregistrement clinique.
    }
  }

  Future<void> enrichQcmForPost(String postId) async {
    if (!_backend.enabled ||
        _backend.client.auth.currentUser == null ||
        postId.trim().isEmpty) {
      return;
    }
    try {
      final response = await _backend.client.functions.invoke(
        'generate-clinical-case-qcm',
        body: <String, dynamic>{'post_id': postId.trim()},
      );
      final data = response.data;
      if (data is Map && data['count'] == 5) notifyChanged();
    } catch (_) {
      // Le feed conserve ses fallbacks si l'IA est temporairement indisponible.
    }
  }

  Future<int> _practiceXp() async {
    try {
      final response = await _backend.client.rpc(
        'practice_summary',
        params: const <String, dynamic>{'p_scope': 'all', 'p_guard_id': null},
      );
      if (response is List && response.isNotEmpty && response.first is Map) {
        return int.tryParse('${(response.first as Map)['xp'] ?? 0}') ?? 0;
      }
    } catch (_) {}
    return 0;
  }

  int _levelForXp(int xp) {
    const ceilings = <int>[100, 250, 500, 900, 1500, 2300, 3300, 5000, 7500];
    for (var i = 0; i < ceilings.length; i++) {
      if (xp < ceilings[i]) return i + 1;
    }
    return 10;
  }

  Future<void> _notifyAfterQcmAnswer(
    QcmAttemptResult result,
    int beforeXp,
    DateTime startedAt,
  ) async {
    final postId = result.postId?.trim() ?? '';
    if (postId.isNotEmpty && result.caseAnswered >= 5) {
      await _triggerPush(
        result.caseCorrect >= 5
            ? 'practice_qcm_perfect'
            : 'practice_qcm_complete',
        postId,
      );
    }

    final afterXp = await _practiceXp();
    if (postId.isNotEmpty && _levelForXp(afterXp) > _levelForXp(beforeXp)) {
      await _triggerPush('practice_level_up', postId);
    }

    // practice_my_achievements rafraîchit les succès côté serveur. Seuls ceux
    // débloqués pendant cette action sont poussés ; les succès historiques ne
    // provoquent donc pas une rafale de notifications lors de la mise à jour.
    try {
      final rows = await _backend.client.rpc('practice_my_achievements');
      if (rows is List) {
        for (final raw in rows.whereType<Map>()) {
          final unlockedAt =
              DateTime.tryParse('${raw['unlocked_at'] ?? ''}')?.toLocal();
          final key = '${raw['key'] ?? ''}'.trim();
          if (key.isEmpty || unlockedAt == null) continue;
          if (unlockedAt
              .isAfter(startedAt.subtract(const Duration(seconds: 5)))) {
            await _triggerPush('practice_achievement_unlocked', key);
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _triggerPush(String kind, String resourceId) async {
    try {
      await _backend.triggerPush(kind, resourceId);
    } catch (_) {
      // Une notification ne doit jamais rendre une action Practice échouée.
    }
  }
}
