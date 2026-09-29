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
    "  String get dateStr => entry.dateStr;\n",
    "  String get dateStr => entry.dateStr;\n  bool get isDisciplinary => entry.isDisciplinary;\n",
    'disciplinary getter',
)

model = replace_once(
    model,
    """      case 'urg-nuit':
        start = DateTime(day.year, day.month, day.day, 20);
        end = DateTime(day.year, day.month, day.day + 1, 8);
        break;
""",
    """      case 'urg-nuit':
        // Convention du planning Urgences : la tuile Nuit porte la date
        // du matin de fin de garde. Ex. tuile 30/09 = 29/09 20h -> 30/09 08h.
        start = DateTime(day.year, day.month, day.day - 1, 20);
        end = DateTime(day.year, day.month, day.day, 8);
        break;
""",
    'night guard interval',
)
model_path.write_text(model, encoding='utf-8')


test_path = Path('source/test/practice_models_test.dart')
test = test_path.read_text(encoding='utf-8')

test = replace_once(
    test,
    """    PlanningEntry entry(String shift, String date) => PlanningEntry(
          id: '$shift-$date',
          dateStr: date,
          shiftId: shift,
          ownerId: user.id,
          ownerPhone: user.phone,
          ownerName: user.fullName,
        );
""",
    """    PlanningEntry entry(
      String shift,
      String date, {
      bool isDisciplinary = false,
    }) => PlanningEntry(
          id: '$shift-$date${isDisciplinary ? '-disciplinary' : ''}',
          dateStr: date,
          shiftId: shift,
          ownerId: user.id,
          ownerPhone: user.phone,
          ownerName: user.fullName,
          isDisciplinary: isDisciplinary,
        );
""",
    'test entry helper',
)

test = replace_once(
    test,
    """    test('detects an overnight emergency night guard', () {
      final guard = PracticeGuard.current(
        entries: [entry('urg-nuit', '2026-09-29')],
        user: user,
        now: DateTime(2026, 9, 30, 2, 30),
      );
      expect(guard, isNotNull);
      expect(guard!.periodLabel, 'Nuit');
      expect(guard.start, DateTime(2026, 9, 29, 20));
      expect(guard.end, DateTime(2026, 9, 30, 8));
    });
""",
    """    test('detects tonight when the night tile is dated the next morning', () {
      final guard = PracticeGuard.current(
        entries: [entry('urg-nuit', '2026-09-30')],
        user: user,
        now: DateTime(2026, 9, 29, 23, 3),
      );
      expect(guard, isNotNull);
      expect(guard!.periodLabel, 'Nuit');
      expect(guard.start, DateTime(2026, 9, 29, 20));
      expect(guard.end, DateTime(2026, 9, 30, 8));
    });

    test('keeps the same night guard active after midnight until 08:00', () {
      final guard = PracticeGuard.current(
        entries: [entry('urg-nuit', '2026-09-30')],
        user: user,
        now: DateTime(2026, 9, 30, 2, 30),
      );
      expect(guard, isNotNull);
      expect(guard!.start, DateTime(2026, 9, 29, 20));
      expect(guard.end, DateTime(2026, 9, 30, 8));
    });

    test('includes disciplinary emergency guards in Practice', () {
      final guard = PracticeGuard.current(
        entries: [
          entry(
            'urg-nuit',
            '2026-09-30',
            isDisciplinary: true,
          ),
        ],
        user: user,
        now: DateTime(2026, 9, 29, 23, 3),
      );
      expect(guard, isNotNull);
      expect(guard!.isDisciplinary, isTrue);
    });

    test('night guard is inactive before 20:00 and from 08:00', () {
      final night = entry('urg-nuit', '2026-09-30');
      expect(
        PracticeGuard.current(
          entries: [night],
          user: user,
          now: DateTime(2026, 9, 29, 19, 59),
        ),
        isNull,
      );
      expect(
        PracticeGuard.current(
          entries: [night],
          user: user,
          now: DateTime(2026, 9, 30, 8),
        ),
        isNull,
      );
    });
""",
    'night and disciplinary tests',
)

test_path.write_text(test, encoding='utf-8')

print('Practice night/disciplinary hotfix applied.')
