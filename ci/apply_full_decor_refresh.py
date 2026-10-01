from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCREENS = ROOT / 'source' / 'lib' / 'screens'

SCENES = {
    'admin_disciplinary_assignment_screen.dart': 'admin',
    'admin_password_reset_screen.dart': 'admin',
    'admin_screen.dart': 'admin',
    'announcements_screen.dart': 'announcements',
    'application_settings_screen.dart': 'settings',
    'astreinte_screen.dart': 'onCall',
    'audit_screen.dart': 'audit',
    'auth_screen.dart': 'auth',
    'directory_screen.dart': 'directory',
    'forgot_password_screen.dart': 'auth',
    'home_screen.dart': 'home',
    'junior_oncall_screen.dart': 'onCall',
    'notifications_screen.dart': 'notifications',
    'official_planning_screen.dart': 'planning',
    'practice_qcm_screen.dart': 'practice',
    'practice_screen.dart': 'practice',
    'profile_screen.dart': 'profile',
    'senior_oncall_screen.dart': 'onCall',
    'senior_roster_review_screen.dart': 'onCall',
    'settings_screen.dart': 'settings',
    'splash_screen.dart': 'splash',
}


def add_import(text: str) -> str:
    marker = "import '../theme/screen_decor.dart';"
    if marker in text:
        return text
    lines = text.splitlines(keepends=True)
    import_indexes = [i for i, line in enumerate(lines) if line.startswith('import ')]
    if not import_indexes:
        raise RuntimeError('No import block found')
    idx = import_indexes[-1] + 1
    lines.insert(idx, marker + '\n')
    return ''.join(lines)


print('=== FULL-SCREEN DECOR COVERAGE ===')
missing = []
for filename, scene in SCENES.items():
    path = SCREENS / filename
    text = path.read_text(encoding='utf-8')
    count = text.count('Scaffold(')
    if count == 0:
        missing.append(filename)
        print(f'NO_SCAFFOLD {filename}')
        continue
    text = add_import(text)
    text = text.replace('Scaffold(', f'DecorScaffold(scene: ScreenDecorScene.{scene}, ')
    path.write_text(text, encoding='utf-8')
    print(f'OK {filename}: {count} scaffold(s) -> {scene}')

# Sections embedded in the home feed get their own illustrated banners.
clinical = SCREENS / 'clinical_cases_section.dart'
text = add_import(clinical.read_text(encoding='utf-8'))
start_marker = "          Container(\n            width: double.infinity,\n            padding: const EdgeInsets.fromLTRB(15, 15, 11, 15),"
end_marker = "          const SizedBox(height: 12),"
start = text.find(start_marker)
end = text.find(end_marker, start)
if start < 0 or end < 0:
    raise RuntimeError('Clinical cases banner markers not found')
clinical_banner = """          DecorSectionBanner(\n            scene: ScreenDecorScene.practice,\n            title: 'CAS CLINIQUES',\n            subtitle: 'Dossiers anonymisés · raisonnement clinique · 5 QCM par cas',\n            icon: Icons.medical_information_rounded,\n            trailing: DecorIconAction(\n              icon: Icons.refresh_rounded,\n              tooltip: 'Actualiser',\n              onTap: _loading ? null : () => _load(reset: true),\n            ),\n          ),\n"""
text = text[:start] + clinical_banner + text[end:]
clinical.write_text(text, encoding='utf-8')
print('OK clinical_cases_section.dart: illustrated Practice banner')

news = SCREENS / 'daily_news_section.dart'
text = add_import(news.read_text(encoding='utf-8'))
start_marker = "            Row(\n              children: [\n                Container(\n                  width: 39,"
end_marker = "            const SizedBox(height: 13),"
start = text.find(start_marker)
end = text.find(end_marker, start)
if start < 0 or end < 0:
    raise RuntimeError('Daily news banner markers not found')
news_banner = """            DecorSectionBanner(\n              scene: ScreenDecorScene.news,\n              title: 'ACTUALITÉS DU JOUR',\n              subtitle: 'La vie des hôpitaux, de l’UM6SS et de l’AMI UM6',\n              icon: Icons.newspaper_rounded,\n              trailing: Row(\n                mainAxisSize: MainAxisSize.min,\n                children: [\n                  if (_isAdmin) ...[\n                    DecorIconAction(\n                      icon: Icons.add_rounded,\n                      tooltip: 'Publier une actualité',\n                      onTap: _showPublishSheet,\n                    ),\n                    const SizedBox(width: 6),\n                  ],\n                  if (_refreshing)\n                    const SizedBox(\n                      width: 40,\n                      height: 40,\n                      child: Center(\n                        child: SizedBox(\n                          width: 19,\n                          height: 19,\n                          child: CircularProgressIndicator(\n                            strokeWidth: 2.2,\n                            color: Colors.white,\n                          ),\n                        ),\n                      ),\n                    )\n                  else\n                    DecorIconAction(\n                      icon: Icons.refresh_rounded,\n                      tooltip: 'Actualiser les actualités',\n                      onTap: snapshot.connectionState == ConnectionState.waiting\n                          ? null\n                          : _reload,\n                    ),\n                ],\n              ),\n            ),\n"""
text = text[:start] + news_banner + text[end:]
news.write_text(text, encoding='utf-8')
print('OK daily_news_section.dart: illustrated News banner')

sheet = SCREENS / 'exchange_request_sheet.dart'
text = add_import(sheet.read_text(encoding='utf-8'))
old = "            Text('Transfert / échange de garde', style: Theme.of(context).textTheme.displaySmall),"
new = """            const DecorSheetLead(\n              scene: ScreenDecorScene.planning,\n              title: 'Transfert / échange de garde',\n              subtitle: 'Organisez votre remplacement dans un cadre clair et sécurisé',\n              icon: Icons.swap_horiz_rounded,\n            ),"""
if old not in text:
    raise RuntimeError('Exchange sheet lead marker not found')
text = text.replace(old, new, 1)
sheet.write_text(text, encoding='utf-8')
print('OK exchange_request_sheet.dart: decorative Planning lead')

# Remove the only intentionally unused import left from the initial shared file draft.
decor = ROOT / 'source' / 'lib' / 'theme' / 'screen_decor.dart'
decor_text = decor.read_text(encoding='utf-8').replace("import 'dart:math' as math;\n\n", '')
decor.write_text(decor_text, encoding='utf-8')

if missing:
    print('WARNING full-screen files without Scaffold:', ', '.join(missing))
print('=== DECOR PATCH COMPLETE ===')
