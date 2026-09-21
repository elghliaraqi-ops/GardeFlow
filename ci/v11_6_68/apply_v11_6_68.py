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
}
for file_name, needles in checks.items():
    text = Path(file_name).read_text()
    for needle in needles:
        if needle not in text:
            raise SystemExit(
                f"V11.6.68 validation failed: {needle!r} missing in {file_name}"
            )

print("GardeFlow V11.6.68 account isolation + PDF matching hardening applied")
