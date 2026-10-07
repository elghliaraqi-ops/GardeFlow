import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/practice_models.dart';
import 'supabase_backend_service.dart';
import 'clinical_case_service.dart';

class PracticeSaveResult {
  final PracticeCase value;
  final bool pendingSync;
  const PracticeSaveResult(this.value, {required this.pendingSync});
}

class PracticeService {
  PracticeService._();
  static final PracticeService instance = PracticeService._();

  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static const _pendingKeyPrefix = 'guardeflow_practice_pending_v1_';
  static const _draftKeyPrefix = 'guardeflow_practice_draft_v1_';

  SupabaseBackendService get _backend => SupabaseBackendService.instance;

  String? get _authUserId =>
      _backend.enabled ? _backend.client.auth.currentUser?.id : null;

  void _notify() => revision.value = revision.value + 1;

  Future<PracticeStats> summary({
    required String scope,
    String? guardId,
  }) async {
    PracticeStats remote = const PracticeStats();
    if (_backend.enabled && _authUserId != null) {
      final response = await _backend.client.rpc(
        'practice_summary',
        params: <String, dynamic>{
          'p_scope': scope,
          'p_guard_id': guardId,
        },
      );
      final rows = response is List ? response : const <dynamic>[];
      if (rows.isNotEmpty && rows.first is Map) {
        remote =
            PracticeStats.fromMap(Map<String, dynamic>.from(rows.first as Map));
      }
    }
    return _mergePendingStats(remote, scope: scope, guardId: guardId);
  }

  Future<List<int>> monthlyCounts({int? year}) async {
    final values = List<int>.filled(12, 0);
    if (!_backend.enabled || _authUserId == null) return values;
    final response = await _backend.client.rpc(
      'practice_monthly_counts',
      params: <String, dynamic>{'p_year': year},
    );
    if (response is List) {
      for (final raw in response) {
        if (raw is! Map) continue;
        final row = Map<String, dynamic>.from(raw);
        final month = int.tryParse('${row['month']}') ?? 0;
        if (month < 1 || month > 12) continue;
        values[month - 1] = int.tryParse('${row['patients']}') ?? 0;
      }
    }
    return values;
  }

  Future<PracticePreferences> preferences() async {
    final uid = _authUserId;
    if (!_backend.enabled || uid == null) return const PracticePreferences();
    final row = await _backend.client
        .from('practice_preferences')
        .select()
        .eq('user_id', uid)
        .maybeSingle();
    if (row == null) return const PracticePreferences();
    return PracticePreferences.fromMap(Map<String, dynamic>.from(row));
  }

  Future<void> savePreferences({
    required bool leaderboardOptIn,
    int? guardGoal,
  }) async {
    final uid = _authUserId;
    if (!_backend.enabled || uid == null) return;
    await _backend.client.from('practice_preferences').upsert(
      <String, dynamic>{
        'user_id': uid,
        'leaderboard_opt_in': leaderboardOptIn,
        'guard_goal': guardGoal,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'user_id',
    );
    _notify();
  }

  Future<PracticeRanks> ranks({String period = 'month'}) async {
    if (!_backend.enabled || _authUserId == null) return const PracticeRanks();
    final response = await _backend.client.rpc(
      'practice_my_ranks',
      params: <String, dynamic>{'p_period': period},
    );
    final rows = response is List ? response : const <dynamic>[];
    if (rows.isEmpty || rows.first is! Map) return const PracticeRanks();
    return PracticeRanks.fromMap(Map<String, dynamic>.from(rows.first as Map));
  }

  Future<List<PracticeRankEntry>> leaderboard({
    String period = 'month',
    int? promotion,
  }) async {
    if (!_backend.enabled || _authUserId == null)
      return const <PracticeRankEntry>[];
    final params = <String, dynamic>{'p_period': period};
    if (promotion != null) params['p_promotion'] = promotion;
    final response =
        await _backend.client.rpc('practice_leaderboard', params: params);
    if (response is! List) return const <PracticeRankEntry>[];
    return response
        .whereType<Map>()
        .map((row) => PracticeRankEntry.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<List<PracticeAchievement>> achievements() async {
    if (!_backend.enabled || _authUserId == null)
      return const <PracticeAchievement>[];
    final response = await _backend.client.rpc('practice_my_achievements');
    if (response is! List) return const <PracticeAchievement>[];
    return response
        .whereType<Map>()
        .map((row) =>
            PracticeAchievement.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<int> nextPatientNumber(PracticeGuard guard) async {
    if (_backend.enabled && _authUserId != null) {
      try {
        final response = await _backend.client.rpc(
          'practice_next_patient_number',
          params: <String, dynamic>{'p_guard_id': guard.id},
        );
        final parsed = int.tryParse('$response');
        if (parsed != null && parsed > 0) return parsed;
      } catch (_) {
        // Fallback local below. Server remains authoritative at sync time.
      }
    }
    var maxNumber = 0;
    final pending = await pendingCases();
    for (final item in pending.where((item) => item.guardId == guard.id)) {
      if (item.patientNumber > maxNumber) maxNumber = item.patientNumber;
    }
    try {
      final remote = await fetchCases(
          guardId: guard.id, limit: 1000, includePending: false);
      for (final item in remote) {
        if (item.patientNumber > maxNumber) maxNumber = item.patientNumber;
      }
    } catch (_) {}
    return maxNumber + 1;
  }

  Future<List<PracticeCase>> fetchCases({
    String? guardId,
    String scope = 'all',
    String? status,
    int offset = 0,
    int limit = 50,
    bool includePending = true,
  }) async {
    final uid = _authUserId;
    final remote = <PracticeCase>[];
    if (_backend.enabled && uid != null) {
      dynamic query = _backend.client
          .from('practice_cases')
          .select()
          .eq('user_id', uid)
          .eq('encounter_context', practiceEmergencyEncounterContext)
          .eq('is_draft', false);
      if (guardId != null) query = query.eq('guard_id', guardId);
      if (scope == 'month' || scope == 'year') {
        final now = DateTime.now();
        final start = scope == 'month'
            ? DateTime(now.year, now.month)
            : DateTime(now.year);
        final end = scope == 'month'
            ? DateTime(now.year, now.month + 1)
            : DateTime(now.year + 1);
        query = query
            .gte('guard_date', _dateKey(start))
            .lt('guard_date', _dateKey(end));
      }
      if (status != null) {
        switch (status) {
          case 'waiting':
            query = query.eq('waiting', true);
            break;
          case 'specialist':
            query = query.eq('specialist_opinion_requested', true);
            break;
          case 'discharged':
            query = query.eq('discharged', true);
            break;
          case 'hospitalized':
            query = query.eq('hospitalized', true);
            break;
          case 'prescription':
            query = query.eq('prescription_done', true);
            break;
        }
      }
      final response = await query
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);
      if (response is List) {
        remote.addAll(response.whereType<Map>().map(
            (row) => PracticeCase.fromMap(Map<String, dynamic>.from(row))));
      }
    }

    if (!includePending || offset > 0) return remote;
    final pending = await pendingCases();
    final filtered = pending.where((item) {
      if (item.isStandalone) return false;
      if (guardId != null && item.guardId != guardId) return false;
      if (scope == 'month' || scope == 'year') {
        final date = DateTime.tryParse(item.guardDate);
        if (date == null) return false;
        final now = DateTime.now();
        if (scope == 'month' &&
            (date.year != now.year || date.month != now.month)) return false;
        if (scope == 'year' && date.year != now.year) return false;
      }
      switch (status) {
        case 'waiting':
          return item.waiting;
        case 'specialist':
          return item.specialistOpinionRequested;
        case 'discharged':
          return item.discharged;
        case 'hospitalized':
          return item.hospitalized;
        case 'prescription':
          return item.prescriptionDone;
      }
      return true;
    });
    final remoteClientIds = remote.map((item) => item.clientId).toSet();
    return <PracticeCase>[
      ...filtered.where((item) => !remoteClientIds.contains(item.clientId)),
      ...remote,
    ];
  }

  Future<PracticeCase?> fetchCaseById(String id) async {
    final uid = _authUserId;
    final caseId = id.trim();
    if (!_backend.enabled || uid == null || caseId.isEmpty) return null;
    final row = await _backend.client
        .from('practice_cases')
        .select()
        .eq('id', caseId)
        .eq('user_id', uid)
        .maybeSingle();
    if (row == null) return null;
    return PracticeCase.fromMap(Map<String, dynamic>.from(row));
  }

  Future<PracticeSaveResult> saveValidated(PracticeCase value) async {
    final normalized = value.copyWith(isDraft: false, pendingSync: false);
    if (!normalized.isValid) {
      throw StateError(
          'Le motif de consultation et au moins une section clinique sont obligatoires.');
    }
    if (_backend.enabled && _authUserId != null) {
      try {
        final saved = await _saveRemote(normalized);
        await _removePending(saved.clientId);
        _notify();
        return PracticeSaveResult(saved, pendingSync: false);
      } catch (_) {
        // Network/server interruption: keep a durable local outbox copy.
      }
    }
    final queued = normalized.copyWith(pendingSync: true);
    await _putPending(queued);
    _notify();
    return PracticeSaveResult(queued, pendingSync: true);
  }

  Future<PracticeCase> _saveRemote(PracticeCase value) async {
    final isNew = value.id == null || value.id!.isEmpty;
    final activityStartedAt = DateTime.now();
    PracticeStats? beforeAll;
    if (isNew) {
      try {
        beforeAll = await summary(scope: 'all');
      } catch (_) {}
    }

    final payload = value.toMap(includeId: false)
      ..['is_draft'] = false
      ..['synced_at'] = DateTime.now().toUtc().toIso8601String();
    dynamic response;
    if (isNew) {
      response = await _backend.client
          .from('practice_cases')
          .insert(payload)
          .select()
          .single();
    } else {
      response = await _backend.client
          .from('practice_cases')
          .update(payload)
          .eq('id', value.id!)
          .select()
          .single();
    }
    final saved =
        PracticeCase.fromMap(Map<String, dynamic>.from(response as Map));
    final savedId = saved.id?.trim() ?? '';
    if (savedId.isNotEmpty) {
      ClinicalCaseService.instance.notifyChanged();
      unawaited(ClinicalCaseService.instance.enrichQcmForPracticeCase(savedId));
      if (isNew && !saved.isStandalone) {
        unawaited(_notifyAfterNewCase(saved, beforeAll, activityStartedAt));
      }
    }
    return saved;
  }

  Future<void> _notifyAfterNewCase(
    PracticeCase saved,
    PracticeStats? beforeAll,
    DateTime activityStartedAt,
  ) async {
    final savedId = saved.id?.trim() ?? '';
    if (savedId.isEmpty || !_backend.enabled || _authUserId == null) return;

    await _triggerPracticePush('practice_case_created', savedId);
    await _triggerPracticePush('practice_goal_reached', saved.guardId);
    await _triggerPracticePush('practice_case_milestone', savedId);

    try {
      final afterAll = await summary(scope: 'all');
      if (beforeAll != null) {
        if (practiceLevelForXp(afterAll.xp).number >
            practiceLevelForXp(beforeAll.xp).number) {
          await _triggerPracticePush('practice_level_up', savedId);
        }
        if (afterAll.streak > beforeAll.streak && afterAll.streak >= 3) {
          await _triggerPracticePush('practice_streak', savedId);
        }
      }
    } catch (_) {}

    try {
      final rows = await achievements();
      for (final achievement in rows) {
        final unlockedAt = achievement.unlockedAt;
        if (unlockedAt == null) continue;
        if (unlockedAt.isAfter(
          activityStartedAt.subtract(const Duration(seconds: 5)),
        )) {
          await _triggerPracticePush(
            'practice_achievement_unlocked',
            achievement.key,
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _triggerPracticePush(String kind, String resourceId) async {
    try {
      await _backend.triggerPush(kind, resourceId);
    } catch (_) {
      // La notification est best-effort et ne doit jamais transformer un
      // enregistrement clinique réussi en erreur visible pour l'utilisateur.
    }
  }

  Future<void> deleteCase(PracticeCase value) async {
    if (value.pendingSync || value.id == null) {
      await _removePending(value.clientId);
      _notify();
      return;
    }
    if (_backend.enabled && _authUserId != null) {
      await _backend.client.from('practice_cases').delete().eq('id', value.id!);
    }
    await _removePending(value.clientId);
    ClinicalCaseService.instance.notifyChanged();
    _notify();
  }

  Future<int> syncPending() async {
    if (!_backend.enabled || _authUserId == null) return 0;
    final items = await pendingCases();
    var synced = 0;
    for (final item in items) {
      try {
        final existing = await _backend.client
            .from('practice_cases')
            .select('id')
            .eq('user_id', item.userId)
            .eq('client_id', item.clientId)
            .maybeSingle();
        if (existing != null) {
          final existingId = '${existing['id'] ?? ''}'.trim();
          await _removePending(item.clientId);
          ClinicalCaseService.instance.notifyChanged();
          if (existingId.isNotEmpty) {
            unawaited(ClinicalCaseService.instance
                .enrichQcmForPracticeCase(existingId));
          }
          synced++;
          continue;
        }
        final payload = item.toMap(includeId: false)
          ..['patient_number'] = 0
          ..['is_draft'] = false
          ..['synced_at'] = DateTime.now().toUtc().toIso8601String();
        final inserted = await _backend.client
            .from('practice_cases')
            .insert(payload)
            .select('id')
            .single();
        final insertedId = '${inserted['id'] ?? ''}'.trim();
        await _removePending(item.clientId);
        ClinicalCaseService.instance.notifyChanged();
        if (insertedId.isNotEmpty) {
          final syncedCase = item.copyWith(id: insertedId, pendingSync: false);
          unawaited(ClinicalCaseService.instance
              .enrichQcmForPracticeCase(insertedId));
          if (!syncedCase.isStandalone) {
            unawaited(
              _notifyAfterNewCase(
                syncedCase,
                null,
                DateTime.now(),
              ),
            );
          }
        }
        synced++;
      } catch (_) {
        // Keep the item for the next foreground sync.
      }
    }
    if (synced > 0) _notify();
    return synced;
  }

  Future<List<PracticeCase>> pendingCases() async {
    final uid = _authUserId;
    if (uid == null) return const <PracticeCase>[];
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_pendingKeyPrefix$uid');
    if (raw == null || raw.isEmpty) return const <PracticeCase>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <PracticeCase>[];
      return decoded
          .whereType<Map>()
          .map((row) => PracticeCase.fromMap(Map<String, dynamic>.from(row),
              pendingSync: true))
          .toList(growable: false);
    } catch (_) {
      return const <PracticeCase>[];
    }
  }

  Future<void> _putPending(PracticeCase value) async {
    final uid = _authUserId ?? value.userId;
    final prefs = await SharedPreferences.getInstance();
    final items = (await pendingCases()).toList();
    final index = items.indexWhere((item) => item.clientId == value.clientId);
    if (index >= 0) {
      items[index] = value;
    } else {
      items.insert(0, value);
    }
    await prefs.setString(
      '$_pendingKeyPrefix$uid',
      jsonEncode(items.map((item) => item.toMap()).toList()),
    );
  }

  Future<void> _removePending(String clientId) async {
    final uid = _authUserId;
    if (uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    final items = (await pendingCases())
        .where((item) => item.clientId != clientId)
        .toList();
    await prefs.setString(
      '$_pendingKeyPrefix$uid',
      jsonEncode(items.map((item) => item.toMap()).toList()),
    );
  }

  Future<void> saveLocalDraft(PracticeCase value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _draftKey(value.userId, value.guardId),
      jsonEncode(value.copyWith(isDraft: true).toMap()),
    );
  }

  Future<PracticeCase?> loadLocalDraft({
    required String userId,
    required String guardId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_draftKey(userId, guardId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map)
        return PracticeCase.fromMap(Map<String, dynamic>.from(decoded));
    } catch (_) {}
    return null;
  }

  Future<void> clearLocalDraft({
    required String userId,
    required String guardId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_draftKey(userId, guardId));
  }

  Future<PracticeStats> _mergePendingStats(
    PracticeStats base, {
    required String scope,
    String? guardId,
  }) async {
    final pending = await pendingCases();
    final now = DateTime.now();
    final applicable = pending.where((item) {
      if (item.isStandalone || item.isDraft || !item.isValid) return false;
      if (scope == 'guard') return guardId != null && item.guardId == guardId;
      final date = DateTime.tryParse(item.guardDate);
      if (scope == 'month')
        return date != null && date.year == now.year && date.month == now.month;
      if (scope == 'year') return date != null && date.year == now.year;
      return true;
    }).toList();
    if (applicable.isEmpty) return base;
    final guardIds = applicable.map((e) => e.guardId).toSet();
    return PracticeStats(
      patients: base.patients + applicable.length,
      waiting: base.waiting + applicable.where((e) => e.waiting).length,
      discharged:
          base.discharged + applicable.where((e) => e.discharged).length,
      hospitalized:
          base.hospitalized + applicable.where((e) => e.hospitalized).length,
      specialistOpinions: base.specialistOpinions +
          applicable.where((e) => e.specialistOpinionRequested).length,
      prescriptions: base.prescriptions +
          applicable.where((e) => e.prescriptionDone).length,
      completeObservations: base.completeObservations +
          applicable.where((e) => e.isComplete).length,
      guardsCount: base.guardsCount + guardIds.length,
      averagePerGuard: base.averagePerGuard,
      bestGuard: base.bestGuard,
      xp: base.xp + applicable.fold<int>(0, (sum, e) => sum + e.xp),
      streak: base.streak,
    );
  }

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static String _draftKey(String userId, String guardId) =>
      '$_draftKeyPrefix${userId}_$guardId';
}
