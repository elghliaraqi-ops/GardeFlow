#!/usr/bin/env python3
"""Static release regression: no remote or plugin await before first frame."""
from pathlib import Path
main=Path('source/lib/main.dart').read_text()
state=Path('source/lib/state/app_state.dart').read_text()
preamble=main.split('runApp(const GardeFlowBootstrap())')[0]
assert 'await Supabase' not in preamble
assert 'await NotificationService' not in preamble
assert 'await AppState.load' not in preamble
assert 'runApp(const GardeFlowBootstrap())' in main
assert '_reportStep' in main and 'Démarrage interrompu' in main
section=state.split('static Future<AppState> load() async {')[1].split('Future<void> _restoreRemoteSession')[0]
assert 'await state._reloadFromBackend()' not in section
assert 'await state._syncMyOfficialRosterIfNeeded()' not in section
assert 'await state._activateNativeRemindersForCurrentUser()' not in section
assert 'unawaited(state._restoreRemoteSession(sessionUserId))' in section
assert 'LocalStorageService.loadState()' in section
print('PASS startup visibly paints before remote roster and Android reminders')
