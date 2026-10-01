import 'package:flutter/foundation.dart';

import '../data/profile_avatars.dart';
import 'supabase_backend_service.dart';

class ProfileAvatarService extends ChangeNotifier {
  ProfileAvatarService._();

  static final ProfileAvatarService instance = ProfileAvatarService._();

  final Map<String, String?> _avatarByProfileId = <String, String?>{};
  Future<void>? _loadInFlight;
  DateTime? _lastLoadedAt;

  String? avatarKeyFor(String profileId) => _avatarByProfileId[profileId];

  Future<void> ensureLoaded({bool force = false}) async {
    final backend = SupabaseBackendService.instance;
    if (!backend.enabled || backend.client.auth.currentUser == null) return;

    final lastLoadedAt = _lastLoadedAt;
    if (!force &&
        lastLoadedAt != null &&
        DateTime.now().difference(lastLoadedAt) < const Duration(seconds: 30)) {
      return;
    }

    final inFlight = _loadInFlight;
    if (inFlight != null) return inFlight;

    final future = _load();
    _loadInFlight = future;
    try {
      await future;
    } finally {
      if (identical(_loadInFlight, future)) _loadInFlight = null;
    }
  }

  Future<void> _load() async {
    final rows = await SupabaseBackendService.instance.client
        .rpc('profile_avatar_keys');
    final next = <String, String?>{};

    if (rows is List) {
      for (final raw in rows) {
        if (raw is! Map) continue;
        final row = Map<String, dynamic>.from(raw);
        final profileId = row['profile_id']?.toString().trim() ?? '';
        final rawKey = row['avatar_key']?.toString().trim();
        final key = rawKey == null || rawKey.isEmpty ? null : rawKey;
        if (profileId.isEmpty) continue;
        next[profileId] = profileAvatarByKey(key) == null ? null : key;
      }
    }

    _avatarByProfileId
      ..clear()
      ..addAll(next);
    _lastLoadedAt = DateTime.now();
    notifyListeners();
  }

  Future<void> setMyAvatar(String? avatarKey) async {
    final normalized = avatarKey?.trim();
    final value = normalized == null || normalized.isEmpty ? null : normalized;
    if (!isProfileAvatarKeyAllowed(value)) {
      throw ArgumentError('Avatar GardeFlow invalide.');
    }

    final backend = SupabaseBackendService.instance;
    if (!backend.enabled || backend.client.auth.currentUser == null) {
      throw StateError('Connexion au serveur requise pour choisir un avatar.');
    }

    await backend.client.rpc(
      'set_my_profile_avatar',
      params: <String, dynamic>{'p_avatar_key': value},
    );

    final userId = backend.client.auth.currentUser?.id;
    if (userId != null) _avatarByProfileId[userId] = value;
    _lastLoadedAt = DateTime.now();
    notifyListeners();
  }

  void clearSessionCache() {
    if (_avatarByProfileId.isEmpty && _lastLoadedAt == null) return;
    _avatarByProfileId.clear();
    _lastLoadedAt = null;
    notifyListeners();
  }
}
