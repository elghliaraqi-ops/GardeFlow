from pathlib import Path

EXPECTED = "version: 11.6.37+197"
TARGET = "version: 11.6.38+198"

pubspec = Path("pubspec.yaml")
pub = pubspec.read_text()
if EXPECTED not in pub:
    raise SystemExit("V11.6.38: base version mismatch")
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
      total++;
      if (entry.shiftId.startsWith('urg')) {
        urgences++;
      } else {
        service++;
      }
    }
    return {'total': total, 'urgences': urgences, 'service': service};
  }"""
if old_method not in h:
    raise SystemExit("V11.6.38 dashboard count method missing")
h = h.replace(old_method, new_method, 1)
h = h.replace("final monthlyCount = _guardsThisMonth(me, now);", "final monthlyCounts = _guardsThisMonth(me, now);", 1)

old_pill = """                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.13),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.14),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.calendar_month_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 7),
                        Text(
                          '$monthlyCount garde${monthlyCount > 1 ? 's' : ''} ce mois-ci',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),"""
new_pill = """                  const Text(
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
                      for (final metric in [
                        ('Total', monthlyCounts['total'] ?? 0, Icons.calendar_month_rounded),
                        ('Urgences', monthlyCounts['urgences'] ?? 0, Icons.local_hospital_rounded),
                        ('Service', monthlyCounts['service'] ?? 0, Icons.medical_services_rounded),
                      ]) ...[
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 5),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.13),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white.withOpacity(0.14)),
                            ),
                            child: Column(
                              children: [
                                Icon(metric.$3, color: Colors.white, size: 16),
                                const SizedBox(height: 4),
                                Text(
                                  '${metric.$2}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontFamily: 'SpaceGrotesk',
                                    fontSize: 18,
                                    height: 1,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  metric.$1,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (metric.$1 != 'Service') const SizedBox(width: 7),
                      ],
                    ],
                  ),"""
if old_pill not in h:
    raise SystemExit("V11.6.38 dashboard pill missing")
h = h.replace(old_pill, new_pill, 1)

h = h.replace("  bool _showSenior = true;", "  bool _showSenior = false;", 1)
old_hub_top = """          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: _AstreinteModeSwitch(
              showSenior: _showSenior,
              onChanged: (senior) {
                if (senior == _showSenior) return;
                setState(() => _showSenior = senior);
              },
            ),
          ),"""
new_hub_top = """          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.line),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.navy.withOpacity(0.045),
                    blurRadius: 16,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Astreintes',
                    style: TextStyle(
                      fontFamily: 'SpaceGrotesk',
                      color: AppColors.ink,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _showSenior
                        ? 'Médecins séniors de garde et d’astreinte'
                        : 'Gardes et astreintes des médecins juniors',
                    style: const TextStyle(
                      color: AppColors.inkSoft,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _AstreinteModeSwitch(
                    showSenior: _showSenior,
                    onChanged: (senior) {
                      if (senior == _showSenior) return;
                      setState(() => _showSenior = senior);
                    },
                  ),
                ],
              ),
            ),
          ),"""
if old_hub_top not in h:
    raise SystemExit("V11.6.38 astreinte hub top missing")
h = h.replace(old_hub_top, new_hub_top, 1)
h = h.replace("      height: 50,", "      height: 58,", 1)

old_switch = """          Expanded(
            child: _AstreinteModeButton(
              label: 'Astreinte Senior',
              icon: Icons.photo_library_rounded,
              selected: showSenior,
              onTap: () => onChanged(true),
            ),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: _AstreinteModeButton(
              label: 'Astreinte Junior',
              icon: Icons.calendar_view_week_rounded,
              selected: !showSenior,
              onTap: () => onChanged(false),
            ),
          ),"""
new_switch = """          Expanded(
            child: _AstreinteModeButton(
              label: 'Astreintes Junior',
              icon: Icons.calendar_view_week_rounded,
              selected: !showSenior,
              onTap: () => onChanged(false),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _AstreinteModeButton(
              label: 'Astreintes Senior',
              icon: Icons.photo_library_rounded,
              selected: showSenior,
              onTap: () => onChanged(true),
            ),
          ),"""
if old_switch not in h:
    raise SystemExit("V11.6.38 astreinte switch missing")
h = h.replace(old_switch, new_switch, 1)
home.write_text(h)

junior = Path("lib/screens/junior_oncall_screen.dart")
j = junior.read_text()
j = j.replace(
    "padding: const EdgeInsets.fromLTRB(16, 0, 10, 2),",
    "padding: const EdgeInsets.fromLTRB(18, 12, 12, 8),",
    1,
)
j = j.replace(
    """        _WeekSelector(
          start: _weekStart,""",
    """        if (widget.embedded) const SizedBox(height: 6),
        _WeekSelector(
          start: _weekStart,""",
    1,
)
junior.write_text(j)

print("V11.6.38 part 1 applied")
