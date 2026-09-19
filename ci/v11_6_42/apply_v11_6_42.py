from pathlib import Path
import re

EXPECTED = "version: 11.6.41+201"
TARGET = "version: 11.6.42+202"

pubspec = Path("pubspec.yaml")
pub = pubspec.read_text()
if EXPECTED not in pub:
    raise SystemExit("V11.6.42: base version mismatch")
pubspec.write_text(pub.replace(EXPECTED, TARGET, 1))


def class_range(source: str, class_name: str) -> tuple[int, int]:
    marker = f"class {class_name} "
    start = source.find(marker)
    if start < 0:
        raise SystemExit(f"V11.6.42: {class_name} not found")
    brace = source.find("{", start)
    if brace < 0:
        raise SystemExit(f"V11.6.42: opening brace missing for {class_name}")
    depth = 0
    for i in range(brace, len(source)):
        if source[i] == "{":
            depth += 1
        elif source[i] == "}":
            depth -= 1
            if depth == 0:
                return start, i + 1
    raise SystemExit(f"V11.6.42: closing brace missing for {class_name}")


# ---------------------------------------------------------------------------
# Accueil: conserve exactement le contenu/fonctions, change seulement les fonds.
# ---------------------------------------------------------------------------
home = Path("lib/screens/home_screen.dart")
h = home.read_text()

old_hero = """    final heroColors = isNight
        ? const [Color(0xFF143B2C), Color(0xFF071C15)]
        : const [Color(0xFF22A764), Color(0xFF0B6C42)];"""
new_hero = """    final heroColors = isNight
        ? const [Color(0xFF071426), Color(0xFF123D70)]
        : const [Color(0xFF55C2FF), Color(0xFF087FE8)];"""
if old_hero not in h:
    raise SystemExit("V11.6.42: heroColors anchor missing")
h = h.replace(old_hero, new_hero, 1)

start, end = class_range(h, "_NextGuardCard")
card = h[start:end]

build_anchor = "  Widget build(BuildContext context) {"
if build_anchor not in card:
    raise SystemExit("V11.6.42: _NextGuardCard build anchor missing")

card_vars = """  Widget build(BuildContext context) {
    final guardShiftId = entry?.shiftId.toLowerCase() ?? '';
    final guardIs24h = guardShiftId.contains('24h') || guardShiftId.contains('24-h');
    final guardIsNight = !guardIs24h && guardShiftId.contains('nuit');
    final guardBackground = entry == null
        ? const [Color(0xFF6B7A8D), Color(0xFF465568)]
        : guardIs24h
            ? const [Color(0xFF58C8FF), Color(0xFF1766B1), Color(0xFF08172E)]
            : guardIsNight
                ? const [Color(0xFF071426), Color(0xFF123D70)]
                : const [Color(0xFF55C2FF), Color(0xFF087FE8)];"""
card = card.replace(build_anchor, card_vars, 1)

deco_anchor = "decoration: BoxDecoration("
deco_pos = card.find(deco_anchor)
if deco_pos < 0:
    raise SystemExit("V11.6.42: _NextGuardCard decoration missing")
insert_pos = deco_pos + len(deco_anchor)
card = card[:insert_pos] + "\n            gradient: LinearGradient(\n              begin: Alignment.topLeft,\n              end: Alignment.bottomRight,\n              colors: guardBackground,\n            )," + card[insert_pos:]

for old, new in [
    ("AppColors.inkSoft", "Colors.white"),
    ("AppColors.inkFaint", "Colors.white"),
    ("AppColors.ink", "Colors.white"),
    ("AppColors.brandSoft", "Colors.white24"),
    ("AppColors.brand", "Colors.white"),
    ("AppColors.line", "Colors.white30"),
]:
    card = card.replace(old, new)

h = h[:start] + card + h[end:]
home.write_text(h)


# ---------------------------------------------------------------------------
# Menu Rappels: choix indépendant pour l'écran plein écran.
# ---------------------------------------------------------------------------
settings = Path("lib/screens/settings_screen.dart")
s = settings.read_text()

prefs_import = "import 'package:shared_preferences/shared_preferences.dart';"
if prefs_import not in s:
    import_anchor = "import 'package:provider/provider.dart';"
    if import_anchor not in s:
        raise SystemExit("V11.6.42: provider import anchor missing")
    s = s.replace(import_anchor, import_anchor + "\n" + prefs_import, 1)

state_anchor = """  bool _saving = false;
  bool _migratedToAlarm = false;"""
state_replacement = """  bool _saving = false;
  bool _migratedToAlarm = false;
  static const _fullScreenPreferenceKey = 'guard_fullscreen_alarm';
  bool _fullScreenAlarm = true;
  bool _fullScreenPreferenceLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadFullScreenPreference();
  }

  Future<void> _loadFullScreenPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_fullScreenPreferenceKey) ?? true;
    if (!mounted) return;
    setState(() {
      _fullScreenAlarm = enabled;
      _fullScreenPreferenceLoaded = true;
    });
  }

  Future<void> _setFullScreenAlarm(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_fullScreenPreferenceKey, enabled);
    if (!mounted) return;
    setState(() => _fullScreenAlarm = enabled);
  }"""
if state_anchor not in s:
    raise SystemExit("V11.6.42: settings state anchor missing")
s = s.replace(state_anchor, state_replacement, 1)

when_anchor = """          const SizedBox(height: AppSpace.xl),
          const SectionLabel('Quand sonner ?'),"""
full_screen_card = """          const SizedBox(height: AppSpace.xl),
          const SectionLabel('Affichage de l’alarme'),
          AppCard(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.brandSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.fullscreen_rounded,
                    color: AppColors.brand,
                    size: 25,
                  ),
                ),
                const SizedBox(width: 11),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Alarme plein écran',
                        style: TextStyle(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Afficher le visuel JOUR, NUIT ou 24H quand l’alarme sonne.',
                        style: TextStyle(
                          color: AppColors.inkSoft,
                          fontSize: 11.5,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Switch(
                  value: _fullScreenAlarm,
                  onChanged: !_fullScreenPreferenceLoaded || _saving
                      ? null
                      : _setFullScreenAlarm,
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpace.xl),
          const SectionLabel('Quand sonner ?'),"""
if when_anchor not in s:
    raise SystemExit("V11.6.42: settings 'Quand sonner' anchor missing")
s = s.replace(when_anchor, full_screen_card, 1)
settings.write_text(s)

print("GardeFlow V11.6.42: dynamic day/night/24h card backgrounds + optional full-screen alarm")
