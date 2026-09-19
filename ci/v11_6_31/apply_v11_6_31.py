from pathlib import Path

EXPECTED = "version: 11.6.30+190"
TARGET = "version: 11.6.31+191"

pubspec = Path("pubspec.yaml")
pub = pubspec.read_text()
if EXPECTED not in pub:
    raise SystemExit("V11.6.31: base version mismatch")
pubspec.write_text(pub.replace(EXPECTED, TARGET, 1))

def replace_class(source: str, class_name: str, replacement: str) -> str:
    marker = f"class {class_name} "
    start = source.find(marker)
    if start < 0:
        raise SystemExit(f"V11.6.31: {class_name} not found")
    brace = source.find("{", start)
    if brace < 0:
        raise SystemExit(f"V11.6.31: opening brace missing for {class_name}")
    depth = 0
    end = None
    for i in range(brace, len(source)):
        if source[i] == "{":
            depth += 1
        elif source[i] == "}":
            depth -= 1
            if depth == 0:
                end = i + 1
                break
    if end is None:
        raise SystemExit(f"V11.6.31: closing brace missing for {class_name}")
    return source[:start] + replacement.rstrip() + source[end:]

# ---------------------------------------------------------------------------
# Bottom navigation: keep the four tabs, add a center bell action that opens
# reminder settings directly. The bell is an action, not a fifth IndexedStack tab.
# ---------------------------------------------------------------------------
home = Path("lib/screens/home_screen.dart")
h = home.read_text()

old_nav = """      bottomNavigationBar: NavigationBar(
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
            icon: Icon(Icons.medical_services_outlined),
            selectedIcon: Icon(Icons.medical_services_rounded),
            label: 'Astreintes',
          ),
        ],
      ),"""

new_nav = """      bottomNavigationBar: _MainBottomBar(
        selectedIndex: _tab,
        onSelected: (value) => setState(() => _tab = value),
        onReminders: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const SettingsScreen(reminderFocus: true),
          ),
        ),
      ),"""

if old_nav not in h:
    raise SystemExit("V11.6.31: current NavigationBar block not found")
h = h.replace(old_nav, new_nav, 1)

main_bottom_bar = r"""class _MainBottomBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onReminders;

  const _MainBottomBar({
    required this.selectedIndex,
    required this.onSelected,
    required this.onReminders,
  });

  @override
  Widget build(BuildContext context) {
    Widget item(
      int index,
      IconData icon,
      IconData selectedIcon,
      String label,
    ) {
      final selected = selectedIndex == index;
      return Expanded(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onSelected(index),
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(2, 7, 2, 5),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 38,
                    height: 29,
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.brandSoft
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      selected ? selectedIcon : icon,
                      color: selected
                          ? AppColors.brand
                          : AppColors.inkSoft,
                      size: 21,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 9,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                      color: selected
                          ? AppColors.brand
                          : AppColors.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      height: 78,
      decoration: BoxDecoration(
        color: AppColors.card,
        border: const Border(
          top: BorderSide(color: AppColors.line),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withOpacity(0.08),
            blurRadius: 18,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                item(
                  0,
                  Icons.home_outlined,
                  Icons.home_rounded,
                  'Accueil',
                ),
                item(
                  1,
                  Icons.calendar_month_outlined,
                  Icons.calendar_month_rounded,
                  'Planning',
                ),
                const SizedBox(width: 74),
                item(
                  2,
                  Icons.badge_outlined,
                  Icons.badge_rounded,
                  'Annuaire',
                ),
                item(
                  3,
                  Icons.medical_services_outlined,
                  Icons.medical_services_rounded,
                  'Astreintes',
                ),
              ],
            ),
            Positioned(
              top: -17,
              child: Tooltip(
                message: 'Réglages des rappels de garde',
                child: Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  child: InkWell(
                    onTap: onReminders,
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.brandDark,
                            AppColors.brand,
                          ],
                        ),
                        border: Border.all(
                          color: AppColors.card,
                          width: 4,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.brand.withOpacity(0.30),
                            blurRadius: 15,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.notifications_active_rounded,
                        color: Colors.white,
                        size: 27,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const Positioned(
              top: 43,
              child: Text(
                'Rappels',
                style: TextStyle(
                  color: AppColors.brandDark,
                  fontSize: 8.5,
                  height: 1,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
"""

h = replace_class(h, "_MainBottomBar", main_bottom_bar)
home.write_text(h)

# ---------------------------------------------------------------------------
# Settings: add a reminder-focused entry mode. Normal Profile -> Settings
# stays unchanged. The center bell opens directly on reminder controls.
# ---------------------------------------------------------------------------
settings = Path("lib/screens/settings_screen.dart")
s = settings.read_text()

old_widget = """class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}"""
new_widget = """class SettingsScreen extends StatefulWidget {
  final bool reminderFocus;

  const SettingsScreen({
    super.key,
    this.reminderFocus = false,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}"""
if old_widget not in s:
    raise SystemExit("V11.6.31: SettingsScreen constructor not found")
s = s.replace(old_widget, new_widget, 1)

old_appbar = """      appBar: AppBar(title: const GardeFlowTitle('Réglages')),
      body: ListView("""
new_appbar = """      appBar: AppBar(
        title: GardeFlowTitle(
          widget.reminderFocus ? 'Rappels de garde' : 'Réglages',
        ),
      ),
      body: ListView("""
if old_appbar not in s:
    raise SystemExit("V11.6.31: settings AppBar anchor not found")
s = s.replace(old_appbar, new_appbar, 1)

old_intro = """          AppCard(
            padding: const EdgeInsets.all(AppSpace.lg),
            color: AppColors.brandSoft,
            shadow: const [],
            border: Border.all(color: const Color(0xFFCFE3FA)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.tune_rounded, color: AppColors.brand),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Préférences de garde', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 3),
                      Text(
                        'Configurez uniquement les rappels et le comportement des notifications. Votre compte se gère depuis l’onglet Profil.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.xl),

          const SectionLabel('Rappels de garde'),"""

new_intro = """          if (!widget.reminderFocus) ...[
            AppCard(
              padding: const EdgeInsets.all(AppSpace.lg),
              color: AppColors.brandSoft,
              shadow: const [],
              border: Border.all(color: const Color(0xFFCFE3FA)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.tune_rounded,
                      color: AppColors.brand,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Préférences de garde',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Configurez uniquement les rappels et le comportement des notifications. Votre compte se gère depuis l’onglet Profil.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.xl),
          ],

          const SectionLabel('Rappels de garde'),"""
if old_intro not in s:
    raise SystemExit("V11.6.31: settings intro block not found")
s = s.replace(old_intro, new_intro, 1)

settings.write_text(s)

print("GardeFlow V11.6.31: sonnette centrale -> réglages directs des rappels")
