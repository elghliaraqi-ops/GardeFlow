import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'alarm_ring_service.dart';

/// Notifications locales de GardeFlow.
///
/// V11.6.14 : moteur défensif pour Android/Samsung. Une erreur native liée aux
/// notifications ne doit jamais fermer l'application. Les alarmes exactes ne
/// sont plus demandées automatiquement : lorsqu'elles ne sont pas disponibles,
/// les rappels sont programmés en mode compatible (inexactAllowWhileIdle).
///
/// V11.6.15 : ajout du mode `soundMode == 'alarm'`. Ce mode ne passe plus du
/// tout par [flutter_local_notifications] : il est entièrement délégué à
/// [AlarmRingService], qui programme une vraie alarme (sonnerie en boucle,
/// écran allumé, bouton Arrêter) au lieu d'une notification sonore classique
/// limitée à quelques secondes.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  final ValueNotifier<String> reminderStatus = ValueNotifier<String>('Initialisation des rappels…');

  bool _initialized = false;
  bool _initializing = false;
  bool? _canScheduleExact;
  void Function(String kind)? onPushTap;
  String? pendingPushKind;

  static const pushChannelId = 'huim6_push';
  static const _standardReminderChannel = 'gardeflow_guard_standard_v3';
  static const _urgentReminderChannel = 'gardeflow_guard_urgent_v3';
  static const _silentReminderChannel = 'gardeflow_guard_silent_v3';

  bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> init() async {
    if (_initialized || _initializing) return;
    if (kIsWeb) {
      _initialized = true;
      reminderStatus.value = 'Rappels locaux indisponibles sur le Web';
      return;
    }

    _initializing = true;
    try {
      tz_data.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Africa/Casablanca'));

      const androidInit = AndroidInitializationSettings('ic_stat_huim6');
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const settings = InitializationSettings(android: androidInit, iOS: iosInit);

      await _plugin.initialize(
        settings,
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload != null && payload.startsWith('push:')) {
            final kind = payload.substring(5);
            if (onPushTap != null) {
              onPushTap!(kind);
            } else {
              pendingPushKind = kind;
            }
          }
        },
      );

      try {
        final launch = await _plugin.getNotificationAppLaunchDetails();
        final payload = launch?.notificationResponse?.payload;
        if (launch?.didNotificationLaunchApp == true && payload != null && payload.startsWith('push:')) {
          pendingPushKind = payload.substring(5);
        }
      } catch (e) {
        debugPrint('Lecture du lancement par notification ignorée: $e');
      }

      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        await android.createNotificationChannel(const AndroidNotificationChannel(
          pushChannelId,
          'Échanges et congés',
          description: 'Demandes, validations et événements du planning',
          importance: Importance.high,
        ));
        await android.createNotificationChannel(const AndroidNotificationChannel(
          _standardReminderChannel,
          'Rappels de garde · Standard',
          description: 'Rappels sonores avant les gardes validées',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ));
        await android.createNotificationChannel(const AndroidNotificationChannel(
          _urgentReminderChannel,
          'Rappels de garde · Urgent',
          description: 'Rappels prioritaires avant les gardes validées',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ));
        await android.createNotificationChannel(const AndroidNotificationChannel(
          _silentReminderChannel,
          'Rappels de garde · Silencieux',
          description: 'Rappels visuels sans son',
          importance: Importance.high,
          playSound: false,
          enableVibration: false,
        ));

        if (_isAndroid) {
          try {
            _canScheduleExact = await android.canScheduleExactNotifications();
          } catch (e) {
            _canScheduleExact = false;
            debugPrint('Vérification alarmes exactes ignorée: $e');
          }
        }
      }

      _initialized = true;
      reminderStatus.value = _isAndroid
          ? (_canScheduleExact == true
              ? 'Rappels prêts · programmation exacte disponible'
              : 'Rappels prêts · mode compatible Android')
          : 'Rappels prêts';
    } catch (e, st) {
      _initialized = false;
      reminderStatus.value = 'Rappels locaux momentanément indisponibles';
      debugPrint('Initialisation des rappels ignorée: $e\n$st');
    } finally {
      _initializing = false;
    }
  }

  Future<bool> _ensureInitialized() async {
    await init();
    return _initialized;
  }

  Future<void> showPush({required String title, required String body, required String kind}) async {
    if (kIsWeb) return;
    if (!await _ensureInitialized()) return;
    try {
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
    } catch (e) {
      debugPrint('Notification push locale ignorée: $e');
    }
  }

  /// Demande uniquement l'autorisation d'afficher des notifications.
  ///
  /// L'accès spécial "alarmes exactes" n'est volontairement plus demandé ici :
  /// l'utilisateur ne doit pas être envoyé vers un écran système lorsqu'il
  /// change simplement sa sonnerie. L'ordonnanceur utilise un mode compatible
  /// lorsqu'une alarme exacte n'est pas disponible.
  Future<void> requestPermission() async {
    if (kIsWeb) return;
    if (!await _ensureInitialized()) return;

    try {
      await _plugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);

      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();

      if (_isAndroid && android != null) {
        try {
          _canScheduleExact = await android.canScheduleExactNotifications();
        } catch (_) {
          _canScheduleExact = false;
        }
        reminderStatus.value = _canScheduleExact == true
            ? 'Rappels prêts · programmation exacte disponible'
            : 'Rappels prêts · mode compatible Android';
      } else {
        reminderStatus.value = 'Rappels prêts';
      }
    } catch (e) {
      debugPrint('Demande d’autorisation de notification ignorée: $e');
      reminderStatus.value = 'Vérifiez l’autorisation Notifications dans Android';
    }
  }

  Future<bool?> canScheduleExactAlarms() async {
    if (!_isAndroid) return null;
    if (!await _ensureInitialized()) return false;
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    try {
      _canScheduleExact = await android?.canScheduleExactNotifications();
    } catch (_) {
      _canScheduleExact = false;
    }
    return _canScheduleExact;
  }

  /// Prépare explicitement Android pour le mode « Alarme ».
  ///
  /// Cette méthode n'est appelée qu'après une action volontaire de l'utilisateur
  /// (sélection du mode ou bouton de test) afin d'éviter d'ouvrir des écrans
  /// système au démarrage de l'application.
  Future<bool> prepareAlarmModePermissions() async {
    if (kIsWeb) return false;
    await requestPermission();
    if (!_initialized) return false;
    if (!_isAndroid) {
      reminderStatus.value = 'Alarme prête';
      return true;
    }

    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return false;
    try {
      var exact = await android.canScheduleExactNotifications() ?? false;
      if (!exact) {
        await android.requestExactAlarmsPermission();
        exact = await android.canScheduleExactNotifications() ?? false;
      }
      try {
        await android.requestFullScreenIntentPermission();
      } catch (e) {
        debugPrint('Autorisation plein écran ignorée: $e');
      }
      _canScheduleExact = exact;
      reminderStatus.value = exact
          ? 'Alarme prête · programmation exacte disponible'
          : 'Alarme non prête · autorisez « Alarmes et rappels » dans Android';
      return exact;
    } catch (e) {
      debugPrint('Préparation du mode alarme impossible: $e');
      reminderStatus.value = 'Alarme non prête · vérifiez les autorisations Android';
      return false;
    }
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
        category: AndroidNotificationCategory.alarm,
        visibility: NotificationVisibility.public,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: !silent,
        interruptionLevel: urgent ? InterruptionLevel.timeSensitive : InterruptionLevel.active,
      ),
    );
  }

  Future<void> showReminderTest({
    required String soundMode,
    required bool vibration,
  }) async {
    if (kIsWeb) return;
    if (soundMode == 'alarm') {
      final ready = await prepareAlarmModePermissions();
      if (_isAndroid && !ready) return;
      final scheduled = await AlarmRingService.instance.ringTestNow(vibration: vibration);
      reminderStatus.value = scheduled
          ? 'Test alarme envoyé · sonnerie longue'
          : 'Test alarme impossible · vérifiez les autorisations';
      return;
    }
    try {
      await requestPermission();
      if (!_initialized) return;
      await _plugin.show(
        0x3ffffffe,
        'Test rappel de garde',
        'Attention : ceci est un test GardeFlow. Vos rappels sont actifs.',
        _reminderDetails(soundMode: soundMode, vibration: vibration),
        payload: 'guard:test',
      );
      reminderStatus.value = soundMode == 'silent'
          ? 'Test envoyé · profil silencieux'
          : 'Test sonore envoyé';
    } catch (e) {
      debugPrint('Test de rappel ignoré: $e');
      reminderStatus.value = 'Test impossible · vérifiez les notifications Android';
    }
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

    if (soundMode == 'alarm') {
      if (_isAndroid) {
        final exact = await canScheduleExactAlarms();
        if (exact != true) {
          reminderStatus.value = 'Alarme non programmée · autorisez « Alarmes et rappels » dans Android';
          return;
        }
      }
      final scheduled = await AlarmRingService.instance.scheduleGuardAlarm(
        ownerPhone: ownerPhone,
        dateStr: dateStr,
        notificationKey: notificationKey,
        title: title,
        body: body,
        fireAt: fireAt,
        vibration: vibration,
      );
      if (!scheduled) reminderStatus.value = 'Une alarme n’a pas pu être programmée';
      return;
    }

    if (!await _ensureInitialized()) return;

    final details = _reminderDetails(soundMode: soundMode, vibration: vibration);
    final id = _idFor(ownerPhone, notificationKey);
    final scheduled = _moroccoTime(fireAt);
    final payload = 'guard:$ownerPhone:$dateStr:$notificationKey';

    Future<void> schedule(AndroidScheduleMode mode) => _plugin.zonedSchedule(
          id,
          title,
          body,
          scheduled,
          details,
          payload: payload,
          androidScheduleMode: mode,
        );

    if (_isAndroid && _canScheduleExact == true) {
      try {
        await schedule(AndroidScheduleMode.exactAllowWhileIdle);
        return;
      } catch (e) {
        debugPrint('Alarme exacte refusée, bascule en mode compatible: $e');
        _canScheduleExact = false;
      }
    }

    try {
      await schedule(AndroidScheduleMode.inexactAllowWhileIdle);
      if (_isAndroid) reminderStatus.value = 'Rappels programmés · mode compatible Android';
    } catch (e) {
      debugPrint('Impossible de programmer le rappel: $e');
      reminderStatus.value = 'Programmation impossible · réessayez dans Réglages';
    }
  }

  Future<void> cancelGuardReminders(String ownerPhone, String dateStr) async {
    if (kIsWeb) return;
    await AlarmRingService.instance.cancelGuardAlarms(ownerPhone, dateStr);
    final prefix = 'guard:$ownerPhone:$dateStr:';
    try {
      if (!await _ensureInitialized()) return;
      final pending = await _plugin.pendingNotificationRequests();
      for (final item in pending) {
        if (item.payload?.startsWith(prefix) == true) {
          try {
            await _plugin.cancel(item.id);
          } catch (e) {
            debugPrint('Annulation du rappel ${item.id} ignorée: $e');
          }
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
    await AlarmRingService.instance.cancelAll();
    try {
      if (!await _ensureInitialized()) return;
      final pending = await _plugin.pendingNotificationRequests();
      for (final item in pending) {
        final payload = item.payload ?? '';
        if (!payload.startsWith('guard:')) continue;
        try {
          await _plugin.cancel(item.id);
        } catch (e) {
          debugPrint('Annulation du rappel ${item.id} ignorée: $e');
        }
      }
    } catch (e) {
      debugPrint('Nettoyage des rappels ignoré: $e');
      reminderStatus.value = 'Rappels locaux momentanément indisponibles';
    }
  }
}
