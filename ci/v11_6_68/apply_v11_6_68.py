from pathlib import Path

def replace_once(path, old, new, label):
    p = Path(path)
    s = p.read_text()
    if old not in s:
        raise SystemExit(f"V11.6.68: {label} anchor missing in {path}")
    p.write_text(s.replace(old, new, 1))
    print(f"V11.6.68: {label} applied")

replace_once(
    "pubspec.yaml",
    "version: 11.6.67+227",
    "version: 11.6.68+228",
    "version bump",
)

# Session generation: any in-flight reload started for account A must not
# apply its results after logout/login of account B.
replace_once(
    "lib/state/app_state.dart",
    """  StreamSubscription? _directoryRealtime;

  static Future<AppState> load() async {""",
    """  StreamSubscription? _directoryRealtime;
  int _sessionEpoch = 0;

  static Future<AppState> load() async {""",
    "session epoch field",
)

replace_once(
    "lib/state/app_state.dart",
    """          state.currentUser=profile;
          state._applyReminderPrefsForCurrentUser();""",
    """          state._sessionEpoch++;
          state.currentUser=profile;
          state._applyReminderPrefsForCurrentUser();""",
    "restore backend session epoch",
)

replace_once(
    "lib/state/app_state.dart",
    """        state.currentUser = state._users.where((u) => u.phone == sessionPhone).firstOrNull;
        state._applyReminderPrefsForCurrentUser();""",
    """        state.currentUser = state._users.where((u) => u.phone == sessionPhone).firstOrNull;
        if (state.currentUser != null) state._sessionEpoch++;
        state._applyReminderPrefsForCurrentUser();""",
    "restore local session epoch",
)

replace_once(
    "lib/state/app_state.dart",
    """        currentUser=user;
        _applyReminderPrefsForCurrentUser();""",
    """        _sessionEpoch++;
        currentUser=user;
        _applyReminderPrefsForCurrentUser();""",
    "backend login epoch",
)

replace_once(
    "lib/state/app_state.dart",
    """    currentUser=user;_applyReminderPrefsForCurrentUser();unawaited(LocalStorageService.saveSessionPhone(user.phone));""",
    """    _sessionEpoch++;currentUser=user;_applyReminderPrefsForCurrentUser();unawaited(LocalStorageService.saveSessionPhone(user.phone));""",
    "local login epoch",
)

replace_once(
    "lib/state/app_state.dart",
    """  Future<void> logout() async {
    NotificationService.instance.cancelAll();
    _stopRealtime();
    if(backendEnabled){
      await PushNotificationService.instance.unregisterCurrentDevice();
      await SupabaseBackendService.instance.signOut();
    }
    currentUser=null;
    await LocalStorageService.saveSessionPhone(null);
    notifyListeners();
  }""",
    """  Future<void> logout() async {
    // Invalidate every reload already in flight before touching the session.
    _sessionEpoch++;
    _stopRealtime();
    await NotificationService.instance.cancelAll();
    if(backendEnabled){
      // Must happen while the Supabase JWT still identifies the old account.
      await PushNotificationService.instance.unregisterCurrentDevice();
      await SupabaseBackendService.instance.signOut();
    }
    currentUser=null;
    await LocalStorageService.saveSessionPhone(null);
    notifyListeners();
  }""",
    "atomic logout ordering",
)

replace_once(
    "lib/state/app_state.dart",
    """  Future<void> _reloadFromBackend() async {
    if (!backendEnabled || currentUser == null) return;
    final backend = SupabaseBackendService.instance;
    final profiles = await backend.fetchVisibleProfiles();""",
    """  Future<void> _reloadFromBackend() async {
    final sessionUser = currentUser;
    if (!backendEnabled || sessionUser == null) return;
    final expectedEpoch = _sessionEpoch;
    final expectedUserId = sessionUser.id;
    final backend = SupabaseBackendService.instance;
    final profiles = await backend.fetchVisibleProfiles();""",
    "reload session capture",
)

replace_once(
    "lib/state/app_state.dart",
    """    } catch (e) {
      debugPrint('Annuaire manuel indisponible: $e');
    }
    _users
      ..clear()""",
    """    } catch (e) {
      debugPrint('Annuaire manuel indisponible: $e');
    }
    if (_sessionEpoch != expectedEpoch || currentUser?.id != expectedUserId) {
      // A logout or account switch occurred while network calls were running.
      return;
    }
    _users
      ..clear()""",
    "reload stale-session guard",
)

# PDF import safety: a single ambiguous cell must never create several guards.
replace_once(
    "lib/services/official_roster_import_service.dart",
    """        final matched = _matchProfiles(cell.text, candidateProfiles);
        if (matched.isEmpty) {
          unmatched.add({
            'date': dateStr,
            'shift_id': cell.shiftId,
            'text': cell.text,
          });
          continue;
        }
        for (final profile in matched) {
          rawAssignments.add(OfficialRosterAssignment(
            profileId: profile.id,
            dateStr: dateStr,
            shiftId: cell.shiftId,
            isDisciplinary: _profileMarkedRed(profile, cell.fragments),
          ));
        }""",
    """        final matched = _matchProfiles(cell.text, candidateProfiles);
        if (matched.length != 1) {
          unmatched.add({
            'date': dateStr,
            'shift_id': cell.shiftId,
            'text': cell.text,
            'reason': matched.isEmpty ? 'no_match' : 'ambiguous_match',
            if (matched.length > 1)
              'candidate_profile_ids': matched.map((p) => p.id).toList(),
          });
          continue;
        }
        final profile = matched.single;
        rawAssignments.add(OfficialRosterAssignment(
          profileId: profile.id,
          dateStr: dateStr,
          shiftId: cell.shiftId,
          isDisciplinary: _profileMarkedRed(profile, cell.fragments),
        ));""",
    "unique PDF doctor matching",
)


# Accent-insensitive doctor search.
replace_once(
    "lib/screens/exchange_request_sheet.dart",
    """  @override
  void dispose() {
    _doctorSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {""",
    """  @override
  void dispose() {
    _doctorSearchController.dispose();
    super.dispose();
  }

  String _normalizeDoctorSearch(String value) {
    var s = value.toLowerCase();
    const replacements = <String, String>{
      'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a',
      'ç': 'c',
      'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
      'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
      'ñ': 'n',
      'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'œ': 'oe',
      'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
      'ý': 'y', 'ÿ': 'y', 'æ': 'ae',
      '’': ' ', "'": ' ', '-': ' ',
    };
    for (final entry in replacements.entries) {
      s = s.replaceAll(entry.key, entry.value);
    }
    return s.replaceAll(RegExp(r'\\s+'), ' ').trim();
  }

  @override
  Widget build(BuildContext context) {""",
    "accent-insensitive doctor search helper",
)

replace_once(
    "lib/screens/exchange_request_sheet.dart",
    """    final search = _doctorSearch.trim().toLowerCase();
    final filteredTargets = search.isEmpty
        ? targets
        : targets.where((c) {
            final haystack = '${c.name} ${c.service}'.toLowerCase();
            return haystack.contains(search);
          }).toList();""",
    """    final search = _normalizeDoctorSearch(_doctorSearch);
    final filteredTargets = search.isEmpty
        ? targets
        : targets.where((c) {
            final haystack = _normalizeDoctorSearch('${c.name} ${c.service}');
            return haystack.contains(search);
          }).toList();""",
    "accent-insensitive doctor filtering",
)

# Play-policy hardening: keep SCHEDULE_EXACT_ALARM (user special access) and
# remove the additional restricted USE_EXACT_ALARM declaration.
replace_once(
    "tool/configure_android.dart",
    """'SCHEDULE_EXACT_ALARM', 'VIBRATE', 'WAKE_LOCK', 'USE_FULL_SCREEN_INTENT', 'USE_EXACT_ALARM', 'FOREGROUND_SERVICE'""",
    """'SCHEDULE_EXACT_ALARM', 'VIBRATE', 'WAKE_LOCK', 'USE_FULL_SCREEN_INTENT', 'FOREGROUND_SERVICE'""",
    "remove restricted USE_EXACT_ALARM permission",
)


# Push isolation: bind every server push to the currently authenticated account,
# and delete the previous registration when FCM rotates a token.
replace_once(
    "lib/services/push_notification_service.dart",
    """  String get _platform => kIsWeb ? 'web' : _ios ? 'ios' : 'android';

  Future<void> initializeFirebase() async {""",
    """  String get _platform => kIsWeb ? 'web' : _ios ? 'ios' : 'android';

  bool _belongsToCurrentUser(RemoteMessage message) {
    final recipientId = message.data['recipientId']?.toString();
    if (recipientId == null || recipientId.isEmpty) return true;
    return SupabaseBackendService.instance.client.auth.currentUser?.id == recipientId;
  }

  Future<void> initializeFirebase() async {""",
    "push recipient guard helper",
)

replace_once(
    "lib/services/push_notification_service.dart",
    """      FirebaseMessaging.onMessage.listen((message) async {
        if (!_enabled) return;""",
    """      FirebaseMessaging.onMessage.listen((message) async {
        if (!_enabled || !_belongsToCurrentUser(message)) return;""",
    "foreground push account guard",
)

replace_once(
    "lib/services/push_notification_service.dart",
    """      FirebaseMessaging.onMessageOpenedApp.listen((message) => _open(message.data['kind']?.toString() ?? ''));
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _pendingKind = initial.data['kind']?.toString() ?? '';""",
    """      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        if (_belongsToCurrentUser(message)) {
          _open(message.data['kind']?.toString() ?? '');
        }
      });
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null && _belongsToCurrentUser(initial)) {
        _pendingKind = initial.data['kind']?.toString() ?? '';
      }""",
    "opened push account guard",
)

replace_once(
    "lib/services/push_notification_service.dart",
    """          if (!_enabled || backend.client.auth.currentUser?.id != userId) return;
          await backend.registerPushToken(token, platform: _platform);
          _registeredToken = token;
          status.value = 'Notifications push activées sur cet appareil';""",
    """          if (!_enabled || backend.client.auth.currentUser?.id != userId) return;
          final previousToken = _registeredToken;
          await backend.registerPushToken(token, platform: _platform);
          if (previousToken != null && previousToken.isNotEmpty && previousToken != token) {
            try {
              await backend.unregisterPushToken(previousToken);
            } catch (e) {
              debugPrint('Ancien token push non supprimé immédiatement: $e');
            }
          }
          _registeredToken = token;
          status.value = 'Notifications push activées sur cet appareil';""",
    "FCM token rotation cleanup",
)

checks = {
    "pubspec.yaml": ["version: 11.6.68+228"],
    "lib/state/app_state.dart": [
        "int _sessionEpoch = 0;",
        "final expectedEpoch = _sessionEpoch;",
        "currentUser?.id != expectedUserId",
        "await PushNotificationService.instance.unregisterCurrentDevice();",
        "await NotificationService.instance.cancelAll();",
    ],
    "lib/services/official_roster_import_service.dart": [
        "matched.length != 1",
        "'ambiguous_match'",
        "matched.single",
    ],
    "lib/screens/exchange_request_sheet.dart": [
        "_normalizeDoctorSearch",
        "final search = _normalizeDoctorSearch(_doctorSearch);",
    ],
    "tool/configure_android.dart": [
        "'SCHEDULE_EXACT_ALARM'",
        "'USE_FULL_SCREEN_INTENT'",
    ],
    "lib/services/push_notification_service.dart": [
        "_belongsToCurrentUser",
        "recipientId",
        "previousToken",
    ],
}
for file_name, needles in checks.items():
    text = Path(file_name).read_text()
    for needle in needles:
        if needle not in text:
            raise SystemExit(
                f"V11.6.68 validation failed: {needle!r} missing in {file_name}"
            )

if "USE_EXACT_ALARM" in Path("tool/configure_android.dart").read_text():
    raise SystemExit("V11.6.68 validation failed: restricted USE_EXACT_ALARM still declared")

print("GardeFlow V11.6.68 audit hardening applied")
