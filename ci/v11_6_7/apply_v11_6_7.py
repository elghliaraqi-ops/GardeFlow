from pathlib import Path


def must_replace(path: str, old: str, new: str, count: int = 1) -> None:
    p = Path(path)
    text = p.read_text()
    if old not in text:
        raise SystemExit(f"V11.6.7: pattern not found in {path}: {old[:120]!r}")
    text = text.replace(old, new, count)
    p.write_text(text)


# Version
must_replace('pubspec.yaml', 'version: 11.6.6+166', 'version: 11.6.7+167')

# ---------------------------------------------------------------------------
# Local reminders: exact alarms, Morocco timezone, sound profiles, test button,
# repeat support and stable multi-reminder ids.
# ---------------------------------------------------------------------------
Path('lib/services/notification_service.dart').write_text(r'''import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Notifications locales de GardeFlow.
///
/// V11.6.7 : les rappels de garde utilisent l'heure marocaine, tentent une
/// alarme exacte sur Android, survivent au redémarrage grâce au receiver déjà
/// déclaré et peuvent être répétés avec un identifiant distinct par occurrence.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  final ValueNotifier<String> reminderStatus = ValueNotifier<String>('Rappels locaux non initialisés');

  bool _initialized = false;
  bool? _canScheduleExact;
  void Function(String kind)? onPushTap;
  String? pendingPushKind;

  static const pushChannelId = 'huim6_push';
  static const _standardReminderChannel = 'gardeflow_guard_standard_v2';
  static const _urgentReminderChannel = 'gardeflow_guard_urgent_v2';
  static const _silentReminderChannel = 'gardeflow_guard_silent_v2';

  bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get _isIos => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> init() async {
    if (_initialized) return;
    if (kIsWeb) {
      _initialized = true;
      reminderStatus.value = 'Rappels locaux indisponibles sur le Web';
      return;
    }

    tz_data.initializeTimeZones();
    // Les trois établissements GardeFlow sont au Maroc. Fixer explicitement la
    // zone évite que tz.local reste en UTC et décale les alarmes d'une heure.
    tz.setLocalLocation(tz.getLocation('Africa/Casablanca'));

    const androidInit = AndroidInitializationSettings('ic_stat_huim6');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(android: androidInit, iOS: iosInit);

    await _plugin.initialize(settings, onDidReceiveNotificationResponse: (response) {
      final payload = response.payload;
      if (payload != null && payload.startsWith('push:')) {
        final kind = payload.substring(5);
        if (onPushTap != null) {
          onPushTap!(kind);
        } else {
          pendingPushKind = kind;
        }
      }
    });

    final launch = await _plugin.getNotificationAppLaunchDetails();
    final payload = launch?.notificationResponse?.payload;
    if (launch?.didNotificationLaunchApp == true && payload != null && payload.startsWith('push:')) {
      pendingPushKind = payload.substring(5);
    }

    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      pushChannelId,
      'Échanges et congés',
      description: 'Demandes, validations et événements du planning',
      importance: Importance.high,
    ));
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      _standardReminderChannel,
      'Rappels de garde · Standard',
      description: 'Rappels sonores avant les gardes validées',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    ));
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      _urgentReminderChannel,
      'Rappels de garde · Urgent',
      description: 'Rappels prioritaires avant les gardes validées',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    ));
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      _silentReminderChannel,
      'Rappels de garde · Silencieux',
      description: 'Rappels visuels sans son',
      importance: Importance.high,
      playSound: false,
      enableVibration: false,
    ));

    if (_isAndroid) {
      try {
        _canScheduleExact = await android?.canScheduleExactNotifications();
        reminderStatus.value = _canScheduleExact == true
            ? 'Rappels locaux prêts · alarmes exactes autorisées'
            : 'Rappels locaux prêts · alarmes exactes à autoriser';
      } catch (_) {
        reminderStatus.value = 'Rappels locaux prêts';
      }
    } else if (_isIos) {
      reminderStatus.value = 'Rappels locaux iOS prêts';
    } else {
      reminderStatus.value = 'Rappels locaux prêts';
    }
    _initialized = true;
  }

  Future<void> showPush({required String title, required String body, required String kind}) async {
    if (kIsWeb) return;
    await init();
    await _plugin.show(
      (DateTime.now().microsecondsSinceEpoch & 0x3fffffff) | 0x40000000,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          pushChannelId,
          'Échanges et congés',
          channelDescription: 'Demandes, validations et événements du planning',
          icon: 'ic_stat_huim6',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: 'push:$kind',
    );
  }

  Future<void> requestPermission() async {
    if (kIsWeb) return;
    await init();
    await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    if (_isAndroid) {
      try {
        _canScheduleExact = await android?.canScheduleExactNotifications();
        if (_canScheduleExact == false) {
          _canScheduleExact = await android?.requestExactAlarmsPermission();
        }
        reminderStatus.value = _canScheduleExact == true
            ? 'Rappels locaux prêts · alarmes exactes autorisées'
            : 'Alarmes exactes non autorisées · secours en mode approximatif';
      } catch (_) {
        reminderStatus.value = 'Rappels locaux prêts · mode compatible';
      }
    }
  }

  Future<bool?> canScheduleExactAlarms() async {
    if (!_isAndroid) return null;
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    try {
      _canScheduleExact = await android?.canScheduleExactNotifications();
    } catch (_) {}
    return _canScheduleExact;
  }

  int _idFor(String ownerPhone, String notificationKey) {
    var hash = 0;
    for (final unit in '$ownerPhone|$notificationKey'.codeUnits) {
      hash = ((hash * 31) + unit) & 0x3fffffff;
    }
    return hash;
  }

  NotificationDetails _reminderDetails({
    required String soundMode,
    required bool vibration,
  }) {
    final silent = soundMode == 'silent';
    final urgent = soundMode == 'urgent';
    final channelId = silent
        ? _silentReminderChannel
        : urgent
            ? _urgentReminderChannel
            : _standardReminderChannel;
    final channelName = silent
        ? 'Rappels de garde · Silencieux'
        : urgent
            ? 'Rappels de garde · Urgent'
            : 'Rappels de garde · Standard';

    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: 'Rappel avant le début d’une garde dont le calendrier est validé',
        icon: 'ic_stat_huim6',
        importance: urgent ? Importance.max : Importance.high,
        priority: urgent ? Priority.max : Priority.high,
        playSound: !silent,
        enableVibration: !silent && vibration,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: !silent,
      ),
    );
  }

  Future<void> showReminderTest({
    required String soundMode,
    required bool vibration,
  }) async {
    if (kIsWeb) return;
    await requestPermission();
    await _plugin.show(
      0x3ffffffe,
      'Test rappel de garde',
      'Attention : ceci est un test GardeFlow. Vos rappels sont actifs.',
      _reminderDetails(soundMode: soundMode, vibration: vibration),
      payload: 'guard:test',
    );
    reminderStatus.value = 'Notification test envoyée';
  }

  tz.TZDateTime _moroccoTime(DateTime value) => tz.TZDateTime(
        tz.local,
        value.year,
        value.month,
        value.day,
        value.hour,
        value.minute,
        value.second,
      );

  Future<void> scheduleReminder({
    required String ownerPhone,
    required String dateStr,
    required String notificationKey,
    required String title,
    required String body,
    required DateTime fireAt,
    required String soundMode,
    required bool vibration,
  }) async {
    if (kIsWeb || !fireAt.isAfter(DateTime.now())) return;
    await init();

    final details = _reminderDetails(soundMode: soundMode, vibration: vibration);
    final id = _idFor(ownerPhone, notificationKey);
    final scheduled = _moroccoTime(fireAt);
    final payload = 'guard:$ownerPhone:$dateStr:$notificationKey';
    final exact = !_isAndroid || _canScheduleExact != false;

    Future<void> schedule(AndroidScheduleMode mode) => _plugin.zonedSchedule(
          id,
          title,
          body,
          scheduled,
          details,
          payload: payload,
          androidScheduleMode: mode,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        );

    try {
      await schedule(exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle);
    } catch (e) {
      if (_isAndroid && exact) {
        try {
          _canScheduleExact = false;
          reminderStatus.value = 'Alarme exacte refusée · rappel programmé en mode approximatif';
          await schedule(AndroidScheduleMode.inexactAllowWhileIdle);
          return;
        } catch (fallbackError) {
          debugPrint('Impossible de planifier le rappel (secours): $fallbackError');
        }
      }
      debugPrint('Impossible de planifier le rappel: $e');
    }
  }

  Future<void> cancelGuardReminders(String ownerPhone, String dateStr) async {
    if (kIsWeb) return;
    await init();
    final prefix = 'guard:$ownerPhone:$dateStr:';
    try {
      final pending = await _plugin.pendingNotificationRequests();
      for (final item in pending) {
        if (item.payload?.startsWith(prefix) == true) {
          await _plugin.cancel(item.id);
        }
      }
    } catch (e) {
      debugPrint('Annulation ciblée des rappels impossible: $e');
    }
  }

  Future<void> cancelReminder(String ownerPhone, String dateStr) =>
      cancelGuardReminders(ownerPhone, dateStr);

  Future<void> cancelAll() async {
    if (kIsWeb) return;
    await init();
    await _plugin.cancelAll();
  }
}
''')

# Android exact alarm permission + vibration permission.
must_replace(
    'tool/configure_android.dart',
    "for (final permission in ['INTERNET', 'POST_NOTIFICATIONS', 'RECEIVE_BOOT_COMPLETED']) {",
    "for (final permission in ['INTERNET', 'POST_NOTIFICATIONS', 'RECEIVE_BOOT_COMPLETED', 'SCHEDULE_EXACT_ALARM', 'VIBRATE']) {",
)

# ---------------------------------------------------------------------------
# AppState reminder engine. PDF overlay remains a draft; only approved months
# are eligible because every rebuild filters with isPlanningEntryApproved().
# ---------------------------------------------------------------------------
must_replace(
    'lib/state/app_state.dart',
    """          state.currentUser=profile;\n          await state._reloadFromBackend();""",
    """          state.currentUser=profile;\n          state._applyReminderPrefsForCurrentUser();\n          await state._reloadFromBackend();""",
)
must_replace(
    'lib/state/app_state.dart',
    """        state.currentUser = state._users.where((u) => u.phone == sessionPhone).firstOrNull;\n      }\n    }\n    state._refreshReminderStatuses();""",
    """        state.currentUser = state._users.where((u) => u.phone == sessionPhone).firstOrNull;\n        state._applyReminderPrefsForCurrentUser();\n      }\n    }\n    state._applyReminderPrefsForCurrentUser();\n    state._refreshReminderStatuses();""",
)
must_replace(
    'lib/state/app_state.dart',
    """    _rebuildDirectory();\n    _syncCurrentUserRemindersAfterBackend();\n    await _persistNow();""",
    """    _rebuildDirectory();\n    await _syncCurrentUserRemindersAfterBackend();\n    await _persistNow();""",
)
must_replace(
    'lib/state/app_state.dart',
    """  void _syncCurrentUserRemindersAfterBackend(){\n    final me=currentUser;if(me==null)return;\n    NotificationService.instance.cancelAll();\n    _reminders.removeWhere((r)=>r.ownerPhone==me.phone);\n    for(final e in _planning.where((e)=>e.ownerPhone==me.phone&&isPlanningEntryApproved(e))){\n      _scheduleReminder(me.phone,e.dateStr,e.shiftId);\n    }\n  }""",
    """  Future<void> _syncCurrentUserRemindersAfterBackend() async {\n    // Important : la superposition du PDF officiel ne déclenche rien ici.\n    // Seules les gardes d'un mois définitivement validé sont éligibles.\n    await rescheduleAllReminders();\n  }""",
)

old_settings = """  int _delayMinutes=60;\n  bool _notificationsOn=true;\n  int get delayMinutes=>_delayMinutes;\n  set delayMinutes(int v){_delayMinutes=v;_persist();}\n  bool get notificationsOn=>_notificationsOn;\n  set notificationsOn(bool v){_notificationsOn=v;if(v){if(backendEnabled&&currentUser!=null&&(kIsWeb||defaultTargetPlatform==TargetPlatform.android||defaultTargetPlatform==TargetPlatform.iOS)){unawaited(PushNotificationService.instance.activateForSignedInUser());}else{unawaited(NotificationService.instance.requestPermission());}}else{unawaited(NotificationService.instance.cancelAll());if(backendEnabled&&currentUser!=null)unawaited(PushNotificationService.instance.unregisterCurrentDevice());}_persist();}\n"""
new_settings = """  int _delayMinutes=60; // compatibilité avec l'ancien stockage V11.6.6\n  bool _notificationsOn=true;\n  List<int> _reminderDelays=<int>[1440,120];\n  int _reminderRepeatMinutes=15;\n  int _reminderRepeatCount=1;\n  bool _reminderVibration=true;\n  String _reminderSoundMode='urgent';\n  final Map<String,Map<String,dynamic>> _reminderPrefsByUser=<String,Map<String,dynamic>>{};\n\n  List<int> get reminderDelays=>List.unmodifiable(_reminderDelays);\n  int get reminderRepeatMinutes=>_reminderRepeatMinutes;\n  int get reminderRepeatCount=>_reminderRepeatCount;\n  bool get reminderVibration=>_reminderVibration;\n  String get reminderSoundMode=>_reminderSoundMode;\n  int get delayMinutes=>_reminderDelays.isNotEmpty?_reminderDelays.first:_delayMinutes;\n  set delayMinutes(int v){unawaited(setReminderDelays(<int>[v]));}\n  bool get notificationsOn=>_notificationsOn;\n  set notificationsOn(bool v){unawaited(setNotificationsOn(v));}\n\n  String? get _reminderOwnerKey{\n    final me=currentUser;if(me==null)return null;\n    return me.id.isNotEmpty?me.id:me.phone;\n  }\n\n  void _applyReminderPrefsForCurrentUser(){\n    final legacyDelay=_delayMinutes;\n    final legacyOn=_notificationsOn;\n    _reminderDelays=<int>[1440,120];\n    _reminderRepeatMinutes=15;\n    _reminderRepeatCount=1;\n    _reminderVibration=true;\n    _reminderSoundMode='urgent';\n    _notificationsOn=true;\n    final key=_reminderOwnerKey;if(key==null)return;\n    final p=_reminderPrefsByUser[key];\n    if(p==null){\n      // Migration douce de l'unique ancien réglage lors de la première ouverture.\n      if(_reminderPrefsByUser.isEmpty){_reminderDelays=<int>[legacyDelay];_notificationsOn=legacyOn;}\n      _delayMinutes=_reminderDelays.first;\n      return;\n    }\n    final delays=(p['delays'] as List? ?? const <dynamic>[]).map((e)=>(e as num).toInt()).where((e)=>e>0&&e<=10080).toSet().toList()..sort((a,b)=>b.compareTo(a));\n    if(delays.isNotEmpty)_reminderDelays=delays.take(3).toList();\n    _reminderRepeatMinutes=((p['repeatMinutes'] as num?)?.toInt()??15).clamp(5,180);\n    _reminderRepeatCount=((p['repeatCount'] as num?)?.toInt()??1).clamp(0,3);\n    _reminderVibration=p['vibration'] as bool? ?? true;\n    final sound=p['soundMode']?.toString()??'urgent';\n    _reminderSoundMode=const <String>{'system','urgent','silent'}.contains(sound)?sound:'urgent';\n    _notificationsOn=p['enabled'] as bool? ?? true;\n    _delayMinutes=_reminderDelays.first;\n  }\n\n  void _storeReminderPrefsForCurrentUser(){\n    final key=_reminderOwnerKey;if(key==null)return;\n    _reminderPrefsByUser[key]=<String,dynamic>{\n      'delays':List<int>.from(_reminderDelays),\n      'repeatMinutes':_reminderRepeatMinutes,\n      'repeatCount':_reminderRepeatCount,\n      'vibration':_reminderVibration,\n      'soundMode':_reminderSoundMode,\n      'enabled':_notificationsOn,\n    };\n    _delayMinutes=_reminderDelays.first;\n  }\n\n  Future<void> _saveReminderPrefs() async{_storeReminderPrefsForCurrentUser();await _persistNow();notifyListeners();}\n\n  Future<void> setReminderDelays(List<int> values) async{\n    final cleaned=values.where((e)=>e>0&&e<=10080).toSet().toList()..sort((a,b)=>b.compareTo(a));\n    _reminderDelays=cleaned.isEmpty?<int>[60]:cleaned.take(3).toList();\n    await _saveReminderPrefs();\n  }\n  Future<void> setReminderRepeatMinutes(int value) async{_reminderRepeatMinutes=value.clamp(5,180);await _saveReminderPrefs();}\n  Future<void> setReminderRepeatCount(int value) async{_reminderRepeatCount=value.clamp(0,3);await _saveReminderPrefs();}\n  Future<void> setReminderVibration(bool value) async{_reminderVibration=value;await _saveReminderPrefs();}\n  Future<void> setReminderSoundMode(String value) async{_reminderSoundMode=const <String>{'system','urgent','silent'}.contains(value)?value:'system';await _saveReminderPrefs();}\n  Future<void> setNotificationsOn(bool value) async{\n    _notificationsOn=value;\n    if(value){\n      await NotificationService.instance.requestPermission();\n      if(backendEnabled&&currentUser!=null&&(kIsWeb||defaultTargetPlatform==TargetPlatform.android||defaultTargetPlatform==TargetPlatform.iOS)){\n        unawaited(PushNotificationService.instance.activateForSignedInUser());\n      }\n    }else{\n      await NotificationService.instance.cancelAll();\n      if(backendEnabled&&currentUser!=null)unawaited(PushNotificationService.instance.unregisterCurrentDevice());\n    }\n    await _saveReminderPrefs();\n  }\n\n  String reminderDelayLabel(int minutes){\n    if(minutes%1440==0)return '${minutes~/1440} j avant';\n    if(minutes%60==0)return '${minutes~/60} h avant';\n    return '$minutes min avant';\n  }\n\n  String? get nextReminderSummary{\n    _refreshReminderStatuses();\n    final me=currentUser;if(me==null)return null;\n    final list=_reminders.where((r)=>r.ownerPhone==me.phone&&r.status==ReminderStatus.upcoming).toList()..sort((a,b)=>a.fireAt.compareTo(b.fireAt));\n    if(list.isEmpty)return null;\n    final r=list.first;\n    return 'Prochain rappel : ${DateFormat('dd/MM à HH:mm','fr_FR').format(r.fireAt)} · ${r.label}';\n  }\n\n  Future<void> testGuardReminder() async{\n    await NotificationService.instance.showReminderTest(soundMode:_reminderSoundMode,vibration:_reminderVibration);\n  }\n"""
must_replace('lib/state/app_state.dart', old_settings, new_settings)

must_replace(
    'lib/state/app_state.dart',
    """        currentUser=user;\n        await _reloadFromBackend();""",
    """        currentUser=user;\n        _applyReminderPrefsForCurrentUser();\n        await _reloadFromBackend();""",
)
must_replace(
    'lib/state/app_state.dart',
    """    currentUser=user;unawaited(LocalStorageService.saveSessionPhone(user.phone));if(_notificationsOn)unawaited(NotificationService.instance.requestPermission());_activateNativeRemindersForCurrentUser();notifyListeners();return null;""",
    """    currentUser=user;_applyReminderPrefsForCurrentUser();unawaited(LocalStorageService.saveSessionPhone(user.phone));if(_notificationsOn)unawaited(NotificationService.instance.requestPermission());unawaited(_activateNativeRemindersForCurrentUser());notifyListeners();return null;""",
)

old_reminder_engine = """  void _scheduleReminder(String owner,String date,String shiftId){\n    final shift=ShiftCatalog.byId(shiftId);if(!shift.hasSchedule)return;\n    final p=date.split('-').map(int.parse).toList(),s=shift.start!.split(':').map(int.parse).toList();\n    final start=DateTime(p[0],p[1],p[2],s[0],s[1]),fire=start.subtract(Duration(minutes:_delayMinutes));\n    final label='${shift.id.startsWith('urg')?'Urgences':'Service'} · ${shift.label}';\n    _reminders.add(ReminderNotification(id:'n${++_reminderCounter}',ownerPhone:owner,dateStr:date,label:label,fireAt:fire,\n      status:fire.isBefore(DateTime.now())?ReminderStatus.sent:ReminderStatus.upcoming));\n    if(!_notificationsOn||currentUser?.phone!=owner||fire.isBefore(DateTime.now()))return;\n    NotificationService.instance.scheduleReminder(ownerPhone:owner,dateStr:date,title:'Garde à venir',body:'$label — début à ${shift.start} (dans $_delayMinutes min).',fireAt:fire);\n  }\n  void _cancelReminder(String owner,String date){_reminders.removeWhere((r)=>r.ownerPhone==owner&&r.dateStr==date);NotificationService.instance.cancelReminder(owner,date);}\n\n  void rescheduleAllReminders(){\n    final me=currentUser;if(me==null)return;\n    NotificationService.instance.cancelAll();_reminders.removeWhere((r)=>r.ownerPhone==me.phone);\n    for(final e in _planning.where((e)=>e.ownerPhone==me.phone&&isPlanningEntryApproved(e))){_scheduleReminder(me.phone,e.dateStr,e.shiftId);} _persist();notifyListeners();\n  }\n  void _activateNativeRemindersForCurrentUser(){\n    final me=currentUser;NotificationService.instance.cancelAll();if(me==null||!_notificationsOn)return;\n    for(final r in _reminders.where((r)=>r.ownerPhone==me.phone&&r.fireAt.isAfter(DateTime.now()))){\n      final e=_planning.where((e)=>e.ownerPhone==me.phone&&e.dateStr==r.dateStr).firstOrNull;if(e==null)continue;final sh=ShiftCatalog.byId(e.shiftId);\n      NotificationService.instance.scheduleReminder(ownerPhone:me.phone,dateStr:r.dateStr,title:'Garde à venir',body:'${r.label} — début à ${sh.start}.',fireAt:r.fireAt);\n    }\n  }\n"""
new_reminder_engine = """  DateTime _guardStart(String date,String shiftId){\n    final shift=ShiftCatalog.byId(shiftId);\n    final p=date.split('-').map(int.parse).toList(),s=shift.start!.split(':').map(int.parse).toList();\n    return DateTime(p[0],p[1],p[2],s[0],s[1]);\n  }\n\n  List<ReminderNotification> _appendReminderInstances(String owner,String date,String shiftId){\n    final shift=ShiftCatalog.byId(shiftId);if(!shift.hasSchedule)return const <ReminderNotification>[];\n    final start=_guardStart(date,shiftId);\n    final label='${shift.id.startsWith('urg')?'Urgences':'Service'} · ${shift.label}';\n    final added=<ReminderNotification>[];\n    for(final delay in _reminderDelays){\n      final first=start.subtract(Duration(minutes:delay));\n      for(var repeat=0;repeat<=_reminderRepeatCount;repeat++){\n        final fire=first.add(Duration(minutes:_reminderRepeatMinutes*repeat));\n        if(!fire.isBefore(start))continue;\n        final suffix=repeat==0?reminderDelayLabel(delay):'répétition $repeat';\n        final r=ReminderNotification(\n          id:'n${++_reminderCounter}',ownerPhone:owner,dateStr:date,label:'$label · $suffix',fireAt:fire,\n          status:fire.isBefore(DateTime.now())?ReminderStatus.sent:ReminderStatus.upcoming,\n        );\n        _reminders.add(r);added.add(r);\n      }\n    }\n    return added;\n  }\n\n  String _guardReminderBody(ReminderNotification reminder,PlanningEntry entry,ShiftType shift){\n    final start=_guardStart(entry.dateStr,entry.shiftId);\n    final fireDay=DateTime(reminder.fireAt.year,reminder.fireAt.month,reminder.fireAt.day);\n    final guardDay=DateTime(start.year,start.month,start.day);\n    final days=guardDay.difference(fireDay).inDays;\n    late String when;\n    if(days<=0){when=start.hour>=17?'ce soir':'aujourd’hui';}\n    else if(days==1){when='demain';}\n    else{when='dans $days jours';}\n    final service=shift.id.startsWith('urg')?'Urgences':'Service';\n    return 'Attention : garde $when à ${shift.start} · $service ${shift.label}.';\n  }\n\n  Future<void> _scheduleNativeReminder(ReminderNotification r) async{\n    final me=currentUser;if(me==null||!_notificationsOn||r.ownerPhone!=me.phone||!r.fireAt.isAfter(DateTime.now()))return;\n    final e=_planning.where((e)=>e.ownerPhone==me.phone&&e.dateStr==r.dateStr).firstOrNull;if(e==null||!isPlanningEntryApproved(e))return;\n    final sh=ShiftCatalog.byId(e.shiftId);if(!sh.hasSchedule)return;\n    await NotificationService.instance.scheduleReminder(\n      ownerPhone:me.phone,dateStr:r.dateStr,notificationKey:r.id,title:'Attention · GardeFlow',\n      body:_guardReminderBody(r,e,sh),fireAt:r.fireAt,soundMode:_reminderSoundMode,vibration:_reminderVibration,\n    );\n  }\n\n  void _scheduleReminder(String owner,String date,String shiftId){\n    final added=_appendReminderInstances(owner,date,shiftId);\n    if(currentUser?.phone==owner&&_notificationsOn){for(final r in added){unawaited(_scheduleNativeReminder(r));}}\n  }\n  void _cancelReminder(String owner,String date){\n    _reminders.removeWhere((r)=>r.ownerPhone==owner&&r.dateStr==date);\n    unawaited(NotificationService.instance.cancelGuardReminders(owner,date));\n  }\n\n  Future<void> rescheduleAllReminders() async{\n    final me=currentUser;if(me==null)return;\n    await NotificationService.instance.cancelAll();\n    _reminders.removeWhere((r)=>r.ownerPhone==me.phone);\n    for(final e in _planning.where((e)=>e.ownerPhone==me.phone&&isPlanningEntryApproved(e))){_appendReminderInstances(me.phone,e.dateStr,e.shiftId);}\n    await _persistNow();\n    await _activateNativeRemindersForCurrentUser(cancelExisting:false);\n    notifyListeners();\n  }\n\n  Future<void> _activateNativeRemindersForCurrentUser({bool cancelExisting=true}) async{\n    final me=currentUser;\n    if(cancelExisting)await NotificationService.instance.cancelAll();\n    if(me==null||!_notificationsOn)return;\n    final upcoming=_reminders.where((r)=>r.ownerPhone==me.phone&&r.fireAt.isAfter(DateTime.now())).toList()..sort((a,b)=>a.fireAt.compareTo(b.fireAt));\n    final limit=!kIsWeb&&defaultTargetPlatform==TargetPlatform.iOS?56:200;\n    for(final r in upcoming.take(limit)){await _scheduleNativeReminder(r);}\n  }\n"""
must_replace('lib/state/app_state.dart', old_reminder_engine, new_reminder_engine)

must_replace(
    'lib/state/app_state.dart',
    """    'exchanges':_exchanges.map((e)=>e.toJson()).toList(),'leaveRequests':_leaveRequests.map((e)=>e.toJson()).toList(),'planningMonths':_planningMonths.map((e)=>e.toJson()).toList(),'dismissedNotifications':_dismissedNotificationKeys.toList(),'delayMinutes':_delayMinutes,'notificationsOn':_notificationsOn,""",
    """    'exchanges':_exchanges.map((e)=>e.toJson()).toList(),'leaveRequests':_leaveRequests.map((e)=>e.toJson()).toList(),'planningMonths':_planningMonths.map((e)=>e.toJson()).toList(),'dismissedNotifications':_dismissedNotificationKeys.toList(),'delayMinutes':_delayMinutes,'notificationsOn':_notificationsOn,'reminderPrefsByUser':_reminderPrefsByUser,""",
)
must_replace(
    'lib/state/app_state.dart',
    """    _delayMinutes=(j['delayMinutes'] as num?)?.toInt()??60;_notificationsOn=j['notificationsOn'] as bool? ?? true;\n    _planningCounter=""",
    """    _delayMinutes=(j['delayMinutes'] as num?)?.toInt()??60;_notificationsOn=j['notificationsOn'] as bool? ?? true;\n    try{\n      final raw=Map<String,dynamic>.from(j['reminderPrefsByUser'] as Map? ?? const <String,dynamic>{});\n      for(final item in raw.entries){_reminderPrefsByUser[item.key]=Map<String,dynamic>.from(item.value as Map);}\n    }catch(_){}\n    _planningCounter=""",
)

# AppState.load now awaits the native reactivation function.
must_replace(
    'lib/state/app_state.dart',
    """    state._refreshReminderStatuses();\n    state._activateNativeRemindersForCurrentUser();""",
    """    state._refreshReminderStatuses();\n    await state._activateNativeRemindersForCurrentUser();""",
)

# ---------------------------------------------------------------------------
# Settings UI: multiple delays, custom delay, repetition, sound profile,
# vibration, exact-alarm status and immediate test. Every change is awaited.
# ---------------------------------------------------------------------------
Path('lib/screens/settings_screen.dart').write_text(r'''import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/hospitals.dart';
import '../services/notification_service.dart';
import '../services/push_notification_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';
import 'auth_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _delayPresets = <int>[4320, 2880, 1440, 720, 360, 180, 120, 60, 30];
  bool _saving = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addCustomDelay(AppState appState) async {
    final controller = TextEditingController();
    final value = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Délai personnalisé'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Minutes avant la garde',
            hintText: 'Ex. 90',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              final minutes = int.tryParse(controller.text.trim());
              Navigator.pop(ctx, minutes);
            },
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value <= 0 || value > 10080 || !mounted) return;
    final next = <int>{...appState.reminderDelays, value}.toList();
    if (next.length > 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vous pouvez garder jusqu’à 3 délais de rappel simultanés.')),
      );
      return;
    }
    await _run(() async {
      await appState.setReminderDelays(next);
      await appState.rescheduleAllReminders();
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final user = appState.currentUser;

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(title: const GardeFlowTitle('Réglages')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.lg),
        children: [
          if (user != null)
            AppCard(
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: AppColors.paperAlt,
                    child: Text(
                      user.fullName.isEmpty ? '?' : user.fullName.trim()[0].toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink),
                    ),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.fullName, style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 2),
                        Text(
                          '${user.gradeLabel} · ${user.roleLabel} · ${user.service} · ${hospitalDisplayName(user.hospital)}',
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpace.sm),
          if (user != null)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await appState.logout();
                  if (!context.mounted) return;
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const AuthScreen()),
                    (route) => false,
                  );
                },
                icon: const Icon(Icons.logout_rounded, size: 17, color: AppColors.danger),
                label: const Text('Déconnexion', style: TextStyle(color: AppColors.danger)),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.line)),
              ),
            ),
          const SizedBox(height: AppSpace.xl),

          const SectionLabel('Rappels de garde'),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.xs),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Activer les notifications et rappels', style: Theme.of(context).textTheme.titleMedium),
              subtitle: const Text('Les rappels de garde sont programmés uniquement après validation définitive du calendrier.', style: TextStyle(fontSize: 12)),
              value: appState.notificationsOn,
              onChanged: _saving
                  ? null
                  : (v) => _run(() async {
                        await appState.setNotificationsOn(v);
                        await appState.rescheduleAllReminders();
                      }),
            ),
          ),
          const SizedBox(height: AppSpace.md),
          AppCard(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.alarm_rounded, color: AppColors.brand),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Quand me rappeler ?', style: Theme.of(context).textTheme.titleMedium)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Choisissez jusqu’à 3 délais. Le PDF officiel ne déclenche aucun rappel tant que votre calendrier n’est pas validé.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft, height: 1.4),
                ),
                const SizedBox(height: AppSpace.md),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final minutes in _delayPresets)
                      FilterChip(
                        label: Text(appState.reminderDelayLabel(minutes)),
                        selected: appState.reminderDelays.contains(minutes),
                        onSelected: _saving
                            ? null
                            : (selected) async {
                                final next = <int>{...appState.reminderDelays};
                                if (selected) {
                                  if (next.length >= 3) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Maximum : 3 délais simultanés.')),
                                    );
                                    return;
                                  }
                                  next.add(minutes);
                                } else {
                                  if (next.length == 1) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Gardez au moins un délai de rappel.')),
                                    );
                                    return;
                                  }
                                  next.remove(minutes);
                                }
                                await _run(() async {
                                  await appState.setReminderDelays(next.toList());
                                  await appState.rescheduleAllReminders();
                                });
                              },
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.add_rounded, size: 17),
                      label: const Text('Personnalisé…'),
                      onPressed: _saving ? null : () => _addCustomDelay(appState),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.lg),
                DropdownButtonFormField<String>(
                  value: appState.reminderSoundMode,
                  decoration: const InputDecoration(labelText: 'Profil de sonnerie'),
                  items: const [
                    DropdownMenuItem(value: 'urgent', child: Text('Urgente · priorité maximale')),
                    DropdownMenuItem(value: 'system', child: Text('Standard · son système')),
                    DropdownMenuItem(value: 'silent', child: Text('Silencieuse · notification visuelle')),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value == null) return;
                          _run(() async {
                            await appState.setReminderSoundMode(value);
                            await appState.rescheduleAllReminders();
                          });
                        },
                ),
                const SizedBox(height: AppSpace.sm),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Vibration'),
                  subtitle: const Text('Vibrer avec le rappel sonore.'),
                  value: appState.reminderVibration,
                  onChanged: _saving
                      ? null
                      : (v) => _run(() async {
                            await appState.setReminderVibration(v);
                            await appState.rescheduleAllReminders();
                          }),
                ),
                const Divider(height: AppSpace.xl),
                Text('Répéter le rappel', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: appState.reminderRepeatCount,
                        decoration: const InputDecoration(labelText: 'Répétitions'),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('Aucune')),
                          DropdownMenuItem(value: 1, child: Text('1 fois')),
                          DropdownMenuItem(value: 2, child: Text('2 fois')),
                          DropdownMenuItem(value: 3, child: Text('3 fois')),
                        ],
                        onChanged: _saving
                            ? null
                            : (v) {
                                if (v == null) return;
                                _run(() async {
                                  await appState.setReminderRepeatCount(v);
                                  await appState.rescheduleAllReminders();
                                });
                              },
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: <int>[5, 10, 15, 30, 60].contains(appState.reminderRepeatMinutes) ? appState.reminderRepeatMinutes : 15,
                        decoration: const InputDecoration(labelText: 'Après'),
                        items: const [
                          DropdownMenuItem(value: 5, child: Text('5 min')),
                          DropdownMenuItem(value: 10, child: Text('10 min')),
                          DropdownMenuItem(value: 15, child: Text('15 min')),
                          DropdownMenuItem(value: 30, child: Text('30 min')),
                          DropdownMenuItem(value: 60, child: Text('1 h')),
                        ],
                        onChanged: _saving
                            ? null
                            : (v) {
                                if (v == null) return;
                                _run(() async {
                                  await appState.setReminderRepeatMinutes(v);
                                  await appState.rescheduleAllReminders();
                                });
                              },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.lg),
                ValueListenableBuilder<String>(
                  valueListenable: NotificationService.instance.reminderStatus,
                  builder: (context, status, _) => Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpace.sm),
                    decoration: BoxDecoration(color: AppColors.paperAlt, borderRadius: AppRadius.smR),
                    child: Text(status, style: Theme.of(context).textTheme.bodySmall),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  appState.nextReminderSummary ?? 'Aucun rappel programmé : validez d’abord un calendrier contenant une garde future.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft),
                ),
                const SizedBox(height: AppSpace.md),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving
                        ? null
                        : () => _run(() async {
                              await appState.testGuardReminder();
                            }),
                    icon: const Icon(Icons.volume_up_rounded),
                    label: const Text('Tester le rappel maintenant'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.lg),

          const SectionLabel('Notifications réseau'),
          AppCard(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.paperAlt, borderRadius: AppRadius.smR),
                    child: const Icon(Icons.notifications_active_rounded, size: 16, color: AppColors.ink),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: ValueListenableBuilder<String>(
                      valueListenable: PushNotificationService.instance.status,
                      builder: (context, status, _) => Text(status, style: Theme.of(context).textTheme.bodySmall),
                    ),
                  ),
                ]),
                if (appState.notificationsOn && appState.backendEnabled) ...[
                  const SizedBox(height: AppSpace.sm),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () async => PushNotificationService.instance.activateForSignedInUser(),
                      child: const Text('Activer / réessayer les notifications push'),
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: AppSpace.xl),
          const SectionLabel('Synchronisation'),
          AppCard(
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.paperAlt, borderRadius: AppRadius.smR),
                child: Icon(appState.backendEnabled ? Icons.cloud_done_rounded : Icons.cloud_off_rounded, size: 20, color: AppColors.ink),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(appState.backendModeLabel, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      appState.backendEnabled
                          ? 'Comptes, planning et transferts/échanges synchronisés avec Supabase.'
                          : 'Aucune clé Supabase fournie : fonctionnement local de démonstration.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (appState.backendEnabled)
                SoftIconButton(icon: Icons.sync_rounded, onTap: () => appState.refreshBackend(), size: 36, tooltip: 'Synchroniser'),
            ]),
          ),
          const SizedBox(height: AppSpace.md),
          Text(
            'Les paramètres de rappel sont enregistrés localement pour chaque compte sur cet appareil et restaurés après fermeture ou redémarrage.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.6),
          ),
        ],
      ),
    );
  }
}
''')

# ---------------------------------------------------------------------------
# Official PDF screen: current-doctor guard count, text search, and fluorescent
# automatic highlight of the signed-in doctor's name.
# ---------------------------------------------------------------------------
must_replace(
    'lib/screens/official_planning_screen.dart',
    """  final Map<String, String> _importStatus = <String, String>{};\n""",
    """  final Map<String, String> _importStatus = <String, String>{};\n  final Map<String, int> _myGuardCounts = <String, int>{};\n  final Set<String> _guardCountLoading = <String>{};\n""",
)

must_replace(
    'lib/screens/official_planning_screen.dart',
    """      final isAdmin = context.read<AppState>().currentUser?.role == UserRole.admin;\n      if (isAdmin) unawaited(_autoImportExisting(rows));""",
    """      final isAdmin = context.read<AppState>().currentUser?.role == UserRole.admin;\n      if (isAdmin) unawaited(_autoImportExisting(rows));\n      unawaited(_refreshMyGuardCount(rows));""",
)

insert_after_resource = """  SharedResource? _resourceFor(String slot) {\n    for (final r in _resources) {\n      if (r.slot == slot) return r;\n    }\n    return null;\n  }\n"""
new_after_resource = insert_after_resource + r'''

  _OfficialSlot? _slotForHospital(String hospital) {
    for (final slot in _slots) {
      if (slot.hospital == hospital) return slot;
    }
    return null;
  }

  Future<void> _refreshMyGuardCount(List<SharedResource> resources) async {
    if (!mounted) return;
    final me = context.read<AppState>().currentUser;
    if (me == null) return;
    final slot = _slotForHospital(me.hospital);
    if (slot == null) return;
    SharedResource? resource;
    for (final item in resources) {
      if (item.slot == slot.id) {
        resource = item;
        break;
      }
    }
    if (resource == null || _guardCountLoading.contains(slot.id)) return;
    setState(() => _guardCountLoading.add(slot.id));
    try {
      final bytes = await _backend.downloadSharedResource(resource.storagePath);
      final profiles = await _backend.fetchVisibleProfiles();
      final parsed = await OfficialRosterImportService.parse(
        bytes: bytes,
        displayName: resource.displayName,
        hospital: slot.hospital,
        profiles: profiles,
        resourceUpdatedAt: resource.updatedAt,
      );
      final count = parsed.assignments.where((a) => a.profileId == me.id).length;
      if (mounted) setState(() => _myGuardCounts[slot.id] = count);
    } catch (e) {
      debugPrint('Comptage des gardes ${slot.id} impossible: $e');
    } finally {
      if (mounted) setState(() => _guardCountLoading.remove(slot.id));
    }
  }
'''
must_replace('lib/screens/official_planning_screen.dart', insert_after_resource, new_after_resource)

must_replace(
    'lib/screens/official_planning_screen.dart',
    """  Future<void> _open(SharedResource resource) async {\n    if (!mounted) return;\n    await Navigator.push(\n      context,\n      MaterialPageRoute(\n        builder: (_) => _OfficialPdfViewerScreen(resource: resource),\n      ),\n    );\n  }""",
    """  Future<void> _open(SharedResource resource) async {\n    if (!mounted) return;\n    final me = context.read<AppState>().currentUser;\n    await Navigator.push(\n      context,\n      MaterialPageRoute(\n        builder: (_) => _OfficialPdfViewerScreen(resource: resource, currentUser: me),\n      ),\n    );\n  }""",
)

must_replace(
    'lib/screens/official_planning_screen.dart',
    """  Widget build(BuildContext context) {\n    final isAdmin = context.watch<AppState>().currentUser?.role == UserRole.admin;""",
    """  Widget build(BuildContext context) {\n    final currentUser = context.watch<AppState>().currentUser;\n    final isAdmin = currentUser?.role == UserRole.admin;""",
)

must_replace(
    'lib/screens/official_planning_screen.dart',
    """                          importStatus: _importStatus[_slots[i].id],\n                          onOpen: (r) => _open(r),""",
    """                          importStatus: _importStatus[_slots[i].id],\n                          myGuardCount: currentUser?.hospital == _slots[i].hospital ? _myGuardCounts[_slots[i].id] : null,\n                          guardCountLoading: currentUser?.hospital == _slots[i].hospital && _guardCountLoading.contains(_slots[i].id),\n                          isMyHospital: currentUser?.hospital == _slots[i].hospital,\n                          onOpen: (r) => _open(r),""",
)

must_replace(
    'lib/screens/official_planning_screen.dart',
    """  final String? importStatus;\n  final ValueChanged<SharedResource> onOpen;""",
    """  final String? importStatus;\n  final int? myGuardCount;\n  final bool guardCountLoading;\n  final bool isMyHospital;\n  final ValueChanged<SharedResource> onOpen;""",
)
must_replace(
    'lib/screens/official_planning_screen.dart',
    """    required this.importStatus,\n    required this.onOpen,""",
    """    required this.importStatus,\n    required this.myGuardCount,\n    required this.guardCountLoading,\n    required this.isMyHospital,\n    required this.onOpen,""",
)

must_replace(
    'lib/screens/official_planning_screen.dart',
    """            if (importStatus != null) ...[\n              const SizedBox(height: 6),""",
    """            if (isMyHospital) ...[\n              const SizedBox(height: 8),\n              Container(\n                width: double.infinity,\n                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),\n                decoration: BoxDecoration(\n                  color: const Color(0xFFFFF59D).withOpacity(0.42),\n                  borderRadius: AppRadius.smR,\n                  border: Border.all(color: const Color(0xFFF9A825).withOpacity(0.35)),\n                ),\n                child: Row(children: [\n                  const Icon(Icons.manage_search_rounded, size: 17, color: Color(0xFF8D6E00)),\n                  const SizedBox(width: 7),\n                  Expanded(\n                    child: Text(\n                      guardCountLoading\n                          ? 'Recherche de vos gardes dans ce PDF…'\n                          : '${myGuardCount ?? 0} garde${(myGuardCount ?? 0) > 1 ? 's' : ''} retrouvée${(myGuardCount ?? 0) > 1 ? 's' : ''} pour vous',\n                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF6D5700)),\n                    ),\n                  ),\n                ]),\n              ),\n            ],\n            if (importStatus != null) ...[\n              const SizedBox(height: 6),""",
)

# Replace the PDF viewer classes from the class declaration to EOF with a
# search-enabled version. It retains pinch/+/− zoom and adds two independent
# text searchers: automatic doctor highlight + manual word search.
p = Path('lib/screens/official_planning_screen.dart')
text = p.read_text()
marker = 'class _OfficialPdfViewerScreen extends StatefulWidget {'
pos = text.find(marker)
if pos < 0:
    raise SystemExit('V11.6.7: PDF viewer marker not found')
text = text[:pos] + r'''class _OfficialPdfViewerScreen extends StatefulWidget {
  final SharedResource resource;
  final AppUser? currentUser;

  const _OfficialPdfViewerScreen({required this.resource, required this.currentUser});

  @override
  State<_OfficialPdfViewerScreen> createState() => _OfficialPdfViewerScreenState();
}

class _OfficialPdfViewerScreenState extends State<_OfficialPdfViewerScreen> {
  final _backend = SupabaseBackendService.instance;
  final PdfViewerController _controller = PdfViewerController();
  final TextEditingController _searchField = TextEditingController();
  late final PdfTextSearcher _doctorSearcher;
  late final PdfTextSearcher _manualSearcher;

  Uint8List? _bytes;
  Object? _error;
  bool _loading = true;
  bool _searchMode = false;
  bool _viewerReady = false;

  @override
  void initState() {
    super.initState();
    _doctorSearcher = PdfTextSearcher(_controller)..addListener(_onSearchChanged);
    _manualSearcher = PdfTextSearcher(_controller)..addListener(_onSearchChanged);
    _loadPdf();
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _doctorSearcher.removeListener(_onSearchChanged);
    _manualSearcher.removeListener(_onSearchChanged);
    _doctorSearcher.dispose();
    _manualSearcher.dispose();
    _searchField.dispose();
    super.dispose();
  }

  Future<void> _loadPdf() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _viewerReady = false;
      });
    }
    try {
      final bytes = await _backend.downloadSharedResource(widget.resource.storagePath);
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Pattern? _doctorPattern() {
    final user = widget.currentUser;
    if (user == null) return null;
    final nom = user.nom.trim();
    final prenom = user.prenom.trim();
    if (nom.isEmpty || prenom.isEmpty) return null;
    final firstPrenom = prenom.split(RegExp(r'\s+')).first;
    final variants = <String>{
      '${RegExp.escape(prenom)}\\s+${RegExp.escape(nom)}',
      '${RegExp.escape(nom)}\\s+${RegExp.escape(prenom)}',
      '${RegExp.escape(firstPrenom)}\\s+${RegExp.escape(nom)}',
      '${RegExp.escape(nom)}\\s+${RegExp.escape(firstPrenom)}',
    };
    return RegExp('(?:${variants.join('|')})', caseSensitive: false);
  }

  void _startDoctorHighlight() {
    final pattern = _doctorPattern();
    if (pattern == null) return;
    _doctorSearcher.startTextSearch(
      pattern,
      caseInsensitive: true,
      goToFirstMatch: false,
      searchImmediately: true,
    );
  }

  void _search(String raw) {
    final query = raw.trim();
    if (query.isEmpty) {
      _manualSearcher.resetTextSearch();
      return;
    }
    _manualSearcher.startTextSearch(
      query,
      caseInsensitive: true,
      goToFirstMatch: true,
      searchImmediately: true,
    );
  }

  void _toggleSearch() {
    setState(() {
      _searchMode = !_searchMode;
      if (!_searchMode) {
        _searchField.clear();
        _manualSearcher.resetTextSearch();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    final currentIndex = _manualSearcher.currentIndex;
    final matchCount = _manualSearcher.matches.length;
    final searchStatus = _manualSearcher.isSearching
        ? 'Recherche…'
        : matchCount == 0
            ? 'Aucun résultat'
            : '${(currentIndex ?? 0) + 1}/$matchCount';

    return Scaffold(
      backgroundColor: const Color(0xFF202226),
      appBar: AppBar(
        titleSpacing: 8,
        title: _searchMode
            ? TextField(
                controller: _searchField,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: (value) {
                  if (value.trim().length >= 2 || value.trim().isEmpty) _search(value);
                },
                onSubmitted: _search,
                decoration: const InputDecoration(
                  hintText: 'Rechercher un nom, mot, service…',
                  border: InputBorder.none,
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Planning officiel', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  Text(
                    widget.resource.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
        actions: [
          IconButton(
            tooltip: _searchMode ? 'Fermer la recherche' : 'Rechercher dans le PDF',
            onPressed: _loading || bytes == null ? null : _toggleSearch,
            icon: Icon(_searchMode ? Icons.close_rounded : Icons.search_rounded),
          ),
          if (!_searchMode) ...[
            IconButton(
              tooltip: 'Zoom arrière',
              onPressed: _loading || bytes == null ? null : () => _controller.zoomDown(),
              icon: const Icon(Icons.zoom_out_rounded),
            ),
            IconButton(
              tooltip: 'Zoom avant',
              onPressed: _loading || bytes == null ? null : () => _controller.zoomUp(),
              icon: const Icon(Icons.zoom_in_rounded),
            ),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null || bytes == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.picture_as_pdf_outlined, size: 48, color: Colors.white70),
                        const SizedBox(height: 12),
                        const Text(
                          'Impossible d’afficher ce PDF.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text('$_error', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        const SizedBox(height: 16),
                        FilledButton.icon(onPressed: _loadPdf, icon: const Icon(Icons.refresh_rounded), label: const Text('Réessayer')),
                      ],
                    ),
                  ),
                )
              : Stack(
                  children: [
                    Positioned.fill(
                      child: PdfViewer.data(
                        bytes,
                        sourceName: widget.resource.displayName,
                        controller: _controller,
                        params: PdfViewerParams(
                          backgroundColor: const Color(0xFF202226),
                          margin: 10,
                          minScale: 0.7,
                          maxScale: 8.0,
                          panEnabled: true,
                          scaleEnabled: true,
                          matchTextColor: const Color(0xFFFFF176).withOpacity(0.62),
                          activeMatchTextColor: const Color(0xFFFFB300).withOpacity(0.78),
                          pagePaintCallbacks: [
                            _doctorSearcher.pageTextMatchPaintCallback,
                            _manualSearcher.pageTextMatchPaintCallback,
                          ],
                          onViewerReady: (document, controller) {
                            if (_viewerReady) return;
                            _viewerReady = true;
                            _startDoctorHighlight();
                          },
                        ),
                      ),
                    ),
                    if (_searchMode)
                      Positioned(
                        top: 10,
                        left: 12,
                        right: 12,
                        child: SafeArea(
                          bottom: false,
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(color: Colors.black.withOpacity(0.72), borderRadius: BorderRadius.circular(14)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(searchStatus, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                                  const SizedBox(width: 6),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    tooltip: 'Résultat précédent',
                                    onPressed: matchCount == 0 ? null : () => _manualSearcher.goToPrevMatch(),
                                    icon: const Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white),
                                  ),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    tooltip: 'Résultat suivant',
                                    onPressed: matchCount == 0 ? null : () => _manualSearcher.goToNextMatch(),
                                    icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 14,
                      child: IgnorePointer(
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(color: Colors.black.withOpacity(0.62), borderRadius: BorderRadius.circular(99)),
                            child: Text(
                              widget.currentUser == null
                                  ? 'Pincez pour zoomer • loupe pour rechercher'
                                  : '${widget.currentUser!.fullName} est surligné en fluo • loupe pour rechercher',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
'''
p.write_text(text)

print('GardeFlow V11.6.7 applied successfully')
