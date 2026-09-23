import 'package:alarm/alarm.dart';
import 'package:flutter/foundation.dart';

/// Véritable alarme de réveil pour les gardes (V11.6.15).
///
/// Contrairement à [NotificationService], qui affiche une notification
/// classique (son bref, quelques secondes), ce service programme une
/// alarme native façon "réveil" : sonnerie en boucle, vibration continue,
/// écran qui s'allume, et un bouton "Arrêter" tant que l'utilisateur n'a
/// pas confirmé. Ça ne s'arrête jamais tout seul après quelques secondes.
///
/// Même philosophie défensive que le reste de GardeFlow : toute erreur est
/// avalée (`debugPrint`) et ne doit jamais faire planter l'application.
class AlarmRingService {
  AlarmRingService._();
  static final AlarmRingService instance = AlarmRingService._();

  bool _initialized = false;
  bool _initializing = false;

  bool get _isWeb => kIsWeb;

  /// Chemin de la sonnerie personnalisée (optionnel).
  ///
  /// Laisser `null` pour utiliser la sonnerie d'alarme par défaut de
  /// l'appareil (recommandé : aucun fichier audio à fournir, et elle est
  /// déjà longue). Pour utiliser un son maison, déposer un fichier dans
  /// `assets/sounds/garde_alarm.mp3`, le déclarer dans `pubspec.yaml`
  /// (section `flutter: assets:`) puis remplacer la valeur ci-dessous par
  /// `'assets/sounds/garde_alarm.mp3'`.
  static const String? _customSoundAsset = null;

  Future<void> _ensureInitialized() async {
    if (_initialized || _initializing || _isWeb) return;
    _initializing = true;
    try {
      await Alarm.init();
      _initialized = true;
    } catch (e, st) {
      debugPrint('AlarmRingService: initialisation ignorée: $e\n$st');
    } finally {
      _initializing = false;
    }
  }

  /// Identifiant stable et positif dérivé du couple (téléphone, clé).
  ///
  /// Espace de hachage volontairement distinct de celui utilisé par
  /// [NotificationService] (préfixe `alarm:` inclus dans le hash) pour ne
  /// jamais faire collision avec un identifiant de notification classique.
  int _idFor(String ownerPhone, String notificationKey) {
    var hash = 0;
    for (final unit in 'alarm:$ownerPhone|$notificationKey'.codeUnits) {
      hash = ((hash * 31) + unit) & 0x1fffffff;
    }
    return hash == 0 ? 1 : hash;
  }

  /// Programme une alarme sonnerie longue pour une garde.
  ///
  /// [ownerPhone] et [dateStr] servent de préfixe pour retrouver et annuler
  /// toutes les alarmes d'une garde ensuite (voir [cancelGuardAlarms]).
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
    await _ensureInitialized();
    if (!_initialized) return false;

    final id = _idFor(ownerPhone, notificationKey);
    final payload = 'guard:$ownerPhone:$dateStr:$notificationKey';

    try {
      return await Alarm.set(
        alarmSettings: AlarmSettings(
          id: id,
          dateTime: fireAt,
          assetAudioPath: _customSoundAsset,
          loopAudio: true,
          vibrate: vibration,
          warningNotificationOnKill: defaultTargetPlatform == TargetPlatform.iOS,
          androidFullScreenIntent: true,
          androidStopAlarmOnTermination: false,
          payload: payload,
          androidSnoozeDuration: const Duration(minutes: 9),
          volumeSettings: VolumeSettings.fade(
            volume: 1.0,
            fadeDuration: Duration(seconds: 3),
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
      debugPrint('AlarmRingService: programmation ignorée: $e\n$st');
      return false;
    }
  }

  /// Sonne immédiatement jusqu’à Arrêter pour tester le réglage.
  Future<bool> ringTestNow({required bool vibration}) async {
    if (_isWeb) return false;
    await _ensureInitialized();
    if (!_initialized) return false;
    try {
      return await Alarm.set(
        alarmSettings: AlarmSettings(
          id: 0x1ffffffe,
          dateTime: DateTime.now().add(const Duration(seconds: 1)),
          assetAudioPath: _customSoundAsset,
          loopAudio: true,
          vibrate: vibration,
          warningNotificationOnKill: defaultTargetPlatform == TargetPlatform.iOS,
          androidFullScreenIntent: true,
          androidStopAlarmOnTermination: false,
          payload: 'guard:test',
          volumeSettings: VolumeSettings.fade(
            volume: 1.0,
            fadeDuration: Duration(seconds: 2),
            volumeEnforced: true,
          ),
          notificationSettings: const NotificationSettings(
            title: 'Test alarme de garde',
            body: 'Ceci est un test GardeFlow. Appuyez sur Arrêter pour couper la sonnerie.',
            stopButton: 'Arrêter',
            androidStopAlarmOnDismiss: false,
          ),
        ),
      );
    } catch (e) {
      debugPrint('AlarmRingService: test ignoré: $e');
      return false;
    }
  }

  Future<void> cancelGuardAlarms(String ownerPhone, String dateStr) async {
    if (_isWeb) return;
    final prefix = 'guard:$ownerPhone:$dateStr:';
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
      debugPrint('AlarmRingService: annulation ciblée impossible: $e');
    }
  }

  Future<void> cancelAll() async {
    if (_isWeb) return;
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
      debugPrint('AlarmRingService: nettoyage ignoré: $e');
    }
  }
}
