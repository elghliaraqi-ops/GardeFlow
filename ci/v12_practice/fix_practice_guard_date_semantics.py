from pathlib import Path

path = Path('source/lib/models/practice_models.dart')
text = path.read_text(encoding='utf-8')
old = """      case 'urg-nuit':
        // Convention du planning Urgences : la tuile Nuit porte la date
        // du matin de fin de garde. Ex. tuile 30/09 = 29/09 20h -> 30/09 08h.
        start = DateTime(day.year, day.month, day.day - 1, 20);
        end = DateTime(day.year, day.month, day.day, 8);
        break;
"""
new = """      case 'urg-nuit':
        // La date de la garde est toujours sa date de début.
        // Ex. Nuit du 29/09 = 29/09 20h -> 30/09 08h.
        start = DateTime(day.year, day.month, day.day, 20);
        end = DateTime(day.year, day.month, day.day + 1, 8);
        break;
"""
if new in text:
    print('Practice night semantics already correct.')
    raise SystemExit(0)
if text.count(old) != 1:
    raise SystemExit(f'Expected exactly one old night block, found {text.count(old)}')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
print('Updated Practice night guard semantics to start-date convention.')
