from pathlib import Path


def must_replace(path: str, old: str, new: str, count: int = 1) -> None:
    p = Path(path)
    text = p.read_text()
    if old not in text:
        raise SystemExit(f"V11.6.10: pattern not found in {path}: {old[:180]!r}")
    p.write_text(text.replace(old, new, count))


must_replace('pubspec.yaml', 'version: 11.6.9+169', 'version: 11.6.10+170')

# Android 16/Samsung hotfix: never call FlutterLocalNotificationsPlugin.cancelAll().
# On some devices this native cancelAllNotifications path can throw during app
# startup and prevent GardeFlow from opening. Enumerate pending requests instead,
# cancel only GardeFlow guard reminders, and swallow notification-plugin errors so
# the reminder subsystem can never block application startup.
must_replace(
    'lib/services/notification_service.dart',
    """  Future<void> cancelAll() async {\n    if (kIsWeb) return;\n    await init();\n    await _plugin.cancelAll();\n  }\n""",
    """  Future<void> cancelAll() async {\n    if (kIsWeb) return;\n    try {\n      await init();\n      final pending = await _plugin.pendingNotificationRequests();\n      for (final item in pending) {\n        final payload = item.payload ?? '';\n        if (!payload.startsWith('guard:')) continue;\n        try {\n          await _plugin.cancel(item.id);\n        } catch (e) {\n          debugPrint('Annulation du rappel ${item.id} ignorée: $e');\n        }\n      }\n    } catch (e) {\n      // A notification failure must never prevent GardeFlow from opening.\n      debugPrint('Nettoyage des rappels ignoré au démarrage: $e');\n      reminderStatus.value = 'Rappels locaux momentanément indisponibles';\n    }\n  }\n""",
)

# Harden scheduling too: plugin initialization is best-effort during background
# reminder synchronization. If Android refuses the plugin call, the app continues
# normally and the user can retry from Settings > Rappels de garde.
must_replace(
    'lib/services/notification_service.dart',
    """  Future<void> scheduleReminder({\n    required String ownerPhone,\n    required String dateStr,\n    required String notificationKey,\n    required String title,\n    required String body,\n    required DateTime fireAt,\n    required String soundMode,\n    required bool vibration,\n  }) async {\n    if (kIsWeb || !fireAt.isAfter(DateTime.now())) return;\n    await init();\n\n    final details = _reminderDetails(soundMode: soundMode, vibration: vibration);\n""",
    """  Future<void> scheduleReminder({\n    required String ownerPhone,\n    required String dateStr,\n    required String notificationKey,\n    required String title,\n    required String body,\n    required DateTime fireAt,\n    required String soundMode,\n    required bool vibration,\n  }) async {\n    if (kIsWeb || !fireAt.isAfter(DateTime.now())) return;\n    try {\n      await init();\n    } catch (e) {\n      debugPrint('Initialisation des rappels ignorée: $e');\n      reminderStatus.value = 'Rappels locaux momentanément indisponibles';\n      return;\n    }\n\n    final details = _reminderDetails(soundMode: soundMode, vibration: vibration);\n""",
)

# Targeted cancellation gets the same startup-safe treatment.
must_replace(
    'lib/services/notification_service.dart',
    """  Future<void> cancelGuardReminders(String ownerPhone, String dateStr) async {\n    if (kIsWeb) return;\n    await init();\n    final prefix = 'guard:$ownerPhone:$dateStr:';\n    try {\n""",
    """  Future<void> cancelGuardReminders(String ownerPhone, String dateStr) async {\n    if (kIsWeb) return;\n    final prefix = 'guard:$ownerPhone:$dateStr:';\n    try {\n      await init();\n""",
)

print('GardeFlow V11.6.10 notification startup hotfix applied successfully')
