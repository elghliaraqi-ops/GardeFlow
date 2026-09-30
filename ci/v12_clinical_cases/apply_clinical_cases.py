from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one match, found {count}')
    return text.replace(old, new, 1)


def matching_paren(text: str, open_index: int) -> int:
    depth = 0
    quote = None
    escaped = False
    for i in range(open_index, len(text)):
        ch = text[i]
        if quote is not None:
            if escaped:
                escaped = False
                continue
            if ch == '\\':
                escaped = True
                continue
            if ch == quote:
                quote = None
            continue
        if ch in ("'", '"'):
            quote = ch
            continue
        if ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
            if depth == 0:
                return i
    raise SystemExit('Unbalanced parentheses while locating Actualités CTA')


home_path = Path('source/lib/screens/home_screen.dart')
home = home_path.read_text(encoding='utf-8')

home = replace_once(
    home,
    "import 'daily_news_section.dart';",
    "import 'daily_news_section.dart';\nimport 'clinical_cases_section.dart';",
    'home import',
)
home = replace_once(
    home,
    '  final GlobalKey _newsFeedKey = GlobalKey();',
    '  final GlobalKey _newsFeedKey = GlobalKey();\n  final GlobalKey _clinicalCasesFeedKey = GlobalKey();',
    'home state key',
)
home = replace_once(
    home,
    '                    newsFeedKey: _newsFeedKey,',
    '                    newsFeedKey: _newsFeedKey,\n                    clinicalCasesFeedKey: _clinicalCasesFeedKey,',
    'dashboard call key',
)
home = replace_once(
    home,
    '  final GlobalKey newsFeedKey;\n  final VoidCallback onOpenPlanning;',
    '  final GlobalKey newsFeedKey;\n  final GlobalKey clinicalCasesFeedKey;\n  final VoidCallback onOpenPlanning;',
    'dashboard field',
)
home = replace_once(
    home,
    '    required this.newsFeedKey,\n    required this.onOpenPlanning,',
    '    required this.newsFeedKey,\n    required this.clinicalCasesFeedKey,\n    required this.onOpenPlanning,',
    'dashboard constructor',
)
home = replace_once(
    home,
    '        DailyNewsSection(verticalFeedKey: newsFeedKey),',
    '        DailyNewsSection(verticalFeedKey: newsFeedKey),\n        SizedBox(height: 18),\n        ClinicalCasesSection(verticalFeedKey: clinicalCasesFeedKey),',
    'clinical feed bottom placement',
)

# Turn the existing "Actualités plus bas" pill into a two-button Wrap by
# cloning its exact Material widget. This keeps the new CTA visually identical
# without relying on brittle hand-copied styling.
label_index = home.find("'Actualités plus bas'")
if label_index < 0:
    raise SystemExit('Actualités CTA label not found')
material_index = home.rfind('Material(', 0, label_index)
if material_index < 0:
    raise SystemExit('Actualités CTA Material widget not found')
open_index = material_index + len('Material')
close_index = matching_paren(home, open_index)
actualites_material = home[material_index:close_index + 1]
if 'newsFeedKey.currentContext' not in actualites_material:
    raise SystemExit('Located Material is not the Actualités scroll CTA')
clinical_material = actualites_material.replace(
    'newsFeedKey.currentContext',
    'clinicalCasesFeedKey.currentContext',
).replace(
    "'Actualités plus bas'",
    "'Cas cliniques plus bas'",
).replace(
    'Icons.newspaper_rounded',
    'Icons.clinical_notes_rounded',
)
wrapped = (
    'Wrap(\n'
    '              spacing: 8,\n'
    '              runSpacing: 8,\n'
    '              alignment: WrapAlignment.center,\n'
    '              children: [\n'
    f'                {actualites_material},\n'
    f'                {clinical_material},\n'
    '              ],\n'
    '            )'
)
home = home[:material_index] + wrapped + home[close_index + 1:]
home_path.write_text(home, encoding='utf-8')

practice_path = Path('source/lib/services/practice_service.dart')
practice = practice_path.read_text(encoding='utf-8')
practice = replace_once(
    practice,
    "import 'supabase_backend_service.dart';",
    "import 'supabase_backend_service.dart';\nimport 'clinical_case_service.dart';",
    'practice service import',
)
practice = replace_once(
    practice,
    "    return PracticeCase.fromMap(Map<String, dynamic>.from(response as Map));",
    "    final saved = PracticeCase.fromMap(Map<String, dynamic>.from(response as Map));\n"
    "    final savedId = saved.id?.trim() ?? '';\n"
    "    if (savedId.isNotEmpty) {\n"
    "      ClinicalCaseService.instance.notifyChanged();\n"
    "      unawaited(ClinicalCaseService.instance.enrichQcmForPracticeCase(savedId));\n"
    "    }\n"
    "    return saved;",
    'practice remote save hook',
)
practice = replace_once(
    practice,
    "    await _removePending(value.clientId);\n    _notify();\n  }\n\n  Future<int> syncPending() async {",
    "    await _removePending(value.clientId);\n"
    "    ClinicalCaseService.instance.notifyChanged();\n"
    "    _notify();\n"
    "  }\n\n"
    "  Future<int> syncPending() async {",
    'practice delete refresh',
)
practice = replace_once(
    practice,
    "        if (existing != null) {\n          await _removePending(item.clientId);\n          synced++;\n          continue;\n        }",
    "        if (existing != null) {\n"
    "          final existingId = '${existing['id'] ?? ''}'.trim();\n"
    "          await _removePending(item.clientId);\n"
    "          ClinicalCaseService.instance.notifyChanged();\n"
    "          if (existingId.isNotEmpty) {\n"
    "            unawaited(ClinicalCaseService.instance.enrichQcmForPracticeCase(existingId));\n"
    "          }\n"
    "          synced++;\n"
    "          continue;\n"
    "        }",
    'practice pending existing hook',
)
practice = replace_once(
    practice,
    "        await _backend.client.from('practice_cases').insert(payload);\n        await _removePending(item.clientId);\n        synced++;",
    "        final inserted = await _backend.client\n"
    "            .from('practice_cases')\n"
    "            .insert(payload)\n"
    "            .select('id')\n"
    "            .single();\n"
    "        final insertedId = '${inserted['id'] ?? ''}'.trim();\n"
    "        await _removePending(item.clientId);\n"
    "        ClinicalCaseService.instance.notifyChanged();\n"
    "        if (insertedId.isNotEmpty) {\n"
    "          unawaited(ClinicalCaseService.instance.enrichQcmForPracticeCase(insertedId));\n"
    "        }\n"
    "        synced++;",
    'practice pending insert hook',
)
practice_path.write_text(practice, encoding='utf-8')

print('Clinical cases integration patch applied successfully.')
