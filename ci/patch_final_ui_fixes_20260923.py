from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    if old not in text:
        raise SystemExit(f"Pattern not found in {path}: {old[:120]!r}")
    p.write_text(text.replace(old, new, 1))


def replace_all_required(path: str, old: str, new: str, minimum: int = 1) -> None:
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count < minimum:
        raise SystemExit(f"Expected at least {minimum} matches in {path}, found {count}: {old!r}")
    p.write_text(text.replace(old, new))


# 1) Astreintes: selected hospital chips must keep readable text in dark/green themes.
replace_once(
    "source/lib/screens/junior_oncall_screen.dart",
    """          return ChoiceChip(\n            visualDensity: VisualDensity.compact,\n            padding: EdgeInsets.symmetric(horizontal: 7),\n            label: Text(\n              _juniorHospitalLabel(hospital),\n              style: TextStyle(\n                fontSize: 10.5,\n                fontWeight: FontWeight.w800,\n                color: selected ? AppColors.brandDark : AppColors.inkSoft,\n              ),\n            ),\n            selected: selected,\n            onSelected: (_) => onChanged(hospital),\n          );""",
    """          return ChoiceChip(\n            visualDensity: VisualDensity.compact,\n            padding: EdgeInsets.symmetric(horizontal: 7),\n            selectedColor: AppColors.brand,\n            backgroundColor: AppColors.card,\n            side: BorderSide(\n              color: selected ? AppColors.brandBright : AppColors.line,\n            ),\n            label: Text(\n              _juniorHospitalLabel(hospital),\n              style: TextStyle(\n                fontSize: 10.5,\n                fontWeight: FontWeight.w800,\n                color: selected ? Colors.white : AppColors.inkSoft,\n              ),\n            ),\n            selected: selected,\n            onSelected: (_) => onChanged(hospital),\n          );""",
)

replace_once(
    "source/lib/screens/senior_oncall_screen.dart",
    """          return ChoiceChip(\n            label: Text(\n              hospitalDisplayName(hospital),\n              style: TextStyle(\n                fontSize: 10.5,\n                fontWeight: FontWeight.w800,\n                color: selected ? AppColors.brandDark : AppColors.inkSoft,\n              ),\n            ),\n            selected: selected,\n            onSelected: (_) => onChanged(hospital),\n          );""",
    """          return ChoiceChip(\n            selectedColor: AppColors.brand,\n            backgroundColor: AppColors.card,\n            side: BorderSide(\n              color: selected ? AppColors.brandBright : AppColors.line,\n            ),\n            label: Text(\n              hospitalDisplayName(hospital),\n              style: TextStyle(\n                fontSize: 10.5,\n                fontWeight: FontWeight.w800,\n                color: selected ? Colors.white : AppColors.inkSoft,\n              ),\n            ),\n            selected: selected,\n            onSelected: (_) => onChanged(hospital),\n          );""",
)

replace_once(
    "source/lib/screens/astreinte_screen.dart",
    """                  ChoiceChip(\n                    label: Text(hospitalDisplayName(item)),\n                    selected: item == hospital,\n                    onSelected: (_) => onSelectHospital(item),\n                  ),""",
    """                  ChoiceChip(\n                    selectedColor: AppColors.brand,\n                    backgroundColor: AppColors.card,\n                    side: BorderSide(\n                      color: item == hospital\n                          ? AppColors.brandBright\n                          : AppColors.line,\n                    ),\n                    label: Text(\n                      hospitalDisplayName(item),\n                      style: TextStyle(\n                        color: item == hospital\n                            ? Colors.white\n                            : AppColors.inkSoft,\n                        fontWeight: FontWeight.w800,\n                      ),\n                    ),\n                    selected: item == hospital,\n                    onSelected: (_) => onSelectHospital(item),\n                  ),""",
)

# 2) Home: make "Actualités plus bas" a real action targeting the vertical categorized feed.
home_path = Path("source/lib/screens/home_screen.dart")
home = home_path.read_text()
home = home.replace(
    "class _HomeScreenState extends State<HomeScreen> {\n  int _tab = 0;",
    "class _HomeScreenState extends State<HomeScreen> {\n  int _tab = 0;\n  final GlobalKey _newsFeedKey = GlobalKey();",
    1,
)
home = home.replace(
    """                  _DashboardView(\n                    appState: appState,\n                    onOpenPlanning: () => setState(() => _tab = 1),""",
    """                  _DashboardView(\n                    appState: appState,\n                    newsFeedKey: _newsFeedKey,\n                    onOpenPlanning: () => setState(() => _tab = 1),""",
    1,
)
home = home.replace(
    """class _DashboardView extends StatelessWidget {\n  final AppState appState;\n  final VoidCallback onOpenPlanning;""",
    """class _DashboardView extends StatelessWidget {\n  final AppState appState;\n  final GlobalKey newsFeedKey;\n  final VoidCallback onOpenPlanning;""",
    1,
)
home = home.replace(
    """  const _DashboardView({\n    required this.appState,\n    required this.onOpenPlanning,""",
    """  const _DashboardView({\n    required this.appState,\n    required this.newsFeedKey,\n    required this.onOpenPlanning,""",
    1,
)
old_news_button = """        Center(\n          child: Container(\n            padding: EdgeInsets.symmetric(horizontal: 13, vertical: 8),\n            decoration: BoxDecoration(\n              color: AppColors.card,\n              borderRadius: BorderRadius.circular(999),\n              border: Border.all(color: AppColors.brandBright, width: 1.2),\n            ),\n            child: Row(\n              mainAxisSize: MainAxisSize.min,\n              children: [\n                Text(\n                  'Actualités plus bas',\n                  style: TextStyle(\n                    color: AppColors.ink,\n                    fontSize: 11.5,\n                    fontWeight: FontWeight.w800,\n                  ),\n                ),\n                SizedBox(width: 6),\n                Icon(\n                  Icons.keyboard_arrow_down_rounded,\n                  color: AppColors.brandBright,\n                  size: 20,\n                ),\n              ],\n            ),\n          ),\n        ),\n        SizedBox(height: 14),\n        DailyNewsSection(),"""
new_news_button = """        Center(\n          child: Material(\n            color: Colors.transparent,\n            child: InkWell(\n              borderRadius: BorderRadius.circular(999),\n              onTap: () {\n                final targetContext = newsFeedKey.currentContext;\n                if (targetContext == null) return;\n                Scrollable.ensureVisible(\n                  targetContext,\n                  duration: const Duration(milliseconds: 520),\n                  curve: Curves.easeOutCubic,\n                  alignment: 0.04,\n                );\n              },\n              child: Ink(\n                padding: EdgeInsets.symmetric(horizontal: 13, vertical: 8),\n                decoration: BoxDecoration(\n                  color: AppColors.card,\n                  borderRadius: BorderRadius.circular(999),\n                  border: Border.all(\n                    color: AppColors.brandBright,\n                    width: 1.2,\n                  ),\n                ),\n                child: Row(\n                  mainAxisSize: MainAxisSize.min,\n                  children: [\n                    Text(\n                      'Actualités plus bas',\n                      style: TextStyle(\n                        color: AppColors.ink,\n                        fontSize: 11.5,\n                        fontWeight: FontWeight.w800,\n                      ),\n                    ),\n                    SizedBox(width: 6),\n                    Icon(\n                      Icons.keyboard_arrow_down_rounded,\n                      color: AppColors.brandBright,\n                      size: 20,\n                    ),\n                  ],\n                ),\n              ),\n            ),\n          ),\n        ),\n        SizedBox(height: 14),\n        DailyNewsSection(verticalFeedKey: newsFeedKey),"""
if old_news_button not in home:
    raise SystemExit("Home news button block not found")
home = home.replace(old_news_button, new_news_button, 1)

# 3) Planning header: promotion first, then "Planning PDF", then announcement megaphone.
home = home.replace("'Planning officiel'", "'Planning PDF'", 1)
planning_anchor = "              Expanded(\n                flex: 10,\n                child: Material("
promo_anchor = "              if (promotionLabel != null) ...["
announce_anchor = "              const SizedBox(width: 6),\n              const _AnnouncementsCompactButton(),"
planning_start = home.find(planning_anchor, home.find("class _PlanningView"))
promo_start = home.find(promo_anchor, planning_start)
announce_start = home.find(announce_anchor, promo_start)
if min(planning_start, promo_start, announce_start) < 0:
    raise SystemExit("Planning header blocks not found")
planning_block = home[planning_start:promo_start]
promo_block = home[promo_start:announce_start]
promo_block = promo_block.replace(
    "              if (promotionLabel != null) ...[\n                const SizedBox(width: 6),\n",
    "              if (promotionLabel != null) ...[\n",
    1,
)
reordered = (
    promo_block
    + "              if (promotionLabel != null) const SizedBox(width: 6),\n"
    + planning_block
)
home = home[:planning_start] + reordered + home[announce_start:]
home_path.write_text(home)

# DailyNewsSection exposes a precise scroll target on the vertical categorized feed.
replace_once(
    "source/lib/screens/daily_news_section.dart",
    """class DailyNewsSection extends StatefulWidget {\n  const DailyNewsSection({super.key});""",
    """class DailyNewsSection extends StatefulWidget {\n  final Key? verticalFeedKey;\n\n  const DailyNewsSection({super.key, this.verticalFeedKey});""",
)
replace_once(
    "source/lib/screens/daily_news_section.dart",
    """              Text(\n                'Fil d’actualités',""",
    """              Text(\n                'Fil d’actualités',\n                key: widget.verticalFeedKey,""",
)

# 4) Directory: make add-contact CTA lighter and much more visible.
replace_once(
    "source/lib/screens/directory_screen.dart",
    """                  child: FloatingActionButton(\n                    heroTag: 'directory-add-contact-embedded',\n                    tooltip: 'Ajouter un contact',\n                    onPressed: () => _openContactEditor(context, appState),\n                    backgroundColor: AppColors.brandDark,\n                    foregroundColor: Colors.white,\n                    elevation: 5,\n                    child: Icon(Icons.person_add_alt_1_rounded),\n                  ),""",
    """                  child: FloatingActionButton.extended(\n                    heroTag: 'directory-add-contact-embedded',\n                    tooltip: 'Ajouter un contact',\n                    onPressed: () => _openContactEditor(context, appState),\n                    backgroundColor: AppColors.brandBright,\n                    foregroundColor: Colors.white,\n                    elevation: 7,\n                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),\n                    label: const Text(\n                      'Ajouter',\n                      style: TextStyle(fontWeight: FontWeight.w900),\n                    ),\n                  ),""",
)
replace_once(
    "source/lib/screens/directory_screen.dart",
    """          ? FloatingActionButton(\n              heroTag: 'directory-add-contact-standalone',\n              tooltip: 'Ajouter un contact',\n              onPressed: () => _openContactEditor(context, appState),\n              backgroundColor: AppColors.brandDark,\n              foregroundColor: Colors.white,\n              child: Icon(Icons.person_add_alt_1_rounded),\n            )""",
    """          ? FloatingActionButton.extended(\n              heroTag: 'directory-add-contact-standalone',\n              tooltip: 'Ajouter un contact',\n              onPressed: () => _openContactEditor(context, appState),\n              backgroundColor: AppColors.brandBright,\n              foregroundColor: Colors.white,\n              elevation: 7,\n              icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),\n              label: const Text(\n                'Ajouter',\n                style: TextStyle(fontWeight: FontWeight.w900),\n              ),\n            )""",
)

# 5) Registration: remove the explanatory paragraph under promotion dropdown.
replace_once(
    "source/lib/screens/auth_screen.dart",
    """          SizedBox(height: 7),\n          Text(\n            'La Promo $latestPromotion est actuellement la 1re année. Une nouvelle promotion n’apparaît ici qu’après son ajout par un administrateur.',\n            style: TextStyle(\n              fontSize: 10.8,\n              height: 1.35,\n              color: AppColors.inkFaint,\n              fontWeight: FontWeight.w600,\n            ),\n          ),\n""",
    "",
)

print("Final UI fixes applied successfully")
