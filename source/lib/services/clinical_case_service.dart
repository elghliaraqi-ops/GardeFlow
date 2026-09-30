import 'package:flutter/foundation.dart';

import '../models/clinical_case_post.dart';
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
