from pathlib import Path

EXPECTED = "version: 11.6.49+209"
TARGET = "version: 11.6.50+210"

pubspec = Path("pubspec.yaml")
pub = pubspec.read_text()
if EXPECTED not in pub:
    raise SystemExit("V11.6.50: base version mismatch")
pubspec.write_text(pub.replace(EXPECTED, TARGET, 1))


def class_range(source: str, class_name: str) -> tuple[int, int]:
    marker = f"class {class_name} "
    start = source.find(marker)
    if start < 0:
        raise SystemExit(f"V11.6.50: {class_name} not found")
    brace = source.find("{", start)
    if brace < 0:
        raise SystemExit(f"V11.6.50: opening brace missing for {class_name}")
    depth = 0
    for i in range(brace, len(source)):
        if source[i] == "{":
            depth += 1
        elif source[i] == "}":
            depth -= 1
            if depth == 0:
                return start, i + 1
    raise SystemExit(f"V11.6.50: closing brace missing for {class_name}")


# ---------------------------------------------------------------------------
# 1) Astreinte Junior : le bouton calendrier ouvre le mois complet.
#    Sélectionner un jour repositionne ensuite la vue hebdomadaire sur ce jour.
# ---------------------------------------------------------------------------
junior = Path("lib/screens/junior_oncall_screen.dart")
j = junior.read_text()
state_start, state_end = class_range(j, "_JuniorOnCallScreenState")
state = j[state_start:state_end]

build_marker = "  @override\n  Widget build(BuildContext context)"
if build_marker not in state:
    raise SystemExit("V11.6.50: junior build marker missing")

method = r"""  Future<void> _openMonthCalendar() async {
    final currentDate = _weekStart.add(
      Duration(days: _selectedDayIndex),
    );

    final picked = await showDatePicker(
      context: context,
      locale: const Locale('fr', 'FR'),
      initialDate: currentDate,
      firstDate: DateTime(currentDate.year - 1, 1, 1),
      lastDate: DateTime(currentDate.year + 2, 12, 31),
      initialDatePickerMode: DatePickerMode.day,
      helpText: 'Calendrier des astreintes juniors',
      cancelText: 'Fermer',
      confirmText: 'Afficher',
    );

    if (picked == null || !mounted) return;

    final monday = picked.subtract(
      Duration(days: picked.weekday - DateTime.monday),
    );

    setState(() {
      _weekStart = DateTime(monday.year, monday.month, monday.day);
      _selectedDayIndex = picked.weekday - DateTime.monday;
    });

    await _load();
  }

"""

state = state.replace(build_marker, method + build_marker, 1)

state = state.replace(
    """                  tooltip: 'Aujourd’hui',
                  visualDensity: VisualDensity.compact,
                  onPressed: _loading ? null : _goToCurrentWeek,
                  icon: const Icon(Icons.today_rounded, size: 20),""",
    """                  tooltip: 'Calendrier du mois',
                  visualDensity: VisualDensity.compact,
                  onPressed: _loading ? null : _openMonthCalendar,
                  icon: const Icon(Icons.calendar_month_rounded, size: 20),""",
    1,
)

state = state.replace(
    """            tooltip: 'Aujourd’hui',
            onPressed: _loading ? null : _goToCurrentWeek,
            icon: const Icon(Icons.today_rounded),""",
    """            tooltip: 'Calendrier du mois',
            onPressed: _loading ? null : _openMonthCalendar,
            icon: const Icon(Icons.calendar_month_rounded),""",
    1,
)

j = j[:state_start] + state + j[state_end:]
junior.write_text(j)


# ---------------------------------------------------------------------------
# 2) Planning : la fenêtre explicative doit rester au-dessus de la barre
#    de navigation Android / zone système.
# ---------------------------------------------------------------------------
home = Path("lib/screens/home_screen.dart")
h = home.read_text()

old_sheet = r"""    showModalBottomSheet<void>(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.xl,
          AppSpace.md,
          AppSpace.xl,
          AppSpace.xxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpace.sm),
            Text(detail, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );"""

new_sheet = r"""    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: AppSpace.lg),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.xl,
            AppSpace.sm,
            AppSpace.xl,
            AppSpace.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpace.sm),
              Text(
                detail,
                style: Theme.of(sheetContext).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );"""

if old_sheet not in h:
    raise SystemExit("V11.6.50: planning month info bottom-sheet anchor missing")
h = h.replace(old_sheet, new_sheet, 1)

# ---------------------------------------------------------------------------
# 3) Garde disciplinaire : conserver le verrou absolu côté médecin même si
#    le mois est encore draft / non validé. V11.6.47 l'implémente déjà ;
#    cette version refuse de se construire si une de ces protections disparaît.
# ---------------------------------------------------------------------------
disciplinary_checks = [
    "if(existing?.isDisciplinary==true)return 'Cette garde disciplinaire est verrouillée. Seul un administrateur peut la supprimer.';",
    "if(entry.isDisciplinary)return 'Cette garde disciplinaire ne peut pas être annulée. Seul un administrateur peut la supprimer.';",
    "!entry.isDisciplinary && !appState.isApprovedLeaveEntry(entry)",
]
state_text = Path("lib/state/app_state.dart").read_text()
for needle in disciplinary_checks[:2]:
    if needle not in state_text:
        raise SystemExit(f"V11.6.50: disciplinary lock missing in app state: {needle}")

if disciplinary_checks[2] not in h:
    raise SystemExit("V11.6.50: disciplinary UI lock missing from planning calendar")

home.write_text(h)

print("GardeFlow V11.6.50: Junior monthly calendar + Android-safe info sheet + disciplinary lock verified")
