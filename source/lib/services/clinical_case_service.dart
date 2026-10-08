import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/clinical_case_post.dart';
import '../models/qcm_models.dart';
import 'qcm_generation_retry_policy.dart';
import 'supabase_backend_service.dart';

class ClinicalCaseService {
  ClinicalCaseService._();
  static final ClinicalCaseService instance = ClinicalCaseService._();

  final ValueNotifier<int> revision = ValueNotifier<int>(0);
  final Set<String> _enrichmentInFlight = <String>{};
  final Map<String, _QcmRetryState> _retryStates = <String, _QcmRetryState>{};

  String? _retryUserId;
  bool _retryStateLoaded = false;
  Future<void>? _retryLoadFuture;

  SupabaseBackendService get _backend => SupabaseBackendService.instance;

  void notifyChanged() => revision.value = revision.value + 1;

  Future<List<ClinicalCasePost>> fetchFeed({
    int offset = 0,
    int limit = 20,
  }) async {
    if (!_backend.enabled || _backend.client.auth.currentUser == null) {
      return const <ClinicalCasePost>[];
    }
    await _ensureRetryStateLoaded();

    dynamic response;
    try {
      response = await _backend.client.rpc(
        'clinical_case_feed_v2',
        params: <String, dynamic>{'p_offset': offset, 'p_limit': limit},
      );
    } catch (_) {
      // Backward-compatible fallback while a backend migration is propagating.
      response = await _backend.client.rpc(
        'clinical_case_feed',
        params: <String, dynamic>{'p_offset': offset, 'p_limit': limit},
      );
    }
    if (response is! List) return const <ClinicalCasePost>[];
    final posts = response
        .whereType<Map>()
        .map((row) => ClinicalCasePost.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);

    // A UI rebuild/refresh is not a retry policy. Automatic enrichment is
    // deduplicated in memory and backed by a persisted, bounded cooldown.
    final now = DateTime.now().toUtc();
    for (final post in posts) {
      final needsAi = post.qcms.length < 5 ||
          post.qcms.any((qcm) => qcm.generationSource != 'openai');
      if (!needsAi || !_canAutoAttempt(post.id, now)) continue;
      if (!_enrichmentInFlight.add(post.id)) continue;
      unawaited(
        _enrichQcmForPost(post.id).whenComplete(() {
          _enrichmentInFlight.remove(post.id);
        }),
      );
    }
    return posts;
  }

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
    final params = <String, dynamic>{'p_period': period};
    if (promotion != null) params['p_promotion'] = promotion;
    final response = await _backend.client.rpc(
      'clinical_case_qcm_leaderboard',
      params: params,
    );
    if (response is! List) return const <QcmLeaderboardEntry>[];
    return response
        .whereType<Map>()
        .map(
          (row) => QcmLeaderboardEntry.fromMap(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

  Future<int> resetMyQcmAnswers({required String postId}) async {
    if (!_backend.enabled || _backend.client.auth.currentUser == null) {
      throw StateError('Authentification requise.');
    }
    final response = await _backend.client.rpc(
      'clinical_case_reset_my_qcm_answers',
      params: <String, dynamic>{'p_post_id': postId},
    );
    final count = int.tryParse('$response') ?? 0;
    notifyChanged();
    return count;
  }

  /// Ajoute cinq nouvelles questions uniquement : ne relance jamais la
  /// génération initiale et ne supprime ni réponses ni statistiques.
  Future<int> addQcmsToClinicalCase({required String postId}) async {
    final id = postId.trim();
    if (!_backend.enabled ||
        _backend.client.auth.currentUser == null ||
        id.isEmpty) {
      throw StateError('Authentification requise.');
    }
    try {
      final response = await _backend.client.functions.invoke(
        'generate-clinical-case-qcm',
        body: <String, dynamic>{
          'post_id': id,
          'append_qcms': true,
        },
      );
      final data = response.data;
      if (data is Map && data['ok'] == true && data['added'] == 5) {
        notifyChanged();
        return int.tryParse('${data['count']}') ?? 0;
      }
      final code = data is Map ? '${data['error'] ?? ''}' : '';
      if (code == 'generation_in_progress') {
        throw StateError('Une génération est déjà en cours pour ce cas.');
      }
      if (code == 'extension_cooldown') {
        throw StateError('Réessayez dans quelques minutes.');
      }
      if (code == 'qcm_limit_reached') {
        throw StateError('Ce cas a atteint sa limite de 100 QCM.');
      }
      throw StateError('Ajout des QCM indisponible pour le moment.');
    } catch (error) {
      if (error is StateError) rethrow;
      throw StateError(
        'Échec de la génération. Vérifiez la connexion puis réessayez.',
      );
    }
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
      if (data is Map && data['count'] == 5 && data['ok'] == true) {
        unawaited(_triggerPush('practice_qcm_ready', practiceCaseId.trim()));
        notifyChanged();
      }
    } catch (_) {
      // L'enregistrement du cas reste indépendant du fournisseur IA.
    }
  }

  /// Manual retry deliberately reaches the authoritative server guard. Local
  /// persisted cooldowns only throttle automatic background retries; the Edge
  /// Function remains responsible for lock, cooldown and rate-limit decisions.
  Future<void> enrichQcmForPost(String postId) async {
    if (!_backend.enabled ||
        _backend.client.auth.currentUser == null ||
        postId.trim().isEmpty) {
      return;
    }
    await _ensureRetryStateLoaded();
    final id = postId.trim();
    if (!_enrichmentInFlight.add(id)) return;
    try {
      await _enrichQcmForPost(id);
    } finally {
      _enrichmentInFlight.remove(id);
    }
  }

  bool canRetryQcmManually(String postId) {
    final id = postId.trim();
    return id.isNotEmpty && !_enrichmentInFlight.contains(id);
  }

  DateTime? qcmRetryAfter(String postId) => _retryStates[postId]?.nextAttemptAt;

  Future<void> _enrichQcmForPost(String postId) async {
    if (!_backend.enabled || _backend.client.auth.currentUser == null) return;
    try {
      final response = await _backend.client.functions.invoke(
        'generate-clinical-case-qcm',
        body: <String, dynamic>{'post_id': postId},
      );
      final data = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      final status = response.status;

      if (data['ok'] == true && data['count'] == 5) {
        await _clearRetryState(postId);
        notifyChanged();
        return;
      }

      final code = '${data['error'] ?? data['reason'] ?? 'qcm_unavailable'}';
      final retryable = data['retryable'] is bool
          ? data['retryable'] as bool
          : QcmGenerationRetryPolicy.isRetryableHttpStatus(status);
      final retryAfter = _parseRetryAfter(data);
      if (status == 202 || code == 'generation_in_progress') {
        await _deferWithoutFailure(postId, retryAfter);
        return;
      }
      await _registerFailure(
        postId,
        retryable: retryable &&
            !QcmGenerationRetryPolicy.isPermanentHttpStatus(status),
        retryAfter: retryAfter,
        errorCode: code,
      );
    } catch (error) {
      final status = _exceptionStatus(error);
      final details = _exceptionDetails(error);
      final retryable = details['retryable'] is bool
          ? details['retryable'] as bool
          : QcmGenerationRetryPolicy.isRetryableHttpStatus(status);
      final code =
          '${details['error'] ?? details['reason'] ?? 'network_or_function_error'}';
      await _registerFailure(
        postId,
        retryable: retryable &&
            !QcmGenerationRetryPolicy.isPermanentHttpStatus(status),
        retryAfter: _parseRetryAfter(details),
        errorCode: code,
      );
    }
  }

  Future<void> _ensureRetryStateLoaded() async {
    final userId = _backend.client.auth.currentUser?.id;
    if (userId == null) return;
    if (_retryStateLoaded && _retryUserId == userId) return;
    if (_retryLoadFuture != null && _retryUserId == userId) {
      await _retryLoadFuture;
      return;
    }

    _retryUserId = userId;
    _retryStateLoaded = false;
    _retryStates.clear();
    _retryLoadFuture = _loadRetryState(userId);
    try {
      await _retryLoadFuture;
    } finally {
      _retryLoadFuture = null;
    }
  }

  Future<void> _loadRetryState(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_retryPrefsKey(userId));
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final now = DateTime.now().toUtc();
      for (final entry in decoded.entries) {
        if (entry.value is! Map) continue;
        final state = _QcmRetryState.fromMap(
          Map<String, dynamic>.from(entry.value as Map),
        );
        if (state == null) continue;
        if (now.difference(state.firstFailureAt) >
            QcmGenerationRetryPolicy.resetWindow) {
          continue;
        }
        _retryStates['${entry.key}'] = state;
      }
    } catch (_) {
      _retryStates.clear();
    } finally {
      _retryStateLoaded = true;
    }
  }

  Future<void> _persistRetryState() async {
    final userId = _retryUserId;
    if (userId == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _retryPrefsKey(userId),
        jsonEncode(<String, dynamic>{
          for (final entry in _retryStates.entries)
            entry.key: entry.value.toMap(),
        }),
      );
    } catch (_) {
      // Local persistence is defensive and must never break Practice.
    }
  }

  // v2 intentionally invalidates persisted OpenAI-era failures after the
  // provider migration to Gemini. Server-side locking/rate limits still guard
  // against duplicate generation, so old devices cannot create a request storm.
  String _retryPrefsKey(String userId) => 'qcm_generation_retry_v2_$userId';

  bool _canAutoAttempt(String postId, DateTime now) {
    final state = _retryStates[postId];
    if (state == null) return !_enrichmentInFlight.contains(postId);
    if (now.difference(state.firstFailureAt) >
        QcmGenerationRetryPolicy.resetWindow) {
      _retryStates.remove(postId);
      unawaited(_persistRetryState());
      return !_enrichmentInFlight.contains(postId);
    }
    if (state.permanent || state.automaticSuspended) return false;
    if (now.isBefore(state.nextAttemptAt)) return false;
    return !_enrichmentInFlight.contains(postId);
  }

  Future<void> _deferWithoutFailure(
      String postId, DateTime? serverRetry) async {
    final now = DateTime.now().toUtc();
    final current = _retryStates[postId];
    final next = serverRetry != null && serverRetry.isAfter(now)
        ? serverRetry
        : now.add(const Duration(minutes: 1));
    _retryStates[postId] = _QcmRetryState(
      failureCount: current?.failureCount ?? 0,
      firstFailureAt: current?.firstFailureAt ?? now,
      nextAttemptAt: next,
      permanent: false,
      automaticSuspended: current?.automaticSuspended ?? false,
      lastErrorCode: 'generation_in_progress',
    );
    await _persistRetryState();
  }

  Future<void> _registerFailure(
    String postId, {
    required bool retryable,
    required DateTime? retryAfter,
    required String errorCode,
  }) async {
    final now = DateTime.now().toUtc();
    final previous = _retryStates[postId];
    final withinWindow = previous != null &&
        now.difference(previous.firstFailureAt) <=
            QcmGenerationRetryPolicy.resetWindow;
    final failureCount = (withinWindow ? previous.failureCount : 0) + 1;
    final firstFailureAt = withinWindow ? previous.firstFailureAt : now;
    var next = now.add(QcmGenerationRetryPolicy.delayForFailure(failureCount));
    if (retryAfter != null && retryAfter.isAfter(next)) next = retryAfter;

    _retryStates[postId] = _QcmRetryState(
      failureCount: failureCount,
      firstFailureAt: firstFailureAt,
      nextAttemptAt: next,
      permanent: !retryable,
      automaticSuspended:
          failureCount >= QcmGenerationRetryPolicy.maxAutomaticFailures,
      lastErrorCode:
          errorCode.length <= 80 ? errorCode : errorCode.substring(0, 80),
    );
    await _persistRetryState();
  }

  Future<void> _clearRetryState(String postId) async {
    if (_retryStates.remove(postId) != null) await _persistRetryState();
  }

  DateTime? _parseRetryAfter(Map<String, dynamic> data) {
    final raw = data['retry_after'];
    if (raw != null) {
      final parsed = DateTime.tryParse('$raw')?.toUtc();
      if (parsed != null) return parsed;
    }
    final seconds = int.tryParse('${data['retry_after_seconds'] ?? ''}');
    if (seconds != null && seconds > 0) {
      return DateTime.now().toUtc().add(Duration(seconds: seconds));
    }
    return null;
  }

  int? _exceptionStatus(Object error) {
    try {
      final value = (error as dynamic).status;
      if (value is int) return value;
      return int.tryParse('$value');
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _exceptionDetails(Object error) {
    try {
      final value = (error as dynamic).details;
      if (value is Map) return Map<String, dynamic>.from(value);
    } catch (_) {}
    return const <String, dynamic>{};
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

    try {
      final rows = await _backend.client.rpc('practice_my_achievements');
      if (rows is List) {
        for (final raw in rows.whereType<Map>()) {
          final unlockedAt =
              DateTime.tryParse('${raw['unlocked_at'] ?? ''}')?.toLocal();
          final key = '${raw['key'] ?? ''}'.trim();
          if (key.isEmpty || unlockedAt == null) continue;
          if (unlockedAt.isAfter(
            startedAt.subtract(const Duration(seconds: 5)),
          )) {
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
      // A notification must never make a Practice action fail.
    }
  }
}

class _QcmRetryState {
  final int failureCount;
  final DateTime firstFailureAt;
  final DateTime nextAttemptAt;
  final bool permanent;
  final bool automaticSuspended;
  final String lastErrorCode;

  const _QcmRetryState({
    required this.failureCount,
    required this.firstFailureAt,
    required this.nextAttemptAt,
    required this.permanent,
    required this.automaticSuspended,
    required this.lastErrorCode,
  });

  Map<String, dynamic> toMap() => <String, dynamic>{
        'failure_count': failureCount,
        'first_failure_at': firstFailureAt.toUtc().toIso8601String(),
        'next_attempt_at': nextAttemptAt.toUtc().toIso8601String(),
        'permanent': permanent,
        'automatic_suspended': automaticSuspended,
        'last_error_code': lastErrorCode,
      };

  static _QcmRetryState? fromMap(Map<String, dynamic> map) {
    final first =
        DateTime.tryParse('${map['first_failure_at'] ?? ''}')?.toUtc();
    final next = DateTime.tryParse('${map['next_attempt_at'] ?? ''}')?.toUtc();
    if (first == null || next == null) return null;
    return _QcmRetryState(
      failureCount: int.tryParse('${map['failure_count'] ?? 0}') ?? 0,
      firstFailureAt: first,
      nextAttemptAt: next,
      permanent: map['permanent'] == true,
      automaticSuspended: map['automatic_suspended'] == true,
      lastErrorCode: '${map['last_error_code'] ?? ''}',
    );
  }
}
