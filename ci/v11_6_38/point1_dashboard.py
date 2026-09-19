from pathlib import Path

EXPECTED = "version: 11.6.37+197"
TARGET = "version: 11.6.38+198"

pubspec = Path("pubspec.yaml")
pub = pubspec.read_text()
if EXPECTED not in pub:
    raise SystemExit("V11.6.38 point 1: base version mismatch")
pubspec.write_text(pub.replace(EXPECTED, TARGET, 1))

home = Path("lib/screens/home_screen.dart")
h = home.read_text()

old_method = """  int _guardsThisMonth(AppUser me, DateTime now) {
    return appState.planning.where((entry) {
      if (entry.ownerId != me.id && entry.ownerPhone != me.phone) return false;
      if (entry.shiftId == 'conge') return false;
      final date = DateTime.tryParse(entry.dateStr);
      if (date == null) return false;
      return date.year == now.year && date.month == now.month;
    }).length;
  }"""

new_method = """  Map<String, int> _guardsThisMonth(AppUser me, DateTime now) {
    var total = 0;
    var urgences = 0;
    var service = 0;

    for (final entry in appState.planning) {
      if (entry.ownerId != me.id && entry.ownerPhone != me.phone) continue;
      if (entry.shiftId == 'conge') continue;
      final date = DateTime.tryParse(entry.dateStr);
      if (date == null || date.year != now.year || date.month != now.month) continue;
      total += 1;
      if (entry.shiftId.startsWith('urg')) {
        urgences += 1;
      } else {
        service += 1;
      }
    }

    return {'total': total, 'urgences': urgences, 'service': service};
  }"""

if old_method not in h:
    raise SystemExit("V11.6.38 point 1: monthly guard method not found")
h = h.replace(old_method, new_method, 1)

old_count = "    final monthlyCount = _guardsThisMonth(me, now);"
new_count = "    final monthlyCounts = _guardsThisMonth(me, now);"
if old_count not in h:
    raise SystemExit("V11.6.38 point 1: monthly count assignment not found")
h = h.replace(old_count, new_count, 1)

# Replace only the old monthly-count Container.
needle = "'$monthlyCount garde"
pos = h.find(needle)
if pos < 0:
    raise SystemExit("V11.6.38 point 1: old monthly count text not found")
start = h.rfind("                  Container(", 0, pos)
if start < 0:
    raise SystemExit("V11.6.38 point 1: old monthly container start not found")
paren = h.find('(', start)
depth = 0
end = None
in_single = False
in_double = False
escape = False
for i in range(paren, len(h)):
    ch = h[i]
    if escape:
        escape = False
        continue
    if ch == '\\':
        escape = True
        continue
    if ch == "'" and not in_double:
        in_single = not in_single
        continue
    if ch == '"' and not in_single:
        in_double = not in_double
        continue
    if in_single or in_double:
        continue
    if ch == '(':
        depth += 1
    elif ch == ')':
        depth -= 1
        if depth == 0:
            end = i + 1
            if end < len(h) and h[end] == ',':
                end += 1
            break
if end is None:
    raise SystemExit("V11.6.38 point 1: old monthly container end not found")

new_widget = """                  const Text(
                    'Gardes ce mois-ci',
                    style: TextStyle(
                      color: Color(0xFFDDEFE6),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _MonthlyGuardMetric(label: 'Total', value: monthlyCounts['total'] ?? 0, icon: Icons.calendar_month_rounded)),
                      const SizedBox(width: 7),
                      Expanded(child: _MonthlyGuardMetric(label: 'Urgences', value: monthlyCounts['urgences'] ?? 0, icon: Icons.emergency_rounded)),
                      const SizedBox(width: 7),
                      Expanded(child: _MonthlyGuardMetric(label: 'Service', value: monthlyCounts['service'] ?? 0, icon: Icons.medical_services_rounded)),
                    ],
                  ),"""
h = h[:start] + new_widget + h[end:]

insert_before = "class _NextGuardCard extends StatelessWidget {"
metric_class = r"""class _MonthlyGuardMetric extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;

  const _MonthlyGuardMetric({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.13),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.14)),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(height: 4),
          Text(
            '$value',
            style: const TextStyle(color: Colors.white, fontFamily: 'SpaceGrotesk', fontSize: 18, height: 1, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 3),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

"""
if insert_before not in h:
    raise SystemExit("V11.6.38 point 1: next guard anchor not found")
h = h.replace(insert_before, metric_class + insert_before, 1)
home.write_text(h)
print("V11.6.38 point 1: dashboard guard counters applied")