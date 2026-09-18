from pathlib import Path

EXPECTED = "version: 11.6.18+178"
TARGET = "version: 11.6.19+179"

pubspec = Path("pubspec.yaml")
pub = pubspec.read_text()
if EXPECTED not in pub:
    raise SystemExit("V11.6.19: base version mismatch")
pubspec.write_text(pub.replace(EXPECTED, TARGET, 1))

home = Path("lib/screens/home_screen.dart")
text = home.read_text()

text = text.replace("      extendBody: true,", "      extendBody: false,", 1)\ntext = text.replace("const SettingsScreen()", "SettingsScreen()")

old_shell = """      floatingActionButton: FloatingActionButton(
        heroTag: 'gardeflow-main-add',
        elevation: 7,
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
        onPressed: () => _showQuickAdd(context, appState),
        child: const Icon(Icons.add_rounded, size: 32),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: _MainBottomBar(
        selectedIndex: _tab,
        onSelected: (value) => setState(() => _tab = value),
      ),
"""

new_shell = """      bottomNavigationBar: NavigationBar(
        height: 72,
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Accueil',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month_rounded),
            label: 'Planning',
          ),
          NavigationDestination(
            icon: Icon(Icons.badge_outlined),
            selectedIcon: Icon(Icons.badge_rounded),
            label: 'Annuaire',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profil',
          ),
        ],
      ),
"""

if old_shell not in text:
    raise SystemExit("V11.6.19: main FAB/navigation block not found")
text = text.replace(old_shell, new_shell, 1)

def replace_class(source: str, class_name: str, replacement: str) -> str:
    marker = f"class {class_name} "
    start = source.find(marker)
    if start < 0:
        raise SystemExit(f"V11.6.19: {class_name} not found")
    brace = source.find("{", start)
    if brace < 0:
        raise SystemExit(f"V11.6.19: opening brace missing for {class_name}")
    depth = 0
    end = None
    for i in range(brace, len(source)):
        ch = source[i]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                end = i + 1
                break
    if end is None:
        raise SystemExit(f"V11.6.19: closing brace missing for {class_name}")
    return source[:start] + replacement.rstrip() + source[end:]

dashboard = r"""class _DashboardView extends StatelessWidget {
  final AppState appState;
  final VoidCallback onOpenPlanning;
  final VoidCallback onOpenDirectory;
  final VoidCallback onOpenProfile;

  const _DashboardView({
    required this.appState,
    required this.onOpenPlanning,
    required this.onOpenDirectory,
    required this.onOpenProfile,
  });

  List<PlanningEntry> _futureGuards(AppUser me) {
    final entries = appState.planning
        .where((entry) =>
            (entry.ownerId == me.id || entry.ownerPhone == me.phone) &&
            entry.shiftId != 'conge' &&
            appState.isPlanningEntryApproved(entry) &&
            !appState.guardHasStarted(entry))
        .toList()
      ..sort((a, b) {
        final ad = DateTime.parse(a.dateStr);
        final bd = DateTime.parse(b.dateStr);
        final cmp = ad.compareTo(bd);
        if (cmp != 0) return cmp;
        final ashift = ShiftCatalog.byId(a.shiftId);
        final bshift = ShiftCatalog.byId(b.shiftId);
        return (ashift.start ?? '').compareTo(bshift.start ?? '');
      });
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final me = appState.currentUser;
    if (me == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final future = _futureGuards(me);
    final next = future.isEmpty ? null : future.first;
    final now = DateTime.now();
    final rawDate = DateFormat('EEEE d MMMM yyyy', 'fr_FR').format(now);
    final dateLabel = rawDate.isEmpty
        ? ''
        : rawDate[0].toUpperCase() + rawDate.substring(1);
    final timeLabel = DateFormat('HH:mm').format(now);

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 28, 18, 32),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.brandDark, AppColors.brand],
            ),
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: AppColors.brand.withOpacity(0.20),
                blurRadius: 28,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                right: -16,
                top: -24,
                child: Container(
                  width: 112,
                  height: 112,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.08),
                  ),
                ),
              ),
              Positioned(
                right: 18,
                bottom: -42,
                child: Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.06),
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bonjour Dr ${me.nom}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'SpaceGrotesk',
                      fontSize: 31,
                      height: 1.08,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.7,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.schedule_rounded,
                        color: Colors.white.withOpacity(0.82),
                        size: 19,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'On est le $dateLabel, il est $timeLabel',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.88),
                            fontSize: 14,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 30),
        Text(
          'Prochaine garde à venir',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontFamily: 'SpaceGrotesk',
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          next == null
              ? 'Aucune garde validée à venir pour le moment.'
              : 'Voici votre prochaine garde programmée.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.inkSoft,
                fontWeight: FontWeight.w500,
              ),
        ),
        const SizedBox(height: 14),
        _NextGuardCard(
          entry: next,
          onTap: onOpenPlanning,
        ),
      ],
    );
  }
}
"""

text = replace_class(text, "_DashboardView", dashboard)

home.write_text(text)

print("V11.6.19 accueil simplifie: bonjour/date-heure/prochaine garde, FAB central supprime")
