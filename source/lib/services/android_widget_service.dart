import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/app_user.dart';
import '../models/planning_entry.dart';
import '../models/qcm_models.dart';
import '../models/shift_type.dart';
import '../state/app_state.dart';
import 'clinical_case_service.dart';

/// Pont léger entre GardeFlow et le widget Android natif.
///
/// Aucune donnée médicale n'est exposée : uniquement identité d'affichage,
/// planning personnel, statut du jour, statistiques Practice et raccourcis.
class AndroidWidgetService {
  AndroidWidgetService._();
  static final AndroidWidgetService instance = AndroidWidgetService._();

  static const MethodChannel _channel = MethodChannel(
    'com.huim6.huim6_planning/widget',
  );

  final ValueNotifier<String?> action = ValueNotifier<String?>(null);
  bool _initialized = false;
  String? _lastPayload;
  QcmStats? _practiceMonthCache;
  DateTime? _practiceCacheAt;

  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> initialize() async {
    if (!_supported || _initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'widgetAction') {
        final value = call.arguments?.toString();
        if (value != null && value.isNotEmpty) action.value = value;
      }
    });
    try {
      final initial = await _channel.invokeMethod<String>(
        'getInitialWidgetAction',
      );
      if (initial != null && initial.isNotEmpty) action.value = initial;
    } catch (_) {
      // Le widget ne doit jamais bloquer l'ouverture de l'application.
    }
  }

  void consumeAction() {
    if (action.value != null) action.value = null;
  }

  Future<void> sync(AppState appState) async {
    if (!_supported) return;
    final me = appState.currentUser;
    if (me == null) return;
    await initialize();

    final practiceMonth = await _practiceMonthStats();
    final payload = _buildPayload(appState, me, practiceMonth);
    final encoded = jsonEncode(payload);
    if (encoded == _lastPayload) return;

    try {
      await _channel.invokeMethod<void>('updateWidgetData', payload);
      _lastPayload = encoded;
    } catch (_) {
      // Une indisponibilité du launcher Android ne doit pas affecter GardeFlow.
    }
  }

  Future<QcmStats> _practiceMonthStats() async {
    final now = DateTime.now();
    if (_practiceMonthCache != null &&
        _practiceCacheAt != null &&
        now.difference(_practiceCacheAt!) < const Duration(minutes: 5)) {
      return _practiceMonthCache!;
    }
    try {
      final stats = await ClinicalCaseService.instance.qcmSummary(period: 'month');
      _practiceMonthCache = stats;
      _practiceCacheAt = now;
      return stats;
    } catch (_) {
      return _practiceMonthCache ?? const QcmStats();
    }
  }

  Map<String, String> _buildPayload(
    AppState appState,
    AppUser me,
    QcmStats practiceMonth,
  ) {
    final now = DateTime.now();
    final mine = appState.planning
        .where(
          (entry) =>
              (entry.ownerId == me.id || entry.ownerPhone == me.phone) &&
              appState.isPlanningEntryApproved(entry),
        )
        .toList(growable: false);

    PlanningEntry? active;
    DateTime? activeStart;
    DateTime? activeEnd;
    final future = <({PlanningEntry entry, DateTime start, DateTime end})>[];
    var isOnLeaveToday = false;

    for (final entry in mine) {
      final date = DateTime.tryParse(entry.dateStr);
      if (date == null) continue;
      if (entry.shiftId == 'conge') {
        if (_sameDay(date, now)) isOnLeaveToday = true;
        continue;
      }

      final shift = _shiftFor(entry.shiftId);
      if (shift == null || !shift.hasSchedule) continue;
      final bounds = _bounds(date, shift);
      if (bounds == null) continue;

      if (!now.isBefore(bounds.$1) && now.isBefore(bounds.$2)) {
        if (activeStart == null || bounds.$1.isAfter(activeStart)) {
          active = entry;
          activeStart = bounds.$1;
          activeEnd = bounds.$2;
        }
      } else if (bounds.$1.isAfter(now)) {
        future.add((entry: entry, start: bounds.$1, end: bounds.$2));
      }
    }

    future.sort((a, b) => a.start.compareTo(b.start));
    final next = active ?? (future.isEmpty ? null : future.first.entry);
    final nextStart = active != null
        ? activeStart
        : (future.isEmpty ? null : future.first.start);
    final nextEnd = active != null
        ? activeEnd
        : (future.isEmpty ? null : future.first.end);
    final nextData = next == null ? null : _guardData(next, now);

    String todayStatus;
    String astreintesDetail;
    String astreintesSubdetail;
    if (active != null) {
      final shift = _shiftFor(active.shiftId);
      todayStatus = shift == null
          ? 'De garde aujourd’hui'
          : '${_category(active.shiftId)} · ${shift.label.toUpperCase()}';
      astreintesDetail = 'Vous êtes de garde';
      astreintesSubdetail = 'Juniors + séniors · accès rapide';
    } else if (isOnLeaveToday) {
      todayStatus = 'Congé aujourd’hui';
      astreintesDetail = 'Aujourd’hui · Congé';
      astreintesSubdetail = 'Voir les équipes de garde';
    } else {
      final todayUpcoming = future
          .where((item) => _sameDay(item.start, now))
          .firstOrNull;
      if (todayUpcoming != null) {
        todayStatus =
            'Garde à ${DateFormat('HH:mm').format(todayUpcoming.start)}';
        astreintesDetail = 'Garde prévue aujourd’hui';
        astreintesSubdetail = 'Juniors + séniors · accès rapide';
      } else {
        todayStatus = 'Repos aujourd’hui';
        astreintesDetail = 'Aujourd’hui · Repos';
        astreintesSubdetail = 'Voir les juniors et séniors de garde';
      }
    }

    final futureCount = future.length + (active == null ? 0 : 1);
    final planningItems = <String>[];
    if (active != null) planningItems.add(_compactGuardLine(active, now));
    for (final item in future.take(3 - planningItems.length)) {
      planningItems.add(_compactGuardLine(item.entry, now));
    }
    while (planningItems.length < 3) {
      planningItems.add('');
    }

    final practiceAnswered = practiceMonth.answered;
    final practiceAccuracy = practiceMonth.accuracy;
    final practiceDetail = practiceAnswered == 0
        ? 'Ce mois · aucun QCM'
        : 'Ce mois · $practiceAnswered QCM répondus';
    final practiceSubdetail = practiceAnswered == 0
        ? 'Commencer un entraînement'
        : '${practiceAccuracy.toStringAsFixed(0)}% de réussite · ouvrir Practice';

    return <String, String>{
      'doctor_name': _doctorLabel(me),
      'date_label': _shortDate(now),
      'today_status': todayStatus,
      'next_title': nextData?.title ?? 'Aucune garde à venir',
      'next_detail': nextData?.detail ?? 'Votre planning est à jour',
      'next_shift_id': next?.shiftId ?? 'none',
      'next_start_ms': nextStart?.millisecondsSinceEpoch.toString() ?? '',
      'next_end_ms': nextEnd?.millisecondsSinceEpoch.toString() ?? '',
      'next_active': (active != null).toString(),
      'planning_detail': futureCount == 0
          ? 'Aucune garde à venir'
          : '$futureCount garde${futureCount > 1 ? 's' : ''} à venir',
      'planning_line_1': planningItems[0],
      'planning_line_2': planningItems[1],
      'planning_line_3': planningItems[2],
      'astreintes_detail': astreintesDetail,
      'astreintes_subdetail': astreintesSubdetail,
      'practice_detail': practiceDetail,
      'practice_subdetail': practiceSubdetail,
      'updated_at': now.toIso8601String(),
    };
  }

  ({String title, String detail}) _guardData(
    PlanningEntry entry,
    DateTime now,
  ) {
    final date = DateTime.tryParse(entry.dateStr) ?? now;
    final shift = _shiftFor(entry.shiftId);
    if (shift == null) {
      return (title: 'Prochaine garde', detail: entry.dateStr);
    }
    final bounds = _bounds(date, shift);
    final day = _relativeDay(date, now);
    final category = _category(entry.shiftId);
    final title = '$category · ${shift.label.toUpperCase()}';
    if (bounds == null) return (title: title, detail: day);

    final start = DateFormat('HH:mm').format(bounds.$1);
    final end = DateFormat('HH:mm').format(bounds.$2);
    final endPrefix = _sameDay(bounds.$1, bounds.$2) ? '' : 'demain ';
    return (title: title, detail: '$day · $start → $endPrefix$end');
  }

  String _compactGuardLine(PlanningEntry entry, DateTime now) {
    final date = DateTime.tryParse(entry.dateStr) ?? now;
    final shift = _shiftFor(entry.shiftId);
    final dateLabel = DateFormat('dd MMM', 'fr_FR').format(date);
    if (shift == null) return dateLabel;
    final category = _category(entry.shiftId) == 'URGENCES' ? 'URG' : 'SERVICE';
    return '$dateLabel · $category ${shift.label.toUpperCase()}';
  }

  String _shortDate(DateTime value) {
    final raw = DateFormat('EEE d MMM', 'fr_FR').format(value);
    return raw.isEmpty ? '' : raw[0].toUpperCase() + raw.substring(1);
  }

  String _doctorLabel(AppUser user) {
    final last = user.nom.trim();
    if (last.isNotEmpty) return 'Dr $last';
    final first = user.prenom.trim();
    return first.isEmpty ? 'Docteur' : 'Dr $first';
  }

  String _category(String shiftId) =>
      shiftId.toLowerCase().startsWith('urg') ? 'URGENCES' : 'SERVICE';

  String _relativeDay(DateTime value, DateTime now) {
    final date = DateTime(value.year, value.month, value.day);
    final today = DateTime(now.year, now.month, now.day);
    final delta = date.difference(today).inDays;
    if (delta == 0) return 'Aujourd’hui';
    if (delta == 1) return 'Demain';
    final raw = DateFormat('EEE d MMM', 'fr_FR').format(date);
    return raw.isEmpty ? '' : raw[0].toUpperCase() + raw.substring(1);
  }

  ShiftType? _shiftFor(String id) {
    for (final shift in ShiftCatalog.all) {
      if (shift.id == id) return shift;
    }
    return null;
  }

  (DateTime, DateTime)? _bounds(DateTime date, ShiftType shift) {
    final startRaw = shift.start;
    final endRaw = shift.end;
    if (startRaw == null || endRaw == null) return null;
    final startParts = startRaw.split(':').map(int.tryParse).toList();
    final endParts = endRaw.split(':').map(int.tryParse).toList();
    if (startParts.length != 2 || endParts.length != 2) return null;
    final sh = startParts[0];
    final sm = startParts[1];
    final eh = endParts[0];
    final em = endParts[1];
    if (sh == null || sm == null || eh == null || em == null) return null;

    final start = DateTime(date.year, date.month, date.day, sh, sm);
    var end = DateTime(date.year, date.month, date.day, eh, em);
    if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
    return (start, end);
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

extension _FirstOrNullWidget<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
