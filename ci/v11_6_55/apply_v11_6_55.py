from pathlib import Path

EXPECTED = "version: 11.6.54+214"
TARGET = "version: 11.6.55+215"

pubspec = Path("pubspec.yaml")
pub = pubspec.read_text()
if EXPECTED not in pub:
    raise SystemExit("V11.6.55: base version mismatch")
pubspec.write_text(pub.replace(EXPECTED, TARGET, 1))

screen = Path("lib/screens/official_planning_screen.dart")
s = screen.read_text()

s = s.replace(
"""  final Map<String, int> _myGuardCounts = <String, int>{};
  final Map<String, int> _myDisciplinaryCounts = <String, int>{};
  final Set<String> _guardCountLoading = <String>{};""",
"""  final Map<String, int> _myGuardCounts = <String, int>{};
  final Map<String, int> _myDisciplinaryCounts = <String, int>{};
  final Map<String, bool> _myCanResync = <String, bool>{};
  final Set<String> _guardCountLoading = <String>{};""",
1)

old_summary = """      final serverDisciplinaryCount =
          (summary['disciplinary'] as num?)?.toInt() ?? 0;
      final disciplinaryCount =
          parsedDisciplinaryCount > serverDisciplinaryCount
              ? parsedDisciplinaryCount
              : serverDisciplinaryCount;

      if (mounted) {
        setState(() {
          _myGuardCounts[slot.id] = count;
          _myDisciplinaryCounts[slot.id] = disciplinaryCount;
        });
      }"""
new_summary = """      final serverDisciplinaryCount =
          (summary['disciplinary'] as num?)?.toInt() ?? 0;
      final disciplinaryCount =
          parsedDisciplinaryCount > serverDisciplinaryCount
              ? parsedDisciplinaryCount
              : serverDisciplinaryCount;
      final canResync = summary['can_resync'] as bool? ?? false;

      if (mounted) {
        setState(() {
          _myGuardCounts[slot.id] = count;
          _myDisciplinaryCounts[slot.id] = disciplinaryCount;
          _myCanResync[slot.id] = canResync;
        });
      }"""
if old_summary not in s:
    raise SystemExit("V11.6.55: summary state anchor missing")
s=s.replace(old_summary,new_summary,1)

old_resync_start = """    setState(() => _busySlot = slot.id);
    try {
      final appState = context.read<AppState>();
      await appState.forceSyncMyOfficialRoster();"""
new_resync_start = """    setState(() => _busySlot = slot.id);
    try {
      final summary =
          await _backend.officialRosterMySummary(resource: resource);
      final canResync = summary['can_resync'] as bool? ?? false;
      if (!canResync) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Calendrier validé définitivement : la superposition ne peut plus être refaite.',
            ),
          ),
        );
        return;
      }

      final appState = context.read<AppState>();
      await appState.forceSyncMyOfficialRoster();"""
if old_resync_start not in s:
    raise SystemExit("V11.6.55: resync guard anchor missing")
s=s.replace(old_resync_start,new_resync_start,1)

old_card_args = """                          myDisciplinaryCount: currentUser?.hospital == _slots[i].hospital ? _myDisciplinaryCounts[_slots[i].id] : null,
                          guardCountLoading: currentUser?.hospital == _slots[i].hospital && _guardCountLoading.contains(_slots[i].id),
                          isMyHospital: currentUser?.hospital == _slots[i].hospital,
                          onOpen: (r) => _open(r),
                          onResync: (r) => _resyncMyRoster(_slots[i], r),"""
new_card_args = """                          myDisciplinaryCount: currentUser?.hospital == _slots[i].hospital ? _myDisciplinaryCounts[_slots[i].id] : null,
                          canResync: currentUser?.hospital == _slots[i].hospital ? (_myCanResync[_slots[i].id] ?? false) : false,
                          guardCountLoading: currentUser?.hospital == _slots[i].hospital && _guardCountLoading.contains(_slots[i].id),
                          isMyHospital: currentUser?.hospital == _slots[i].hospital,
                          onOpen: (r) => _open(r),
                          onResync: (r) => _resyncMyRoster(_slots[i], r),"""
if old_card_args not in s:
    raise SystemExit("V11.6.55: card args anchor missing")
s=s.replace(old_card_args,new_card_args,1)

s=s.replace(
"""  final int? myDisciplinaryCount;
  final bool guardCountLoading;
  final bool isMyHospital;""",
"""  final int? myDisciplinaryCount;
  final bool canResync;
  final bool guardCountLoading;
  final bool isMyHospital;""",
1)

s=s.replace(
"""    required this.myDisciplinaryCount,
    required this.guardCountLoading,
    required this.isMyHospital,""",
"""    required this.myDisciplinaryCount,
    required this.canResync,
    required this.guardCountLoading,
    required this.isMyHospital,""",
1)

s=s.replace(
"""              if (r != null && isMyHospital)
                OutlinedButton.icon(""",
"""              if (r != null && isMyHospital && canResync)
                OutlinedButton.icon(""",
1)

screen.write_text(s)

source_sql = Path(__file__).resolve().parent / "resync_validation_lock.sql"
if not source_sql.exists():
    raise SystemExit("V11.6.55: SQL migration source missing")
target_sql = Path("supabase/patch_v11_6_55_resync_validation_lock.sql")
target_sql.write_text(source_sql.read_text())

checks = {
    "lib/screens/official_planning_screen.dart": [
        "_myCanResync",
        "summary['can_resync']",
        "isMyHospital && canResync",
        "Calendrier validé définitivement : la superposition ne peut plus être refaite.",
    ],
    "supabase/patch_v11_6_55_resync_validation_lock.sql": [
        "official_roster_resource_main_month",
        "'can_resync'",
        "la superposition ne peut plus être refaite",
    ],
}
for file_name, needles in checks.items():
    text = Path(file_name).read_text()
    for needle in needles:
        if needle not in text:
            raise SystemExit(f"V11.6.55: missing {needle!r} in {file_name}")

print("GardeFlow V11.6.55: re-overlay allowed only before definitive month validation")
