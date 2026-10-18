import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:huim6_planning/services/local_storage_service.dart';
import 'package:huim6_planning/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Corrupted persisted snapshot is not erased during protected startup',
      () async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{'huim6_state_v5': '{NOT VALID JSON'});
    final app = await AppState.load(skipExternalServices: true);
    expect(app.localSnapshotReadOnly, isTrue);
    // Actions that persist state must not overwrite an unreadable snapshot.
    await app.setDarkMode(true);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('huim6_state_v5'), '{NOT VALID JSON');
  });

  test('Oversized photo cache remains untouched, startup proceeds', () async {
    final original = '{"astreinte":"' + List<String>.filled(8 * 1024 * 1024 + 1, 'x').join() + '"}';
    SharedPreferences.setMockInitialValues(
        <String, Object>{'huim6_state_v5': original});
    final app = await AppState.load(skipExternalServices: true);
    expect(app.localSnapshotReadOnly, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('huim6_state_v5'), original);
  });

  test('Storage platform timeout yields protected, usable state', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final app = await AppState.load(
      skipExternalServices: true,
      snapshotReader: () => Future<Map<String, dynamic>?>.error(
          StateError('Simulated SharedPreferences failure')),
    );
    expect(app.localSnapshotReadOnly, isTrue);
  });

  test('Valid legacy data is still read normally', () async {
    SharedPreferences.setMockInitialValues(
        <String, Object>{'huim6_state_v5': '{"appearanceTheme":"green"}'});
    final restored = await LocalStorageService.loadState();
    expect(restored?['appearanceTheme'], 'green');
    final app = await AppState.load(skipExternalServices: true);
    expect(app.localSnapshotReadOnly, isFalse);
    expect(app.appearanceTheme, 'green');
  });
}
