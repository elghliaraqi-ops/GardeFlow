import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Préférence purement visuelle pour l'avatar médecin affiché dans GardeFlow.
/// Elle ne modifie ni le profil métier, ni les rôles, ni les autorisations.
class DoctorVisualPreference {
  DoctorVisualPreference._();

  static const _storageKey = 'guardeflow_doctor_visual_gender';
  static final ValueNotifier<String> gender = ValueNotifier<String>('male');

  static bool _loaded = false;
  static Future<void>? _loading;

  static Future<void> ensureLoaded() {
    if (_loaded) return Future<void>.value();
    return _loading ??= _load();
  }

  static Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_storageKey);
    if (stored == 'female' || stored == 'male') {
      gender.value = stored!;
    }
    _loaded = true;
  }

  static Future<void> setGender(String value) async {
    final next = value == 'female' ? 'female' : 'male';
    await ensureLoaded();
    if (gender.value != next) gender.value = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, next);
  }
}
