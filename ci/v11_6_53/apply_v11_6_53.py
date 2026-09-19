from pathlib import Path

EXPECTED = "version: 11.6.52+212"
TARGET = "version: 11.6.53+213"

pubspec = Path("pubspec.yaml")
pub = pubspec.read_text()
if EXPECTED not in pub:
    raise SystemExit("V11.6.53: base version mismatch")
pubspec.write_text(pub.replace(EXPECTED, TARGET, 1))

backend = Path("lib/services/supabase_backend_service.dart")
b = backend.read_text()

anchor = """  Future<bool> officialRosterProfileSyncIsCurrent({"""
if anchor not in b:
    raise SystemExit("V11.6.53: backend profile sync anchor missing")

methods = r"""  Future<void> resetMyOfficialRosterProfileSync({
    required SharedResource resource,
  }) async {
    await client.rpc(
      'reset_my_official_roster_profile_sync',
      params: {
        'p_resource_id': resource.id,
        'p_resource_updated_at': resource.updatedAt.toUtc().toIso8601String(),
      },
    );
  }

  Future<Map<String, dynamic>> applyCurrentDisciplinaryRulesForMe() async {
    final result = await client.rpc('apply_current_disciplinary_rules_for_me');
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> officialRosterMySummary({
    required SharedResource resource,
  }) async {
    final result = await client.rpc(
      'official_roster_my_summary',
      params: {
        'p_resource_id': resource.id,
        'p_resource_updated_at': resource.updatedAt.toUtc().toIso8601String(),
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

"""
b = b.replace(anchor, methods + anchor, 1)
backend.write_text(b)

state = Path("lib/state/app_state.dart")
a = state.read_text()

old_result = """    final result = await backend.importOfficialEmergencyRosterForProfile(
      resource: resource,
      profileId: profile.id,
      assignments: myAssignments,
      unmatchedCells: parsed.unmatchedCells,
    );
    final inserted = (result['inserted'] as num?)?.toInt() ?? 0;"""

new_result = """    final result = await backend.importOfficialEmergencyRosterForProfile(
      resource: resource,
      profileId: profile.id,
      assignments: myAssignments,
      unmatchedCells: parsed.unmatchedCells,
    );

    await backend.applyCurrentDisciplinaryRulesForMe();

    final inserted = (result['inserted'] as num?)?.toInt() ?? 0;"""

if old_result not in a:
    raise SystemExit("V11.6.53: personal import result anchor missing")
a = a.replace(old_result, new_result, 1)

public_anchor = """  Future<void> _syncMyOfficialRosterIfNeeded() async {"""
if public_anchor not in a:
    raise SystemExit("V11.6.53: app state sync anchor missing")

force_method = r"""  Future<void> forceSyncMyOfficialRoster() async {
    final me = currentUser;
    if (!backendEnabled || me == null || me.accountStatus != AccountStatus.active) {
      return;
    }

    final slot = _officialPlanningSlotForHospital(me.hospital);
    if (slot == null) {
      throw StateError('Aucun planning officiel configuré pour votre établissement.');
    }

    final backend = SupabaseBackendService.instance;
    final resources = await backend.fetchOfficialPlanningPdfs();
    final resource = resources.where((r) => r.slot == slot).firstOrNull;
    if (resource == null) {
      throw StateError('Aucun PDF officiel publié pour votre établissement.');
    }

    await backend.resetMyOfficialRosterProfileSync(resource: resource);
    await _syncOfficialRosterForProfile(me);
    await backend.applyCurrentDisciplinaryRulesForMe();
    await _reloadFromBackend();
  }

"""
a = a.replace(public_anchor, force_method + public_anchor, 1)

sync_old = """      final changed = await _syncOfficialRosterForProfile(me);
      if (changed) await _reloadFromBackend();"""
sync_new = """      final changed = await _syncOfficialRosterForProfile(me);
      final disciplinary = await SupabaseBackendService.instance.applyCurrentDisciplinaryRulesForMe();
      final disciplinaryChanged =
          ((disciplinary['inserted'] as num?)?.toInt() ?? 0) > 0 ||
          ((disciplinary['updated'] as num?)?.toInt() ?? 0) > 0;
      if (changed || disciplinaryChanged) await _reloadFromBackend();"""
if sync_old not in a:
    raise SystemExit("V11.6.53: automatic disciplinary refresh anchor missing")
a = a.replace(sync_old, sync_new, 1)

state.write_text(a)

screen = Path("lib/screens/official_planning_screen.dart")
o = screen.read_text()

o = o.replace(
"""  final Map<String, int> _myGuardCounts = <String, int>{};
  final Set<String> _guardCountLoading = <String>{};""",
"""  final Map<String, int> _myGuardCounts = <String, int>{};
  final Map<String, int> _myDisciplinaryCounts = <String, int>{};
  final Set<String> _guardCountLoading = <String>{};""",
1)

old_count = """      final count = parsed.assignments.where((a) => a.profileId == me.id).length;
      if (mounted) setState(() => _myGuardCounts[slot.id] = count);"""
new_count = """      final summary = await _backend.officialRosterMySummary(resource: resource);
      final count = (summary['total'] as num?)?.toInt() ?? 0;
      final disciplinaryCount = (summary['disciplinary'] as num?)?.toInt() ?? 0;
      if (mounted) {
        setState(() {
          _myGuardCounts[slot.id] = count;
          _myDisciplinaryCounts[slot.id] = disciplinaryCount;
        });
      }"""
if old_count not in o:
    raise SystemExit("V11.6.53: personal count anchor missing")
o = o.replace(old_count, new_count, 1)

open_anchor = """  Future<void> _open(SharedResource resource) async {"""
if open_anchor not in o:
    raise SystemExit("V11.6.53: open method anchor missing")

resync_method = r"""  Future<void> _resyncMyRoster(
    _OfficialSlot slot,
    SharedResource resource,
  ) async {
    if (_busySlot != null || _guardCountLoading.contains(slot.id)) return;

    setState(() => _busySlot = slot.id);
    try {
      final appState = context.read<AppState>();
      await appState.forceSyncMyOfficialRoster();
      await _refreshMyGuardCount(_resources);

      if (!mounted) return;
      final count = _myGuardCounts[slot.id] ?? 0;
      final disciplinary = _myDisciplinaryCounts[slot.id] ?? 0;
      final disciplineLabel = disciplinary == 0
          ? ''
          : ' dont ${disciplinary} garde${disciplinary > 1 ? 's' : ''} disciplinaire${disciplinary > 1 ? 's' : ''}';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Superposition refaite : ${count} garde${count > 1 ? 's' : ''} retrouvée${count > 1 ? 's' : ''}${disciplineLabel}.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Resynchronisation impossible : ${e}')),
      );
    } finally {
      if (mounted) setState(() => _busySlot = null);
    }
  }

"""
o = o.replace(open_anchor, resync_method + open_anchor, 1)

o = o.replace(
"""                          myGuardCount: currentUser?.hospital == _slots[i].hospital ? _myGuardCounts[_slots[i].id] : null,
                          guardCountLoading: currentUser?.hospital == _slots[i].hospital && _guardCountLoading.contains(_slots[i].id),
                          isMyHospital: currentUser?.hospital == _slots[i].hospital,
                          onOpen: (r) => _open(r),""",
"""                          myGuardCount: currentUser?.hospital == _slots[i].hospital ? _myGuardCounts[_slots[i].id] : null,
                          myDisciplinaryCount: currentUser?.hospital == _slots[i].hospital ? _myDisciplinaryCounts[_slots[i].id] : null,
                          guardCountLoading: currentUser?.hospital == _slots[i].hospital && _guardCountLoading.contains(_slots[i].id),
                          isMyHospital: currentUser?.hospital == _slots[i].hospital,
                          onOpen: (r) => _open(r),
                          onResync: (r) => _resyncMyRoster(_slots[i], r),""",
1)

o = o.replace(
"""  final int? myGuardCount;
  final bool guardCountLoading;
  final bool isMyHospital;
  final ValueChanged<SharedResource> onOpen;""",
"""  final int? myGuardCount;
  final int? myDisciplinaryCount;
  final bool guardCountLoading;
  final bool isMyHospital;
  final ValueChanged<SharedResource> onOpen;
  final ValueChanged<SharedResource> onResync;""",
1)

o = o.replace(
"""    required this.myGuardCount,
    required this.guardCountLoading,
    required this.isMyHospital,
    required this.onOpen,""",
"""    required this.myGuardCount,
    required this.myDisciplinaryCount,
    required this.guardCountLoading,
    required this.isMyHospital,
    required this.onOpen,
    required this.onResync,""",
1)

old_label = """                      guardCountLoading
                          ? 'Recherche de vos gardes dans ce PDF…'
                          : '${myGuardCount ?? 0} garde${(myGuardCount ?? 0) > 1 ? 's' : ''} retrouvée${(myGuardCount ?? 0) > 1 ? 's' : ''} pour vous',"""
new_label = """                      guardCountLoading
                          ? 'Recherche de vos gardes dans ce PDF…'
                          : () {
                              final total = myGuardCount ?? 0;
                              final disciplinary = myDisciplinaryCount ?? 0;
                              final base =
                                  '${total} garde${total > 1 ? 's' : ''} retrouvée${total > 1 ? 's' : ''} pour vous';
                              if (disciplinary <= 0) return base;
                              return '${base} dont ${disciplinary} garde${disciplinary > 1 ? 's' : ''} disciplinaire${disciplinary > 1 ? 's' : ''}';
                            }(),"""
if old_label not in o:
    raise SystemExit("V11.6.53: guard count label anchor missing")
o = o.replace(old_label, new_label, 1)

visualiser = """              if (r != null)
                FilledButton.icon(
                  onPressed: busy ? null : () => onOpen(r),
                  icon: const Icon(Icons.visibility_rounded, size: 18),
                  label: const Text('Visualiser'),
                ),"""
resync_button = visualiser + r"""
              if (r != null && isMyHospital)
                OutlinedButton.icon(
                  onPressed: busy ? null : () => onResync(r),
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync_rounded, size: 18),
                  label: const Text('Resynchroniser'),
                ),"""
if visualiser not in o:
    raise SystemExit("V11.6.53: visualiser button anchor missing")
o = o.replace(visualiser, resync_button, 1)

screen.write_text(o)

source_sql = Path(__file__).resolve().parent / "official_resync_summary.sql"
if not source_sql.exists():
    raise SystemExit("V11.6.53: SQL migration source missing")

target_sql = Path("supabase/patch_v11_6_53_official_resync_summary.sql")
target_sql.write_text(source_sql.read_text())

checks = {
    "lib/screens/official_planning_screen.dart": [
        "_myDisciplinaryCounts",
        "disciplinaire",
        "Resynchroniser",
        "_resyncMyRoster",
    ],
    "lib/state/app_state.dart": [
        "forceSyncMyOfficialRoster",
        "applyCurrentDisciplinaryRulesForMe",
        "officialRosterMySummary",
    ],
    "lib/services/supabase_backend_service.dart": [
        "resetMyOfficialRosterProfileSync",
        "applyCurrentDisciplinaryRulesForMe",
    ],
    "supabase/patch_v11_6_53_official_resync_summary.sql": [
        "reset_my_official_roster_profile_sync",
        "apply_current_disciplinary_rules_for_me",
        "official_roster_my_summary",
    ],
}
for file_name, needles in checks.items():
    text = Path(file_name).read_text()
    for needle in needles:
        if needle not in text:
            raise SystemExit(f"V11.6.53: missing {needle!r} in {file_name}")

print("GardeFlow V11.6.53: official PDF summary shows disciplinary count + dedicated resync button")
