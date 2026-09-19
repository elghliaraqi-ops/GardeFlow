from pathlib import Path

EXPECTED = "version: 11.6.48+208"
TARGET = "version: 11.6.49+209"

pubspec = Path("pubspec.yaml")
pub = pubspec.read_text()
if EXPECTED not in pub:
    raise SystemExit("V11.6.49: base version mismatch")
pubspec.write_text(pub.replace(EXPECTED, TARGET, 1))

junior = Path("lib/screens/junior_oncall_screen.dart")
s = junior.read_text()

old = """    for (final PlanningEntry entry in appState.planning) {
      if (!entry.shiftId.startsWith('service-')) continue;
      final date = DateTime.tryParse(entry.dateStr);
      if (date == null || date.isBefore(start) || !date.isBefore(endExclusive)) continue;
      if (!appState.isPlanningEntryApproved(entry)) continue;

      final user = usersById[entry.ownerId] ?? usersByPhone[entry.ownerPhone];
      if (user == null || user.grade != MedicalGrade.junior || user.accountStatus != AccountStatus.active) continue;

      result.add(_JuniorOnCallRow(
        dateStr: entry.dateStr,
        shiftId: entry.shiftId,
        ownerName: entry.ownerName,
        service: user.service,
        hospital: user.hospital,
      ));
    }"""
new = """    for (final PlanningEntry entry in appState.planning) {
      final isService = entry.shiftId.startsWith('service-');
      final isUrgences = entry.shiftId.startsWith('urg-');
      if (!isService && !isUrgences) continue;
      final date = DateTime.tryParse(entry.dateStr);
      if (date == null || date.isBefore(start) || !date.isBefore(endExclusive)) continue;

      // Les gardes de service restent limitées aux calendriers validés.
      // Les gardes aux urgences proviennent du planning officiel PDF :
      // elles doivent être visibles dès leur import, même avant la validation
      // individuelle/automatique du mois.
      if (isService && !appState.isPlanningEntryApproved(entry)) continue;

      final user = usersById[entry.ownerId] ?? usersByPhone[entry.ownerPhone];
      if (user == null || user.grade != MedicalGrade.junior || user.accountStatus != AccountStatus.active) continue;

      result.add(_JuniorOnCallRow(
        dateStr: entry.dateStr,
        shiftId: entry.shiftId,
        ownerName: entry.ownerName,
        service: isUrgences ? 'Urgences' : user.service,
        hospital: user.hospital,
      ));
    }"""
if old not in s:
    raise SystemExit("V11.6.49: local junior roster anchor missing")
s = s.replace(old, new, 1)

old = """  static int _shiftRank(String shiftId) {
    switch (shiftId) {
      case 'service-jour':
        return 0;
      case 'service-24h':
        return 1;
      case 'service-nuit':
        return 2;
      default:
        return 99;
    }
  }"""
new = """  static int _shiftRank(String shiftId) {
    switch (shiftId) {
      case 'urg-jour':
        return 0;
      case 'urg-24h':
        return 1;
      case 'urg-nuit':
        return 2;
      case 'service-jour':
        return 3;
      case 'service-24h':
        return 4;
      case 'service-nuit':
        return 5;
      default:
        return 99;
    }
  }"""
if old not in s:
    raise SystemExit("V11.6.49: shift rank anchor missing")
s = s.replace(old, new, 1)

s = s.replace(
    "Aucune astreinte Junior validée $day",
    "Aucune garde ou astreinte Junior $day",
    1,
)

old = """  String _timeLabel(ShiftType shift) {
    String compact(String? value) => (value ?? '').replaceAll(':00', 'h');
    if (shift.id == 'service-24h') return '08h - 08h';
    return '${compact(shift.start)} - ${compact(shift.end)}';
  }"""
new = """  String _timeLabel(ShiftType shift) {
    String compact(String? value) => (value ?? '').replaceAll(':00', 'h');
    if (shift.id.endsWith('-24h')) return '08h - 08h';
    return '${compact(shift.start)} - ${compact(shift.end)}';
  }"""
if old not in s:
    raise SystemExit("V11.6.49: duty time label anchor missing")
s = s.replace(old, new, 1)

old = """  Widget build(BuildContext context) {
    final total = group.rows.length;
    return Container("""
new = """  Widget build(BuildContext context) {
    final total = group.rows.length;
    final isUrgences = group.service == 'Urgences';
    return Container("""
if old not in s:
    raise SystemExit("V11.6.49: service card build anchor missing")
s = s.replace(old, new, 1)

old = """            decoration: const BoxDecoration(
              color: AppColors.brandSoft,
              borderRadius: BorderRadius.vertical(top: Radius.circular(17)),
            ),"""
new = """            decoration: BoxDecoration(
              color: isUrgences ? AppColors.urgJour : AppColors.brandSoft,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
            ),"""
if old not in s:
    raise SystemExit("V11.6.49: service card header decoration missing")
s = s.replace(old, new, 1)

old = """                const Icon(
                  Icons.medical_services_rounded,
                  size: 19,
                  color: AppColors.brand,
                ),"""
new = """                Icon(
                  isUrgences ? Icons.emergency_rounded : Icons.medical_services_rounded,
                  size: 19,
                  color: isUrgences ? AppColors.urgJourText : AppColors.brand,
                ),"""
if old not in s:
    raise SystemExit("V11.6.49: service card icon anchor missing")
s = s.replace(old, new, 1)

old = """                    style: const TextStyle(
                      color: AppColors.brandDark,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),"""
new = """                    style: TextStyle(
                      color: isUrgences ? AppColors.urgJourText : AppColors.brandDark,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),"""
if old not in s:
    raise SystemExit("V11.6.49: service card title style missing")
s = s.replace(old, new, 1)

old = """                  style: const TextStyle(
                    color: AppColors.brand,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),"""
new = """                  style: TextStyle(
                    color: isUrgences ? AppColors.urgJourText : AppColors.brand,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),"""
if old not in s:
    raise SystemExit("V11.6.49: service card count style missing")
s = s.replace(old, new, 1)

old = """                Text('Junior', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft)),"""
new = """                Text(
                  row.shiftId.startsWith('urg-') ? 'Junior · Urgences' : 'Junior',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft),
                ),"""
if old not in s:
    raise SystemExit("V11.6.49: junior subtitle anchor missing")
s = s.replace(old, new, 1)

old = """  final services = map.keys.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));"""
new = """  final services = map.keys.toList()
    ..sort((a, b) {
      if (a == 'Urgences' && b != 'Urgences') return -1;
      if (b == 'Urgences' && a != 'Urgences') return 1;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });"""
if old not in s:
    raise SystemExit("V11.6.49: service group sort anchor missing")
s = s.replace(old, new, 1)

junior.write_text(s)

source_sql = Path(__file__).resolve().parent / "junior_oncall_urgences.sql"
if not source_sql.exists():
    raise SystemExit("V11.6.49: Supabase migration source missing")
target_sql = Path("supabase/patch_v11_6_49_junior_oncall_urgences.sql")
target_sql.write_text(source_sql.read_text())

checks = {
    "lib/screens/junior_oncall_screen.dart": [
        "isUrgences ? 'Urgences' : user.service",
        "urg-24h",
        "Junior · Urgences",
        "Aucune garde ou astreinte Junior",
    ],
    "supabase/patch_v11_6_49_junior_oncall_urgences.sql": [
        "urg-jour",
        "official_emergency",
        "when pe.shift_id like 'urg-%' then 'Urgences'",
    ],
}
for file_name, needles in checks.items():
    text = Path(file_name).read_text()
    for needle in needles:
        if needle not in text:
            raise SystemExit(f"V11.6.49: missing {needle!r} in {file_name}")

print("GardeFlow V11.6.49: Astreinte Junior now also shows official emergency-duty juniors")
