import 'dart:async';
import 'dart:convert';

import 'package:alarm/alarm.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppleAlarmKitStatus {
  final bool supported;
  final String authorization;
  final String engine;

  const AppleAlarmKitStatus({
    required this.supported,
    required this.authorization,
    required this.engine,
  });

  const AppleAlarmKitStatus.unsupported()
      : supported = false,
        authorization = 'unsupported',
        engine = 'legacy';

  bool get authorized => supported && authorization == 'authorized';
  bool get denied => supported && authorization == 'denied';
  bool get notDetermined =>
      supported && authorization == 'notDetermined';

  factory AppleAlarmKitStatus.fromMap(Map<dynamic, dynamic>? raw) {
    if (raw == null) return const AppleAlarmKitStatus.unsupported();
    return AppleAlarmKitStatus(
      supported: raw['supported'] == true,
      authorization: (raw['authorization'] ?? 'unknown').toString(),
      engine: (raw['engine'] ?? 'legacy').toString(),
    );
  }
}

class _IosAlarmRegistryEntry {
  final String uuid;
  final String payload;
  final int fireAtMillis;

  const _IosAlarmRegistryEntry({
    required this.uuid,
    required this.payload,
    required this.fireAtMillis,
  });

  factory _IosAlarmRegistryEntry.fromJson(Map<String, dynamic> json) =>
      _IosAlarmRegistryEntry(
        uuid: (json['uuid'] ?? '').toString(),
        payload: (json['payload'] ?? '').toString(),
        fireAtMillis: (json['fireAtMillis'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'uuid': uuid,
        'payload': payload,
        'fireAtMillis': fireAtMillis,
      };
}

/// Moteur d'alarme de garde.
///
/// Android utilise le bridge AlarmManager natif avec écran plein écran.
/// iOS 26+ utilise AlarmKit via un bridge natif Apple afin que les alarmes
/// restent gérées par le système même si GardeFlow n'est plus en mémoire.
/// iOS 13-25 conserve le package `alarm` comme filet de compatibilité.
class AlarmRingService {
  AlarmRingService._();
  static final AlarmRingService instance = AlarmRingService._();

  static const MethodChannel _fullScreenAlarmChannel =
      MethodChannel('gardeflow/fullscreen_alarm');
  static const MethodChannel _iosAlarmKitChannel =
      MethodChannel('gardeflow/ios_alarmkit');
  static const int _testAlarmId = 0x1ffffffe;
  static const String _iosAlarmRegistryKey =
      'gardeflow_ios_alarmkit_registry_v1';

  bool _initialized = false;
  Future<void>? _initializationFuture;
  bool? _nativeBridgeAvailableCache;
  Future<void> _iosSerialTail = Future<void>.value();

  bool get _isWeb => kIsWeb;
  bool get _isAndroid =>
      !_isWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get _isIOS => !_isWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static const String? _customSoundAsset = null;

  Future<void> _ensureInitialized() async {
    if (_initialized || _isWeb) return;
    final existing = _initializationFuture;
    if (existing != null) {
      await existing;
      return;
    }

    final completer = Completer<void>();
    _initializationFuture = completer.future;
    try {
      await Alarm.init();
      if (_isIOS) {
        try {
          await Alarm.setWarningNotificationOnKill(
            'Rappels de garde GardeFlow',
            'Pour les anciens iPhone/iOS, évitez de forcer la fermeture de GardeFlow afin de préserver les alarmes programmées.',
          );
        } catch (e) {
          debugPrint(
            'AlarmRingService: avertissement iOS après fermeture ignoré: $e',
          );
        }
      }
      _initialized = true;
      completer.complete();
    } catch (e, st) {
      debugPrint('AlarmRingService: initialisation fallback ignorée: $e\n$st');
      completer.complete();
    } finally {
      _initializationFuture = null;
    }
  }

  Future<T> _serialOnIOS<T>(Future<T> Function() operation) {
    if (!_isIOS) return operation();
    final completer = Completer<T>();
    _iosSerialTail = _iosSerialTail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
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

  Future<AppleAlarmKitStatus> appleAlarmKitStatus() async {
    if (!_isIOS) return const AppleAlarmKitStatus.unsupported();
    try {
      final raw = await _iosAlarmKitChannel.invokeMethod<dynamic>('status');
      if (raw is Map) return AppleAlarmKitStatus.fromMap(raw);
    } on MissingPluginException {
      return const AppleAlarmKitStatus.unsupported();
    } catch (e) {
      debugPrint('AlarmRingService: lecture état AlarmKit ignorée: $e');
    }
    return const AppleAlarmKitStatus.unsupported();
  }

  Future<AppleAlarmKitStatus> requestAppleAlarmKitAuthorization() async {
    if (!_isIOS) return const AppleAlarmKitStatus.unsupported();
    final current = await appleAlarmKitStatus();
    if (!current.supported || current.authorized || current.denied) {
      return current;
    }
    try {
      final raw =
          await _iosAlarmKitChannel.invokeMethod<dynamic>('requestAuthorization');
      if (raw is Map) return AppleAlarmKitStatus.fromMap(raw);
    } catch (e) {
      debugPrint('AlarmRingService: autorisation AlarmKit impossible: $e');
    }
    return appleAlarmKitStatus();
  }

  Future<bool> openIOSAppSettings() async {
    if (!_isIOS) return false;
    try {
      return await _iosAlarmKitChannel.invokeMethod<bool>('openSettings') ??
          false;
    } catch (e) {
      debugPrint('AlarmRingService: ouverture Réglages iOS impossible: $e');
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

  String _iosUuidForId(int id) {
    final suffix = id.toUnsigned(32).toRadixString(16).padLeft(12, '0');
    return '47465244-464C-4F57-8000-${suffix.substring(suffix.length - 12)}';
  }

  Future<List<_IosAlarmRegistryEntry>> _loadIosRegistry() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_iosAlarmRegistryKey) ?? const <String>[];
    final now = DateTime.now().millisecondsSinceEpoch;
    final items = <_IosAlarmRegistryEntry>[];
    for (final encoded in raw) {
      try {
        final decoded = jsonDecode(encoded);
        if (decoded is! Map) continue;
        final entry = _IosAlarmRegistryEntry.fromJson(
          Map<String, dynamic>.from(decoded),
        );
        if (entry.uuid.isEmpty) continue;
        if (entry.fireAtMillis > 0 && entry.fireAtMillis < now - 86400000) {
          continue;
        }
        items.add(entry);
      } catch (_) {
        // Entrée historique illisible : on l'ignore et on la nettoie au save.
      }
    }
    return items;
  }

  Future<void> _saveIosRegistry(List<_IosAlarmRegistryEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = entries.map((entry) => jsonEncode(entry.toJson())).toList();
    await prefs.setStringList(_iosAlarmRegistryKey, encoded);
  }

  Future<void> _rememberIosAlarm(_IosAlarmRegistryEntry entry) async {
    final entries = await _loadIosRegistry();
    entries.removeWhere((item) => item.uuid == entry.uuid);
    entries.add(entry);
    await _saveIosRegistry(entries);
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

  Future<bool> _scheduleNativeIosAlarm({
    required int id,
    required String payload,
    required String title,
    required String body,
    required DateTime fireAt,
    bool remember = true,
  }) async {
    if (!_isIOS) return false;
    return _serialOnIOS(() async {
      final uuid = _iosUuidForId(id);
      try {
        final scheduled = await _iosAlarmKitChannel.invokeMethod<bool>(
              'schedule',
              <String, Object>{
                'uuid': uuid,
                'triggerAtMillis': fireAt.millisecondsSinceEpoch,
                'title': title,
                'body': body,
                'payload': payload,
              },
            ) ??
            false;
        if (scheduled && remember) {
          await _rememberIosAlarm(
            _IosAlarmRegistryEntry(
              uuid: uuid,
              payload: payload,
              fireAtMillis: fireAt.millisecondsSinceEpoch,
            ),
          );
        }
        return scheduled;
      } catch (e) {
        debugPrint('AlarmRingService: programmation AlarmKit impossible: $e');
        return false;
      }
    });
  }

  Future<void> _cancelNativeIosWhere(bool Function(String payload) test) async {
    if (!_isIOS) return;
    await _serialOnIOS(() async {
      final entries = await _loadIosRegistry();
      final survivors = <_IosAlarmRegistryEntry>[];
      for (final entry in entries) {
        if (!test(entry.payload)) {
          survivors.add(entry);
          continue;
        }
        try {
          final cancelled = await _iosAlarmKitChannel.invokeMethod<bool>(
                'cancel',
                <String, Object>{'uuid': entry.uuid},
              ) ??
              false;
          if (!cancelled) survivors.add(entry);
        } catch (e) {
          debugPrint(
            'AlarmRingService: annulation AlarmKit ${entry.uuid} ignorée: $e',
          );
          survivors.add(entry);
        }
      }
      await _saveIosRegistry(survivors);
    });
  }

  Future<bool> _scheduleLegacyAlarm({
    required int id,
    required String payload,
    required String title,
    required String body,
    required DateTime fireAt,
    required bool vibration,
  }) async {
    Future<bool> run() async {
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
            warningNotificationOnKill: _isIOS,
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

    return _serialOnIOS(run);
  }

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
      debugPrint(
        'AlarmRingService: bascule sur le fallback Flutter après échec Android natif.',
      );
    }

    if (_isIOS) {
      final apple = await appleAlarmKitStatus();
      if (apple.authorized) {
        final nativeScheduled = await _scheduleNativeIosAlarm(
          id: id,
          payload: payload,
          title: title,
          body: body,
          fireAt: fireAt,
        );
        if (nativeScheduled) return true;
        debugPrint(
          'AlarmRingService: bascule iOS vers le moteur compatible après échec AlarmKit.',
        );
      }
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

  Future<bool> ringTestNow({required bool vibration}) async {
    if (_isWeb) return false;

    // Le bouton de test doit tester l'écran plein écran lui-même, pas la
    // capacité Android à programmer une alarme exacte. Sur Android, le bridge
    // natif ouvre donc immédiatement la même AlarmActivity que les vraies
    // gardes. Cette voie ne touche pas à la programmation des alarmes réelles.
    if (_isAndroid && await nativeSystemAlarmAvailable(refresh: true)) {
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
        return true;
      } catch (e) {
        debugPrint(
          'AlarmRingService: ouverture plein écran native impossible: $e',
        );
        // Si le bridge natif est présent mais que l'ouverture échoue, le
        // fallback Flutter ci-dessous reste disponible.
      }
    }

    if (_isIOS) {
      final apple = await appleAlarmKitStatus();
      if (apple.authorized) {
        return _scheduleNativeIosAlarm(
          id: _testAlarmId,
          payload: 'guard:test',
          title: 'Test rappel de garde',
          body: 'GardeFlow · alarme système Apple',
          fireAt: DateTime.now().add(const Duration(seconds: 3)),
          remember: false,
        );
      }
    }

    Future<bool> runFallback() async {
      await _ensureInitialized();
      if (!_initialized) return false;
      try {
        return await Alarm.set(
          alarmSettings: AlarmSettings(
            id: _testAlarmId,
            dateTime: DateTime.now().add(const Duration(milliseconds: 700)),
            assetAudioPath: _customSoundAsset,
            loopAudio: true,
            vibrate: vibration,
            warningNotificationOnKill: _isIOS,
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
              body: 'Ceci est un test GardeFlow.',
              stopButton: 'Arrêter',
              androidSnoozeButton: 'Répéter dans 9 min',
              androidStopAlarmOnDismiss: false,
            ),
          ),
        );
      } catch (e) {
        debugPrint('AlarmRingService: test fallback ignoré: $e');
        return false;
      }
    }

    final scheduled = await _serialOnIOS(runFallback);
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

    if (_isIOS) {
      await _cancelNativeIosWhere((payload) => payload.startsWith(prefix));
    }

    Future<void> cleanupFallback() async {
      try {
        await _ensureInitialized();
        if (!_initialized) return;
        final alarms = await Alarm.getAlarms();
        for (final alarm in alarms) {
          if (alarm.payload?.startsWith(prefix) == true) {
            try {
              await Alarm.stop(alarm.id);
            } catch (e) {
              debugPrint(
                'AlarmRingService: annulation ${alarm.id} ignorée: $e',
              );
            }
          }
        }
      } catch (e) {
        debugPrint('AlarmRingService: annulation fallback impossible: $e');
      }
    }

    await _serialOnIOS(cleanupFallback);
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

    if (_isIOS) {
      await _cancelNativeIosWhere((payload) => payload.startsWith('guard:'));
    }

    Future<void> cleanupFallback() async {
      try {
        await _ensureInitialized();
        if (!_initialized) return;
        final alarms = await Alarm.getAlarms();
        for (final alarm in alarms) {
          if (alarm.payload?.startsWith('guard:') != true) continue;
          try {
            await Alarm.stop(alarm.id);
          } catch (e) {
            debugPrint(
              'AlarmRingService: annulation ${alarm.id} ignorée: $e',
            );
          }
        }
      } catch (e) {
        debugPrint('AlarmRingService: nettoyage fallback ignoré: $e');
      }
    }

    await _serialOnIOS(cleanupFallback);
  }
}
