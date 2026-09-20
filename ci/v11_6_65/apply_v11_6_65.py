from pathlib import Path

EXPECTED = "version: 11.6.64+224"
TARGET = "version: 11.6.65+225"


def replace_once(path: str, old: str, new: str, label: str) -> None:
    p = Path(path)
    text = p.read_text()
    if old not in text:
        if new in text:
            return
        raise SystemExit(f"V11.6.65: {label} anchor missing in {path}")
    p.write_text(text.replace(old, new, 1))


pubspec = Path("pubspec.yaml")
pub = pubspec.read_text()
if EXPECTED not in pub:
    if TARGET not in pub:
        raise SystemExit("V11.6.65: base version mismatch")
else:
    pubspec.write_text(pub.replace(EXPECTED, TARGET, 1))

# ---------------------------------------------------------------------------
# AppState: replace the old dark-mode boolean choice with four persistent
# appearance themes. Green is the new default.
# ---------------------------------------------------------------------------
replace_once(
    "lib/state/app_state.dart",
    """  bool _darkMode = true;
  bool _darkDefaultAppliedV58 = false;
  bool get darkMode => _darkMode;

  Future<void> setDarkMode(bool enabled) async {
    if (_darkMode == enabled) return;
    _darkMode = enabled;
    await _persistNow();
    notifyListeners();
  }
""",
    """  String _appearanceTheme = 'green';
  bool _darkDefaultAppliedV58 = true;

  String get appearanceTheme => _appearanceTheme;

  // Compatibility for screens/helpers that still only need to know whether
  // light or dark foregrounds are required. Green, red and black are dark.
  bool get darkMode => _appearanceTheme != 'white';

  Future<void> setAppearanceTheme(String value) async {
    const allowed = <String>{'green', 'red', 'white', 'black'};
    final next = allowed.contains(value) ? value : 'green';
    if (_appearanceTheme == next) return;
    _appearanceTheme = next;
    await _persistNow();
    notifyListeners();
  }

  // Legacy API kept temporarily so old call sites cannot break.
  Future<void> setDarkMode(bool enabled) =>
      setAppearanceTheme(enabled ? 'black' : 'white');
""",
    "appearance state",
)

replace_once(
    "lib/state/app_state.dart",
    """'planningCounter':_planningCounter,'exchangeCounter':_exchangeCounter,'leaveCounter':_leaveCounter,'reminderCounter':_reminderCounter,'darkMode':_darkMode,'darkDefaultAppliedV58':true,""",
    """'planningCounter':_planningCounter,'exchangeCounter':_exchangeCounter,'leaveCounter':_leaveCounter,'reminderCounter':_reminderCounter,'appearanceTheme':_appearanceTheme,'darkMode':darkMode,'darkDefaultAppliedV58':true,""",
    "persist appearance theme",
)

replace_once(
    "lib/state/app_state.dart",
    """_delayMinutes=(j['delayMinutes'] as num?)?.toInt()??60;_notificationsOn=j['notificationsOn'] as bool? ?? true;_darkDefaultAppliedV58=j['darkDefaultAppliedV58'] as bool? ?? false;_darkMode=_darkDefaultAppliedV58 ? (j['darkMode'] as bool? ?? true) : true;_darkDefaultAppliedV58=true;""",
    """_delayMinutes=(j['delayMinutes'] as num?)?.toInt()??60;_notificationsOn=j['notificationsOn'] as bool? ?? true;_darkDefaultAppliedV58=true;final storedAppearanceTheme=j['appearanceTheme']?.toString();_appearanceTheme=const <String>{'green','red','white','black'}.contains(storedAppearanceTheme)?storedAppearanceTheme!:'green';""",
    "restore appearance theme",
)

# ---------------------------------------------------------------------------
# Root app: apply selected palette globally and choose light/dark Material
# brightness from that palette.
# ---------------------------------------------------------------------------
replace_once(
    "lib/main.dart",
    """    final darkMode = context.select<AppState, bool>((state) => state.darkMode);
    AppColors.setDarkMode(darkMode);

    return MaterialApp(
""",
    """    final appearanceTheme =
        context.select<AppState, String>((state) => state.appearanceTheme);
    AppColors.setAppearanceTheme(appearanceTheme);
    final darkMode = AppColors.isDarkMode;

    return MaterialApp(
""",
    "root appearance selector",
)

# ---------------------------------------------------------------------------
# Dynamic app palette.
# Business colors for Service/Urgences/Congé remain unchanged so the planning
# keeps its medical meaning. The application chrome/surfaces/buttons change.
# ---------------------------------------------------------------------------
replace_once(
    "lib/theme/app_theme.dart",
    """  // Surfaces / texte adaptatifs.
  static bool _darkMode = false;

  static void setDarkMode(bool enabled) => _darkMode = enabled;
  static bool get isDarkMode => _darkMode;

  static Color get paper =>
      _darkMode ? const Color(0xFF0C1410) : const Color(0xFFF5F8F6);
  static Color get paperAlt =>
      _darkMode ? const Color(0xFF131E18) : const Color(0xFFEDF3EF);
  static Color get card =>
      _darkMode ? const Color(0xFF18251F) : const Color(0xFFFFFFFF);
  static Color get ink =>
      _darkMode ? const Color(0xFFF2F7F4) : const Color(0xFF173127);
  static Color get inkSoft =>
      _darkMode ? const Color(0xFFB6C4BC) : const Color(0xFF66776D);
  static Color get inkFaint =>
      _darkMode ? const Color(0xFF83968C) : const Color(0xFF97A59D);
  static Color get line =>
      _darkMode ? const Color(0xFF2B3B32) : const Color(0xFFE0E9E3);

  // Marque.
  static const brand = Color(0xFF138A55);
  static const brandDark = Color(0xFF0B633D);
  static const brandBright = Color(0xFF25A968);
  static Color get brandSoft =>
      _darkMode ? const Color(0xFF17372A) : const Color(0xFFE8F6EE);
  static const cyan = Color(0xFFD94A43);
  static const navy = Color(0xFF173D2E);
""",
    """  // Palette complète choisie par l'utilisateur.
  static String _appearanceTheme = 'green';

  static void setAppearanceTheme(String value) {
    const allowed = <String>{'green', 'red', 'white', 'black'};
    _appearanceTheme = allowed.contains(value) ? value : 'green';
  }

  static String get appearanceTheme => _appearanceTheme;
  static bool get _isGreen => _appearanceTheme == 'green';
  static bool get _isRed => _appearanceTheme == 'red';
  static bool get _isWhite => _appearanceTheme == 'white';
  static bool get _isBlack => _appearanceTheme == 'black';
  static bool get isDarkMode => !_isWhite;

  // Surfaces / texte.
  static Color get paper {
    if (_isRed) return const Color(0xFF2D0F10);
    if (_isWhite) return const Color(0xFFF5F8F6);
    if (_isBlack) return const Color(0xFF080A09);
    return const Color(0xFF0E2B1E);
  }

  static Color get paperAlt {
    if (_isRed) return const Color(0xFF3A1516);
    if (_isWhite) return const Color(0xFFEDF3EF);
    if (_isBlack) return const Color(0xFF101311);
    return const Color(0xFF143725);
  }

  static Color get card {
    if (_isRed) return const Color(0xFF481B1D);
    if (_isWhite) return const Color(0xFFFFFFFF);
    if (_isBlack) return const Color(0xFF171A18);
    return const Color(0xFF19452F);
  }

  static Color get ink =>
      _isWhite ? const Color(0xFF173127) : const Color(0xFFF6FAF8);
  static Color get inkSoft {
    if (_isRed) return const Color(0xFFE2C2C2);
    if (_isWhite) return const Color(0xFF66776D);
    if (_isBlack) return const Color(0xFFBDC5C0);
    return const Color(0xFFC3D8CD);
  }

  static Color get inkFaint {
    if (_isRed) return const Color(0xFFB98E90);
    if (_isWhite) return const Color(0xFF97A59D);
    if (_isBlack) return const Color(0xFF838D87);
    return const Color(0xFF8EAD9C);
  }

  static Color get line {
    if (_isRed) return const Color(0xFF733236);
    if (_isWhite) return const Color(0xFFE0E9E3);
    if (_isBlack) return const Color(0xFF303632);
    return const Color(0xFF2B6247);
  }

  // Marque / accents adaptatifs.
  static Color get brand {
    if (_isRed) return const Color(0xFFE2534D);
    if (_isGreen) return const Color(0xFF2CBF75);
    return const Color(0xFF138A55);
  }

  static Color get brandDark {
    if (_isRed) return const Color(0xFF9E312E);
    if (_isGreen) return const Color(0xFF0B633D);
    return const Color(0xFF0B633D);
  }

  static Color get brandBright {
    if (_isRed) return const Color(0xFFF36C66);
    if (_isGreen) return const Color(0xFF49D590);
    return const Color(0xFF25A968);
  }

  static Color get brandSoft {
    if (_isRed) return const Color(0xFF68282A);
    if (_isWhite) return const Color(0xFFE8F6EE);
    if (_isBlack) return const Color(0xFF173126);
    return const Color(0xFF205B3E);
  }

  static const cyan = Color(0xFFD94A43);

  static Color get navy {
    if (_isRed) return const Color(0xFF3A1012);
    if (_isWhite) return const Color(0xFF173D2E);
    if (_isBlack) return const Color(0xFF080A09);
    return const Color(0xFF0A3524);
  }
""",
    "four-palette AppColors",
)

# Shadows follow the chosen application accent rather than staying green.
theme_path = Path("lib/theme/app_theme.dart")
theme_text = theme_path.read_text()
theme_text = theme_text.replace(
    "color: const Color(0xFF174B36).withOpacity(0.055),",
    "color: AppColors.brandDark.withOpacity(0.08),",
)
theme_text = theme_text.replace(
    "color: const Color(0xFF174B36).withOpacity(0.09),",
    "color: AppColors.brandDark.withOpacity(0.12),",
)
theme_text = theme_text.replace(
    "color: const Color(0xFF0D2F22).withOpacity(0.18),",
    "color: AppColors.brandDark.withOpacity(0.22),",
)
theme_path.write_text(theme_text)

# ---------------------------------------------------------------------------
# Settings: replace "Mode sombre" switch by a 4-choice palette selector.
# ---------------------------------------------------------------------------
replace_once(
    "lib/screens/settings_screen.dart",
    """          SectionLabel('Apparence'),
          AppCard(
            padding: EdgeInsets.all(AppSpace.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.brandSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    appState.darkMode
                        ? Icons.dark_mode_rounded
                        : Icons.light_mode_rounded,
                    color: AppColors.brand,
                    size: 24,
                  ),
                ),
                SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mode sombre',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      SizedBox(height: 4),
                      Text(
                        appState.darkMode
                            ? 'Interface sombre activée sur cet appareil.'
                            : 'Réduire la luminosité de l’interface et utiliser des surfaces foncées.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.inkSoft),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 8),
                Switch(
                  value: appState.darkMode,
                  onChanged: _saving
                      ? null
                      : (enabled) =>
                          _run(() => appState.setDarkMode(enabled)),
                ),
              ],
            ),
          ),
""",
    """          SectionLabel('Apparence'),
          AppCard(
            padding: EdgeInsets.all(AppSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.brandSoft,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.palette_rounded,
                        color: AppColors.brand,
                        size: 24,
                      ),
                    ),
                    SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Thème de l’application',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Choisissez l’apparence générale. Le vert est le thème par défaut.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.inkSoft),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: AppSpace.md),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final itemWidth = (constraints.maxWidth - 10) / 2;
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        SizedBox(
                          width: itemWidth,
                          child: _AppearanceChoice(
                            label: 'Vert',
                            subtitle: 'Par défaut',
                            value: 'green',
                            swatch: Color(0xFF138A55),
                            selected: appState.appearanceTheme == 'green',
                            onTap: _saving
                                ? null
                                : () => _run(
                                      () => appState.setAppearanceTheme('green'),
                                    ),
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: _AppearanceChoice(
                            label: 'Rouge',
                            subtitle: 'Rouge profond',
                            value: 'red',
                            swatch: Color(0xFFD94A43),
                            selected: appState.appearanceTheme == 'red',
                            onTap: _saving
                                ? null
                                : () => _run(
                                      () => appState.setAppearanceTheme('red'),
                                    ),
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: _AppearanceChoice(
                            label: 'Blanc',
                            subtitle: 'Mode clair',
                            value: 'white',
                            swatch: Colors.white,
                            selected: appState.appearanceTheme == 'white',
                            onTap: _saving
                                ? null
                                : () => _run(
                                      () => appState.setAppearanceTheme('white'),
                                    ),
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: _AppearanceChoice(
                            label: 'Noir',
                            subtitle: 'Mode sombre',
                            value: 'black',
                            swatch: Color(0xFF101311),
                            selected: appState.appearanceTheme == 'black',
                            onTap: _saving
                                ? null
                                : () => _run(
                                      () => appState.setAppearanceTheme('black'),
                                    ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
""",
    "settings four-theme selector",
)

settings = Path("lib/screens/settings_screen.dart")
settings_text = settings.read_text()
appearance_widget = r'''

class _AppearanceChoice extends StatelessWidget {
  final String label;
  final String subtitle;
  final String value;
  final Color swatch;
  final bool selected;
  final VoidCallback? onTap;

  const _AppearanceChoice({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.swatch,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selectedBorder =
        value == 'white' ? AppColors.inkSoft : swatch;

    return Material(
      color: selected ? swatch.withOpacity(0.16) : AppColors.paperAlt,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? selectedBorder : AppColors.line,
              width: selected ? 1.8 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: swatch,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: value == 'white'
                        ? const Color(0xFFCBD6D0)
                        : swatch,
                    width: 1.2,
                  ),
                ),
              ),
              SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    SizedBox(height: 1),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(
                  Icons.check_circle_rounded,
                  size: 19,
                  color: AppColors.brand,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
'''
if "class _AppearanceChoice extends StatelessWidget" not in settings_text:
    settings.write_text(settings_text.rstrip() + appearance_widget + "\n")

# ---------------------------------------------------------------------------
# Login background should follow green/red/black, not one fixed old dark color.
# ---------------------------------------------------------------------------
auth = Path("lib/screens/auth_screen.dart")
auth_text = auth.read_text()
auth_text = auth_text.replace(
    """                  color: AppColors.isDarkMode
                      ? const Color(0xFF07110C).withOpacity(0.42 + (0.16 * t))
                      : Colors.white.withOpacity(0.05 + (0.10 * t)),""",
    """                  color: AppColors.isDarkMode
                      ? AppColors.paper.withOpacity(0.42 + (0.16 * t))
                      : Colors.white.withOpacity(0.05 + (0.10 * t)),""",
    1,
)
auth_text = auth_text.replace(
    """                colors: AppColors.isDarkMode
                    ? [
                        const Color(0xFF08120D).withOpacity(0.92),
                        const Color(0xFF0B1711).withOpacity(0.78),
                        const Color(0xFF101D17).withOpacity(0.86),
                        const Color(0xFF0C1410).withOpacity(0.96),
                      ]
                    : [""",
    """                colors: AppColors.isDarkMode
                    ? [
                        AppColors.paper.withOpacity(0.96),
                        AppColors.paperAlt.withOpacity(0.88),
                        AppColors.card.withOpacity(0.92),
                        AppColors.paper.withOpacity(0.98),
                      ]
                    : [""",
    1,
)
auth.write_text(auth_text)

# ---------------------------------------------------------------------------
# Brand colors are now runtime-adaptive, so old compile-time aliases/defaults
# must become runtime values.
# ---------------------------------------------------------------------------
for file_name, replacements in {
    "lib/screens/auth_screen.dart": [
        ("const _loginGreen = AppColors.brand;", "Color get _loginGreen => AppColors.brand;"),
        ("const _loginGreenDark = AppColors.brandDark;", "Color get _loginGreenDark => AppColors.brandDark;"),
    ],
    "lib/screens/forgot_password_screen.dart": [
        ("const _recoveryGreen = AppColors.brand;", "Color get _recoveryGreen => AppColors.brand;"),
        ("const _recoveryGreenDark = AppColors.brandDark;", "Color get _recoveryGreenDark => AppColors.brandDark;"),
    ],
    "lib/widgets/brand_identity.dart": [
        ("const _brandGreen = AppColors.brand;", "Color get _brandGreen => AppColors.brand;"),
    ],
}.items():
    p = Path(file_name)
    text = p.read_text()
    for old, new in replacements:
        if old in text:
            text = text.replace(old, new, 1)
        elif new not in text:
            raise SystemExit(f"V11.6.65: missing adaptive alias anchor {old!r} in {file_name}")
    p.write_text(text)

widgets = Path("lib/theme/widgets.dart")
w = widgets.read_text()
w = w.replace("  final Color foreground;\n", "  final Color? foreground;\n", 1)
w = w.replace("    this.foreground = AppColors.brand,\n", "    this.foreground,\n", 1)
# Pill text/icon foreground uses the nullable runtime brand fallback.
w = w.replace("color: foreground,", "color: foreground ?? AppColors.brand,")
widgets.write_text(w)

# Any const statement embedding one of the new runtime colors must be
# evaluated at runtime instead.
dynamic_tokens = (
    "AppColors.brand",
    "AppColors.brandDark",
    "AppColors.brandBright",
    "AppColors.brandSoft",
    "AppColors.navy",
    "AppColors.paper",
    "AppColors.paperAlt",
    "AppColors.card",
    "AppColors.ink",
    "AppColors.inkSoft",
    "AppColors.inkFaint",
    "AppColors.line",
    "_brandGreen",
    "_loginGreen",
    "_loginGreenDark",
    "_recoveryGreen",
    "_recoveryGreenDark",
)

for dart in Path("lib").rglob("*.dart"):
    text = dart.read_text()
    chunks = []
    start = 0
    changed = False
    for i, char in enumerate(text):
        if char != ";":
            continue
        chunk = text[start:i + 1]
        if "const " in chunk and any(token in chunk for token in dynamic_tokens):
            chunk = chunk.replace("const ", "")
            changed = True
        chunks.append(chunk)
        start = i + 1
    tail = text[start:]
    if "const " in tail and any(token in tail for token in dynamic_tokens):
        tail = tail.replace("const ", "")
        changed = True
    chunks.append(tail)
    if changed:
        dart.write_text("".join(chunks))

# Guardrails.
checks = {
    "lib/state/app_state.dart": [
        "String _appearanceTheme = 'green';",
        "String get appearanceTheme => _appearanceTheme;",
        "Future<void> setAppearanceTheme",
        "'appearanceTheme':_appearanceTheme",
    ],
    "lib/main.dart": [
        "context.select<AppState, String>",
        "AppColors.setAppearanceTheme(appearanceTheme)",
    ],
    "lib/theme/app_theme.dart": [
        "static String _appearanceTheme = 'green';",
        "static Color get brand",
        "if (_isRed) return const Color(0xFFE2534D);",
        "if (_isBlack) return const Color(0xFF080A09);",
    ],
    "lib/screens/settings_screen.dart": [
        "'Thème de l’application'",
        "appState.setAppearanceTheme('green')",
        "appState.setAppearanceTheme('red')",
        "appState.setAppearanceTheme('white')",
        "appState.setAppearanceTheme('black')",
        "class _AppearanceChoice extends StatelessWidget",
    ],
    "lib/screens/auth_screen.dart": [
        "AppColors.paper.withOpacity(0.96)",
        "Color get _loginGreen => AppColors.brand;",
    ],
}
for file_name, needles in checks.items():
    text = Path(file_name).read_text()
    for needle in needles:
        if needle not in text:
            raise SystemExit(f"V11.6.65: missing {needle!r} in {file_name}")

if TARGET not in pubspec.read_text():
    raise SystemExit("V11.6.65: version bump missing")

print("GardeFlow V11.6.65: four full-app appearance themes — green default, red, white, black")
