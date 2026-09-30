import 'package:flutter/foundation.dart';

import '../models/clinical_case_post.dart';
import '../models/qcm_models.dart';
import 'supabase_backend_service.dart';

class ClinicalCaseService {
  ClinicalCaseService._();
  static final ClinicalCaseService instance = ClinicalCaseService._();

  final ValueNotifier<int> revision = ValueNotifier<int>(0);

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
    return response
        .whereType<Map>()
        .map((row) => ClinicalCasePost.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
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
        .map((row) => QcmLeaderboardEntry.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<void> enrichQcmForPracticeCase(String practiceCaseId) async {
    if (!_backend.enabled ||
        _backend.client.auth.currentUser == null ||
        practiceCaseId.trim().isEmpty) {
      return;
    }
    try {
      await _backend.client.functions.invoke(
        'generate-clinical-case-qcm',
        body: <String, dynamic>{'practice_case_id': practiceCaseId.trim()},
      );
      notifyChanged();
    } catch (_) {
      // A deterministic server-side QCM is already present. AI enrichment is
      // deliberately best-effort so it can never block a clinical save.
    }
  }
}
