from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f'{label}: source block not found')
    return text.replace(old, new, 1)

# Only expose the interactive QCM UI when the five AI questions are ready.
# Server fallbacks remain a resilience layer, but the user asked specifically
# for AI explanations after every answer.
path = Path('source/lib/screens/clinical_cases_section.dart')
text = path.read_text(encoding='utf-8')
old = '''  void _syncQcms({required bool resetIndex}) {
    _qcms = List<ClinicalCaseQcm>.from(widget.post.qcms)
      ..sort((a, b) => a.position.compareTo(b.position));
    if (_qcms.isEmpty) {
'''
new = '''  void _syncQcms({required bool resetIndex}) {
    final available = List<ClinicalCaseQcm>.from(widget.post.qcms)
      ..sort((a, b) => a.position.compareTo(b.position));
    final aiReady = available.length == 5 &&
        available.every((qcm) => qcm.generationSource == 'openai');
    _qcms = aiReady ? available : <ClinicalCaseQcm>[];
    if (_qcms.isEmpty) {
'''
text = replace_once(text, old, new, 'AI QCM gating')
text = text.replace(
    'Les 5 QCM de ce cas sont en préparation…',
    'Les 5 QCM et leurs explications IA sont en préparation…',
)
path.write_text(text, encoding='utf-8')

# Avoid a PushNotificationService <-> AppState circular import. HomeScreen owns
# the navigation state, so the push service receives a simple callback.
path = Path('source/lib/services/push_notification_service.dart')
text = path.read_text(encoding='utf-8')
text = text.replace("import '../screens/practice_screen.dart';\n", '')
text = text.replace("import '../state/app_state.dart';\n", '')
text = replace_once(
    text,
    '  AppState? _appState;\n',
    '  void Function()? _openPractice;\n',
    'push callback field',
)
text = replace_once(
    text,
    '''  void navigationReady({required bool isAdmin, AppState? appState}) {
    _navigationReady = true;
    _isAdmin = isAdmin;
    _appState = appState ?? _appState;
''',
    '''  void navigationReady({
    required bool isAdmin,
    void Function()? onPractice,
  }) {
    _navigationReady = true;
    _isAdmin = isAdmin;
    _openPractice = onPractice ?? _openPractice;
''',
    'push navigation callback',
)
text = replace_once(
    text,
    '''    if (kind.startsWith('practice_') && _appState != null) {
      huimNavigatorKey.currentState!.push(
        MaterialPageRoute(
          builder: (_) => PracticeScreen(appState: _appState!),
        ),
      );
      return;
    }
''',
    '''    if (kind.startsWith('practice_') && _openPractice != null) {
      _openPractice!();
      return;
    }
''',
    'push Practice route callback',
)
path.write_text(text, encoding='utf-8')

path = Path('source/lib/screens/home_screen.dart')
text = path.read_text(encoding='utf-8')
text = replace_once(
    text,
    '''          PushNotificationService.instance.navigationReady(
            isAdmin: appState.currentUser!.role == UserRole.admin,
            appState: appState,
          );
''',
    '''          PushNotificationService.instance.navigationReady(
            isAdmin: appState.currentUser!.role == UserRole.admin,
            onPractice: () {
              if (mounted) setState(() => _tab = 2);
            },
          );
''',
    'home Practice callback',
)
path.write_text(text, encoding='utf-8')

print('Final Practice QCM5 UX and push routing applied.')
