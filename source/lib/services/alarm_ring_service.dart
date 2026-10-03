import 'package:alarm/alarm.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Moteur d'alarme de garde.
///
/// Android V12 utilise en priorité le scheduler système natif installé par
/// `tool/install_system_alarm_bridge.py`. Les alarmes passent par
/// AlarmManager.setAlarmClock(), donc elles restent programmées même si
/// GardeFlow est balayée/fermée. Le code natif allume l'écran, ouvre
/// AlarmActivity au premier plan, joue la sonnerie d'alarme Android en boucle
/// et gère la vibration + le snooze 9 minutes.
///
/// Le package `alarm` reste un filet de compatibilité pour iOS et pour les
/// anciens builds Android qui ne contiennent pas encore le bridge natif.
class AlarmRingService {
  AlarmRingService._();
  static final AlarmRingService instance = AlarmRingService._();

  static const MethodChannel _fullScreenAlarmChannel =
      MethodChannel('gardeflow/fullscreen_alarm');
  static const int _testAlarmId = 0x1ffffffe;

  bool _initialized = false;
  bool _initializing = false;
  bool? _nativeBridgeAvailableCache;

  bool get _isWeb => kIsWeb;
  bool get _isAndroid =>
      !_isWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Son personnalisé du fallback Flutter. Le bridge natif Android utilise la
  /// sonnerie d'alarme configurée dans le téléphone.
  static const String? _customSoundAsset = null;

  Future<void> _ensureInitialized() async {
    if (_initialized || _initializing || _isWeb) return;
    _initializing = true;
    try {
      await Alarm.init();
      _initialized = true;
    } catch (e, st) {
      debugPrint('AlarmRingService: initialisation fallback ignorée: $e\n$st');
    } finally {
      _initializing = false;
    }
  }

  Future<bool> nativeSystemAlarmAvailable({bool refresh = false}) async {
    if (!_isAndroid) return false;
    if (!refresh && _nativeBridgeAvailableCache != null) {
      return _nativeBridgeAvailableCache!;
    }
    try {
      final available = await _fullScreenAlarmChannel
              .invokeMethod<bool>('isSystemAlarmBridgeAvailable') ??
          false;
      _nativeBridgeAvailableCache = available;
      return available;
    } on MissingPluginException {
      _nativeBridgeAvailableCache = false;
      return false;
    } catch (e) {
      debugPrint('AlarmRingService: bridge système non disponible: $e');
      _nativeBridgeAvailableCache = false;
      return false;
    }
  }

  int _idFor(String ownerPhone, String notificationKey) {
    var hash = 0;
    for (final unit in 'alarm:$ownerPhone|$notificationKey'.codeUnits) {
      hash = ((hash * 31) + unit) & 0x1fffffff;
    }
    return hash == 0 ? 1 : hash;
  }

  Future<bool> _scheduleNativeAndroidAlarm({
    required int id,
    required String payload,
    required String title,
    required String body,
    required DateTime fireAt,
    required bool vibration,
  }) async {
    try {
      return await _fullScreenAlarmChannel.invokeMethod<bool>(
            'scheduleSystemAlarm',
            <String, Object>{
              'alarmId': id,
              'triggerAtMillis': fireAt.millisecondsSinceEpoch,
              'alarmTitle': title,
              'alarmBody': body,
              'alarmPayload': payload,
              'vibration': vibration,
            },
          ) ??
          false;
    } catch (e) {
      debugPrint('AlarmRingService: programmation système Android impossible: $e');
      return false;
    }
  }

  Future<bool> _scheduleLegacyAlarm({
    required int id,
    required String payload,
    required String title,
    required String body,
    required DateTime fireAt,
    required bool vibration,
  }) async {
    await _ensureInitialized();
    if (!_initialized) return false;
    try {
      return await Alarm.set(
        alarmSettings: AlarmSettings(
          id: id,
          dateTime: fireAt,
          assetAudioPath: _customSoundAsset,
          loopAudio: true,
          vibrate: vibration,
          warningNotificationOnKill:
              defaultTargetPlatform == TargetPlatform.iOS,
          androidFullScreenIntent: true,
          androidStopAlarmOnTermination: false,
          payload: payload,
          androidSnoozeDuration: const Duration(minutes: 9),
          volumeSettings: VolumeSettings.fade(
            volume: 1.0,
            fadeDuration: const Duration(seconds: 3),
            volumeEnforced: true,
          ),
          notificationSettings: NotificationSettings(
            title: title,
            body: body,
            stopButton: 'Arrêter',
            androidSnoozeButton: 'Répéter dans 9 min',
            icon: 'ic_stat_huim6',
            androidStopAlarmOnDismiss: false,
          ),
        ),
      );
    } catch (e, st) {
      debugPrint('AlarmRingService: fallback alarme ignoré: $e\n$st');
      return false;
    }
  }

  /// Programme une alarme longue pour une garde.
  ///
  /// Android : AlarmManager système natif en priorité.
  /// iOS / ancien build Android : fallback via le package `alarm`.
  Future<bool> scheduleGuardAlarm({
    required String ownerPhone,
    required String dateStr,
    required String notificationKey,
    required String title,
    required String body,
    required DateTime fireAt,
    required bool vibration,
  }) async {
    if (_isWeb || !fireAt.isAfter(DateTime.now())) return false;

    final id = _idFor(ownerPhone, notificationKey);
    final payload = 'guard:$ownerPhone:$dateStr:$notificationKey';

    if (_isAndroid && await nativeSystemAlarmAvailable()) {
      final nativeScheduled = await _scheduleNativeAndroidAlarm(
        id: id,
        payload: payload,
        title: title,
        body: body,
        fireAt: fireAt,
        vibration: vibration,
      );
      if (nativeScheduled) return true;
      // Ne pas perdre le rappel si un OEM refuse ponctuellement AlarmManager.
      debugPrint(
        'AlarmRingService: bascule sur le fallback Flutter après échec natif.',
      );
    }

    return _scheduleLegacyAlarm(
      id: id,
      payload: payload,
      title: title,
      body: body,
      fireAt: fireAt,
      vibration: vibration,
    );
  }

  /// Teste le vrai chemin de programmation Android.
  ///
  /// Sur les nouveaux builds, le test est posé dans AlarmManager à +2 secondes
  /// au lieu d'ouvrir artificiellement l'écran depuis Flutter. Cela vérifie le
  /// même mécanisme que les futures alarmes de garde.
  Future<bool> ringTestNow({required bool vibration}) async {
    if (_isWeb) return false;

    if (_isAndroid && await nativeSystemAlarmAvailable(refresh: true)) {
      return _scheduleNativeAndroidAlarm(
        id: _testAlarmId,
        payload: 'guard:test',
        title: 'Test alarme système de garde',
        body:
            'Test GardeFlow : Android doit ouvrir le grand écran d’alarme dans quelques secondes.',
        fireAt: DateTime.now().add(const Duration(seconds: 2)),
        vibration: vibration,
      );
    }

    await _ensureInitialized();
    if (!_initialized) return false;
    try {
      final scheduled = await Alarm.set(
        alarmSettings: AlarmSettings(
          id: _testAlarmId,
          dateTime: DateTime.now().add(const Duration(milliseconds: 500)),
          assetAudioPath: _customSoundAsset,
          loopAudio: true,
          vibrate: vibration,
          warningNotificationOnKill:
              defaultTargetPlatform == TargetPlatform.iOS,
          androidFullScreenIntent: true,
          androidStopAlarmOnTermination: false,
          payload: 'guard:test',
          androidSnoozeDuration: const Duration(minutes: 9),
          volumeSettings: VolumeSettings.fade(
            volume: 1.0,
            fadeDuration: const Duration(seconds: 2),
            volumeEnforced: true,
          ),
          notificationSettings: const NotificationSettings(
            title: 'Test alarme de garde',
            body:
                'Ceci est un test GardeFlow. Utilisez Rappel 9 min ou Arrêter.',
            stopButton: 'Arrêter',
            androidSnoozeButton: 'Répéter dans 9 min',
            androidStopAlarmOnDismiss: false,
          ),
        ),
      );

      if (scheduled && _isAndroid) {
        await Future<void>.delayed(const Duration(milliseconds: 650));
        try {
          await _fullScreenAlarmChannel.invokeMethod<void>(
            'openAlarmActivity',
            <String, Object>{
              'alarmId': _testAlarmId,
              'alarmTitle': 'Test alarme de garde',
              'alarmBody':
                  'Ceci est un test GardeFlow. Utilisez « RAPPEL 9 MIN » ou « J’AI VU — ARRÊTER ».',
              'alarmSnoozeLabel': 'RAPPEL 9 MIN',
              'forceFullScreen': true,
              'vibration': vibration,
            },
          );
        } catch (e) {
          debugPrint(
            'AlarmRingService: ouverture plein écran fallback ignorée: $e',
          );
        }
      }
      return scheduled;
    } catch (e) {
      debugPrint('AlarmRingService: test fallback ignoré: $e');
      return false;
    }
  }

  Future<void> cancelGuardAlarms(String ownerPhone, String dateStr) async {
    if (_isWeb) return;
    final prefix = 'guard:$ownerPhone:$dateStr:';

    if (_isAndroid && await nativeSystemAlarmAvailable()) {
      try {
        await _fullScreenAlarmChannel.invokeMethod<void>(
          'cancelSystemGuardAlarms',
          <String, Object>{'payloadPrefix': prefix},
        );
      } catch (e) {
        debugPrint('AlarmRingService: annulation système ignorée: $e');
      }
    }

    // Nettoyage du moteur historique pour les alarmes créées par un ancien APK.
    try {
      await _ensureInitialized();
      if (!_initialized) return;
      final alarms = await Alarm.getAlarms();
      for (final alarm in alarms) {
        if (alarm.payload?.startsWith(prefix) == true) {
          try {
            await Alarm.stop(alarm.id);
          } catch (e) {
            debugPrint('AlarmRingService: annulation ${alarm.id} ignorée: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('AlarmRingService: annulation fallback impossible: $e');
    }
  }

  Future<void> cancelAll() async {
    if (_isWeb) return;

    if (_isAndroid && await nativeSystemAlarmAvailable()) {
      try {
        await _fullScreenAlarmChannel
            .invokeMethod<void>('cancelAllSystemGuardAlarms');
      } catch (e) {
        debugPrint('AlarmRingService: nettoyage système ignoré: $e');
      }
    }

    try {
      await _ensureInitialized();
      if (!_initialized) return;
      final alarms = await Alarm.getAlarms();
      for (final alarm in alarms) {
        if (alarm.payload?.startsWith('guard:') != true) continue;
        try {
          await Alarm.stop(alarm.id);
        } catch (e) {
          debugPrint('AlarmRingService: annulation ${alarm.id} ignorée: $e');
        }
      }
    } catch (e) {
      debugPrint('AlarmRingService: nettoyage fallback ignoré: $e');
    }
  }
}
