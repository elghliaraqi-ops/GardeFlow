from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected one old block, found {count}')
    return text.replace(old, new, 1)


model_path = Path('source/lib/models/practice_models.dart')
model = model_path.read_text(encoding='utf-8')
model = replace_once(
    model,
    "      case 'urg-nuit':\n        // Convention du planning Urgences : la tuile Nuit porte la date\n        // du matin de fin de garde. Ex. tuile 30/09 = 29/09 20h -> 30/09 08h.\n        start = DateTime(day.year, day.month, day.day - 1, 20);\n        end = DateTime(day.year, day.month, day.day, 8);\n        break;",
    "      case 'urg-nuit':\n        // La date du planning est toujours la date de début de garde.\n        // Ex. tuile 29/09 = 29/09 20h -> 30/09 08h.\n        start = DateTime(day.year, day.month, day.day, 20);\n        end = DateTime(day.year, day.month, day.day + 1, 8);\n        break;",
    'night guard semantics',
)
model_path.write_text(model, encoding='utf-8')


test_path = Path('source/test/practice_models_test.dart')
test = test_path.read_text(encoding='utf-8')
test = replace_once(
    test,
    "    test('detects tonight when the night tile is dated the next morning', () {\n      final guard = PracticeGuard.current(\n        entries: [entry('urg-nuit', '2026-09-30')],\n        user: user,\n        now: DateTime(2026, 9, 29, 23, 3),\n      );\n      expect(guard, isNotNull);\n      expect(guard!.periodLabel, 'Nuit');\n      expect(guard.start, DateTime(2026, 9, 29, 20));\n      expect(guard.end, DateTime(2026, 9, 30, 8));\n    });",
    "    test('night guard uses its planning date as the start date', () {\n      final guard = PracticeGuard.current(\n        entries: [entry('urg-nuit', '2026-09-29')],\n        user: user,\n        now: DateTime(2026, 9, 29, 23, 3),\n      );\n      expect(guard, isNotNull);\n      expect(guard!.periodLabel, 'Nuit');\n      expect(guard.start, DateTime(2026, 9, 29, 20));\n      expect(guard.end, DateTime(2026, 9, 30, 8));\n    });",
    'night start-date test',
)
test = replace_once(
    test,
    "        entries: [entry('urg-nuit', '2026-09-30')],\n        user: user,\n        now: DateTime(2026, 9, 30, 2, 30),",
    "        entries: [entry('urg-nuit', '2026-09-29')],\n        user: user,\n        now: DateTime(2026, 9, 30, 2, 30),",
    'after-midnight test entry date',
)
test = replace_once(
    test,
    "            'urg-nuit',\n            '2026-09-30',\n            isDisciplinary: true,",
    "            'urg-nuit',\n            '2026-09-29',\n            isDisciplinary: true,",
    'disciplinary night date',
)
test = replace_once(
    test,
    "      final night = entry('urg-nuit', '2026-09-30');\n      expect(\n        PracticeGuard.current(\n          entries: [night],\n          user: user,\n          now: DateTime(2026, 9, 29, 19, 59),",
    "      final night = entry('urg-nuit', '2026-09-29');\n      expect(\n        PracticeGuard.current(\n          entries: [night],\n          user: user,\n          now: DateTime(2026, 9, 29, 19, 59),",
    'night boundary test entry date',
)
anchor = "    test('ignores non emergency guards', () {"
extra = """    test('day guard on 29 runs from 08:00 to 20:00 on 29', () {\n      final guard = PracticeGuard.fromEntry(entry('urg-jour', '2026-09-29'));\n      expect(guard, isNotNull);\n      expect(guard!.start, DateTime(2026, 9, 29, 8));\n      expect(guard.end, DateTime(2026, 9, 29, 20));\n      expect(guard.isActiveAt(DateTime(2026, 9, 29, 12)), isTrue);\n      expect(guard.isActiveAt(DateTime(2026, 9, 29, 20)), isFalse);\n    });\n\n    test('24H guard on 29 runs from 29 08:00 to 30 08:00', () {\n      final guard = PracticeGuard.fromEntry(entry('urg-24h', '2026-09-29'));\n      expect(guard, isNotNull);\n      expect(guard!.start, DateTime(2026, 9, 29, 8));\n      expect(guard.end, DateTime(2026, 9, 30, 8));\n      expect(guard.isActiveAt(DateTime(2026, 9, 30, 7, 59)), isTrue);\n      expect(guard.isActiveAt(DateTime(2026, 9, 30, 8)), isFalse);\n    });\n\n"""
if extra not in test:
    if anchor not in test:
        raise SystemExit('guard-type test anchor not found')
    test = test.replace(anchor, extra + anchor, 1)
test_path.write_text(test, encoding='utf-8')


sql_path = Path('ci/v12_practice/practice_night_semantics.sql')
sql = sql_path.read_text(encoding='utf-8')
sql = replace_once(
    sql,
    "-- Practice hotfix: Urgences Nuit uses the roster tile date as the morning/end date.\n-- Example: planning tile 2026-09-30 means 2026-09-29 20:00 -> 2026-09-30 08:00.",
    "-- Practice guard-date semantics: the planning date is always the guard start date.\n-- Example: planning tile 2026-09-29 Nuit means 2026-09-29 20:00 -> 2026-09-30 08:00.",
    'SQL semantics comment',
)
sql = replace_once(
    sql,
    "      when 'urg-nuit' then rec.date_str::timestamp + interval '8 hours'",
    "      when 'urg-nuit' then rec.date_str::timestamp + interval '1 day 8 hours'",
    'SQL night guard end',
)
sql_path.write_text(sql, encoding='utf-8')
