from pathlib import Path
import re

path = Path('source/lib/screens/home_screen.dart')
text = path.read_text(encoding='utf-8')

old = """                    PracticeHomeSummary(appState: appState, user: me),
                    SizedBox(height: 12),
                    Row(
"""
new = """                    SizedBox(height: 12),
                    Row(
"""
if old not in text:
    raise SystemExit('Bloc Practice dans le hero introuvable')
text = text.replace(old, new, 1)

old_date = """                            'On est le $dateLabel, il est $timeLabel',
"""
new_date = """                            '$dateLabel · $timeLabel',
"""
if old_date not in text:
    raise SystemExit('Texte date heure introuvable')
text = text.replace(old_date, new_date, 1)

pattern = re.compile(r"""                    SizedBox\(height: 17\),\n                    Container\(\n.*?_MonthlyGuardChip\(\n                                label: 'Service',\n                                value: serviceMonthlyCount,\n                              \),\n                            \],\n                          \),\n                        \],\n                      \),\n                    \),\n""", re.S)
replacement = """                    SizedBox(height: 14),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.13),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withOpacity(0.14)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_month_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                          SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              '$monthlyCount garde${monthlyCount > 1 ? 's' : ''} ce mois',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              'Urg. $urgenceMonthlyCount · Serv. $serviceMonthlyCount',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.90),
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
"""
text, count = pattern.subn(replacement, text, count=1)
if count != 1:
    raise SystemExit(f'Bloc statistiques mensuelles remplacé {count} fois')

old_after = """          ),
          SizedBox(height: 24),
          Text(
            'Prochaine garde à venir',
"""
new_after = """          ),
          PracticeHomeSummary(appState: appState, user: me),
          SizedBox(height: 20),
          Text(
            'Prochaine garde à venir',
"""
if old_after not in text:
    raise SystemExit('Point insertion Practice hors hero introuvable')
text = text.replace(old_after, new_after, 1)

path.write_text(text, encoding='utf-8')
print('home_screen.dart simplifié avec succès')
