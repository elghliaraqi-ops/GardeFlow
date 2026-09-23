import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistance locale multiplateforme (Web, Android, iOS, desktop).
/// Les données métier sont stockées sous forme JSON dans SharedPreferences.
class LocalStorageService {
  LocalStorageService._();
  static const _stateKey = 'huim6_state_v5';
  static const _sessionKey = 'huim6_session_phone_v5';
  static const _pushDeviceKey = 'gardeflow_push_device_id_v1';
  static const _pushActiveUserKey = 'gardeflow_push_active_user_v1';
  static const _pushEnabledKey = 'gardeflow_push_enabled_v1';

  static Future<Map<String, dynamic>?> loadState() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_stateKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveState(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_stateKey, jsonEncode(data));
  }

  static Future<String?> loadSessionPhone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_sessionKey);
  }

  static Future<void> saveSessionPhone(String? phone) async {
    final prefs = await SharedPreferences.getInstance();
    if (phone == null) {
      await prefs.remove(_sessionKey);
    } else {
      await prefs.setString(_sessionKey, phone);
    }
  }

  static Future<String?> loadPushActiveUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pushActiveUserKey);
  }

  static Future<void> savePushActiveUserId(String? userId) async {
    final prefs = await SharedPreferences.getInstance();
    if (userId == null || userId.trim().isEmpty) {
      await prefs.remove(_pushActiveUserKey);
    } else {
      await prefs.setString(_pushActiveUserKey, userId.trim());
    }
  }

  static Future<bool> loadPushEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_pushEnabledKey) ?? false;
  }

  static Future<void> savePushEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_pushEnabledKey, enabled);
  }

  static Future<String> loadOrCreatePushDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_pushDeviceKey)?.trim();
    if (existing != null && existing.isNotEmpty) return existing;
    final random = Random.secure();
    final id = 'gf-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
        '${random.nextInt(0x7fffffff).toRadixString(36)}';
    await prefs.setString(_pushDeviceKey, id);
    return id;
  }
}
