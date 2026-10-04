import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/app_user.dart';
import '../models/planning_entry.dart';
import '../models/shift_type.dart';
import '../state/app_state.dart';

/// Pont léger entre GardeFlow et le widget Android natif.
///
/// Aucune donnée médicale n'est exposée : uniquement identité d'affichage,
/// garde personnelle, statut du jour et raccourcis de navigation.
/// Le cache local reste volontairement limité aux informations du widget.
class AndroidWidgetService {
  AndroidWidgetService._();
  static final AndroidWidgetService instance = AndroidWidgetService._();

  static const MethodChannel _channel = MethodChannel(
    'com.huim6.huim6_planning/widget',
  );

  final ValueNotifier<String?> action = ValueNotifier<String?>(null);
  bool _initialized = false;
  String? _lastPayload;

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

    final payload = _buildPayload(appState, me);
    final encoded = jsonEncode(payload);
    if (encoded == _lastPayload) return;

    try {
      await _channel.invokeMethod<void>('updateWidgetData', payload);
      _lastPayload = encoded;
    } catch (_) {
      // Une indisponibilité du launcher Android ne doit pas affecter GardeFlow.
    }
  }

  Map<String, String> _buildPayload(AppState appState, AppUser me) {
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
    final future = <({PlanningEntry entry, DateTime start})>[];
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
        }
      } else if (bounds.$1.isAfter(now)) {
        future.add((entry: entry, start: bounds.$1));
      }
    }

    future.sort((a, b) => a.start.compareTo(b.start));
    final next = active ?? (future.isEmpty ? null : future.first.entry);
    final nextData = next == null ? null : _guardData(next, now);

    String todayStatus;
    if (active != null) {
      final shift = _shiftFor(active.shiftId);
      todayStatus = shift == null
          ? 'De garde aujourd’hui'
          : '${_category(active.shiftId)} · ${shift.label.toUpperCase()}';
    } else if (isOnLeaveToday) {
      todayStatus = 'Congé aujourd’hui';
    } else {
      final todayUpcoming = future
          .where((item) => _sameDay(item.start, now))
          .firstOrNull;
      if (todayUpcoming != null) {
        todayStatus =
            'Garde à ${DateFormat('HH:mm').format(todayUpcoming.start)}';
      } else {
        todayStatus = 'Repos aujourd’hui';
      }
    }

    final futureCount = future.length + (active == null ? 0 : 1);
    return <String, String>{
      'doctor_name': _doctorLabel(me),
      'today_status': todayStatus,
      'next_title': nextData?.title ?? 'Aucune garde à venir',
      'next_detail': nextData?.detail ?? 'Votre planning est à jour',
      'next_shift_id': next?.shiftId ?? 'none',
      'planning_detail': futureCount == 0
          ? 'Aucune garde à venir'
          : '$futureCount garde${futureCount > 1 ? 's' : ''} à venir',
      'astreintes_detail': 'Juniors & séniors',
      'practice_detail': 'QCM & cas cliniques',
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
