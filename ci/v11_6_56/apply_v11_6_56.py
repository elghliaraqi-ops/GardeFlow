from pathlib import Path

EXPECTED = "version: 11.6.55+215"
TARGET = "version: 11.6.56+216"

pubspec = Path("pubspec.yaml")
pub = pubspec.read_text()
if EXPECTED not in pub:
    raise SystemExit("V11.6.56: base version mismatch")
pubspec.write_text(pub.replace(EXPECTED, TARGET, 1))

# ---------------------------------------------------------------------------
# AppState: persistent device-level dark mode preference.
# ---------------------------------------------------------------------------
state = Path("lib/state/app_state.dart")
s = state.read_text()

anchor = """  bool get backendEnabled => SupabaseBackendService.instance.enabled;
  String get backendModeLabel => backendEnabled ? 'Supabase connecté' : 'Mode local';
"""
replacement = """  bool _darkMode = false;
  bool get darkMode => _darkMode;

  Future<void> setDarkMode(bool enabled) async {
    if (_darkMode == enabled) return;
    _darkMode = enabled;
    await _persistNow();
    notifyListeners();
  }

  bool get backendEnabled => SupabaseBackendService.instance.enabled;
  String get backendModeLabel => backendEnabled ? 'Supabase connecté' : 'Mode local';
"""
if anchor not in s:
    raise SystemExit("V11.6.56: AppState dark mode insertion anchor missing")
s = s.replace(anchor, replacement, 1)

old_json = """'planningCounter':_planningCounter,'exchangeCounter':_exchangeCounter,'leaveCounter':_leaveCounter,'reminderCounter':_reminderCounter,"""
new_json = """'planningCounter':_planningCounter,'exchangeCounter':_exchangeCounter,'leaveCounter':_leaveCounter,'reminderCounter':_reminderCounter,'darkMode':_darkMode,"""
if old_json not in s:
    raise SystemExit("V11.6.56: AppState JSON anchor missing")
s = s.replace(old_json, new_json, 1)

restore_anchor = """    _delayMinutes=(j['delayMinutes'] as num?)?.toInt()??60;_notificationsOn=j['notificationsOn'] as bool? ?? true;"""
restore_new = """    _delayMinutes=(j['delayMinutes'] as num?)?.toInt()??60;_notificationsOn=j['notificationsOn'] as bool? ?? true;_darkMode=j['darkMode'] as bool? ?? false;"""
if restore_anchor not in s:
    raise SystemExit("V11.6.56: AppState restore anchor missing")
s = s.replace(restore_anchor, restore_new, 1)
state.write_text(s)


# ---------------------------------------------------------------------------
# Root app: switch the complete application theme immediately.
# ---------------------------------------------------------------------------
main = Path("lib/main.dart")
s = main.read_text()

old_build = """  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: huimNavigatorKey,
      scaffoldMessengerKey: huimMessengerKey,
      title: 'GardeFlow',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),"""
new_build = """  @override
  Widget build(BuildContext context) {
    final darkMode = context.select<AppState, bool>((state) => state.darkMode);
    AppColors.setDarkMode(darkMode);

    return MaterialApp(
      navigatorKey: huimNavigatorKey,
      scaffoldMessengerKey: huimMessengerKey,
      title: 'GardeFlow',
      debugShowCheckedModeBanner: false,
      theme: darkMode ? AppTheme.dark() : AppTheme.light(),
      themeAnimationDuration: const Duration(milliseconds: 220),
      themeAnimationCurve: Curves.easeOutCubic,"""
if old_build not in s:
    raise SystemExit("V11.6.56: MaterialApp theme anchor missing")
s = s.replace(old_build, new_build, 1)
main.write_text(s)


# ---------------------------------------------------------------------------
# Theme: adaptive neutral surfaces/text while preserving medical guard colors.
# ---------------------------------------------------------------------------
theme = Path("lib/theme/app_theme.dart")
s = theme.read_text()

old_neutral = """  // Surfaces / texte.
  static const paper = Color(0xFFF5F8F6);
  static const paperAlt = Color(0xFFEDF3EF);
  static const card = Color(0xFFFFFFFF);
  static const ink = Color(0xFF173127);
  static const inkSoft = Color(0xFF66776D);
  static const inkFaint = Color(0xFF97A59D);
  static const line = Color(0xFFE0E9E3);"""
new_neutral = """  // Surfaces / texte adaptatifs.
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
      _darkMode ? const Color(0xFF2B3B32) : const Color(0xFFE0E9E3);"""
if old_neutral not in s:
    raise SystemExit("V11.6.56: AppColors neutral palette anchor missing")
s = s.replace(old_neutral, new_neutral, 1)

old_brand_soft = "  static const brandSoft = Color(0xFFE8F6EE);"
new_brand_soft = """  static Color get brandSoft =>
      _darkMode ? const Color(0xFF17372A) : const Color(0xFFE8F6EE);"""
if old_brand_soft not in s:
    raise SystemExit("V11.6.56: brandSoft anchor missing")
s = s.replace(old_brand_soft, new_brand_soft, 1)

old_theme_start = """  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.brand,
      brightness: Brightness.light,"""
new_theme_start = """  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.brand,
      brightness: brightness,"""
if old_theme_start not in s:
    raise SystemExit("V11.6.56: AppTheme light() anchor missing")
s = s.replace(old_theme_start, new_theme_start, 1)

s = s.replace(
    "        systemOverlayStyle: SystemUiOverlayStyle.dark,",
    """        systemOverlayStyle:
            (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
                .copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: AppColors.card,
          systemNavigationBarIconBrightness:
              isDark ? Brightness.light : Brightness.dark,
        ),""",
    1,
)

s = s.replace(
    "side: const BorderSide(color: Color(0xFFBCD6F3), width: 1.2),",
    "side: BorderSide(color: AppColors.line, width: 1.2),",
    1,
)
s = s.replace(
    "side: const BorderSide(color: Color(0xFFD8E8F9)),",
    "side: BorderSide(color: AppColors.line),",
    1,
)
s = s.replace(
    "side: const BorderSide(color: Color(0xFFD8E8F9)),",
    "side: BorderSide(color: AppColors.line),",
    1,
)
s = s.replace(
    "          return const Color(0xFFCBD6E2);",
    "          return isDark ? const Color(0xFF46554D) : const Color(0xFFCBD6E2);",
    1,
)

theme.write_text(s)


# ---------------------------------------------------------------------------
# Réglages: explicit switch controlled by AppState.
# ---------------------------------------------------------------------------
settings = Path("lib/screens/settings_screen.dart")
s = settings.read_text()

list_anchor = """        children: [
          Container(
            padding: const EdgeInsets.all(AppSpace.lg),"""
appearance = """        children: [
          const SectionLabel('Apparence'),
          AppCard(
            padding: const EdgeInsets.all(AppSpace.lg),
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
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mode sombre',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
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
                const SizedBox(width: 8),
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

          const SizedBox(height: AppSpace.xl),
          Container(
            padding: const EdgeInsets.all(AppSpace.lg),"""
if list_anchor not in s:
    raise SystemExit("V11.6.56: settings appearance insertion anchor missing")
s = s.replace(list_anchor, appearance, 1)
settings.write_text(s)


# ---------------------------------------------------------------------------
# Shared widgets: keep Pill const-compatible while its default background
# becomes adaptive at render time.
# ---------------------------------------------------------------------------
widgets = Path("lib/theme/widgets.dart")
s = widgets.read_text()
old_pill = """  final Color background;
  final Color foreground;
  final double fontSize;

  const Pill({
    super.key,
    required this.text,
    this.icon,
    this.background = AppColors.brandSoft,
    this.foreground = AppColors.brand,
    this.fontSize = 11,
  });"""
new_pill = """  final Color? background;
  final Color foreground;
  final double fontSize;

  const Pill({
    super.key,
    required this.text,
    this.icon,
    this.background,
    this.foreground = AppColors.brand,
    this.fontSize = 11,
  });"""
if old_pill not in s:
    raise SystemExit("V11.6.56: Pill adaptive default anchor missing")
s = s.replace(old_pill, new_pill, 1)
s = s.replace(
    "        color: background,",
    "        color: background ?? AppColors.brandSoft,",
    1,
)
widgets.write_text(s)


# ---------------------------------------------------------------------------
# Neutral AppColors are runtime-adaptive getters. Any const expression that
# embeds one of those colors must become runtime-built. We only de-const
# semicolon-delimited Dart expressions containing an adaptive color.
# ---------------------------------------------------------------------------
adaptive_tokens = (
    "AppColors.paper",
    "AppColors.paperAlt",
    "AppColors.card",
    "AppColors.ink",
    "AppColors.inkSoft",
    "AppColors.inkFaint",
    "AppColors.line",
    "AppColors.brandSoft",
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
        if "const " in chunk and any(token in chunk for token in adaptive_tokens):
            chunk = chunk.replace("const ", "")
            changed = True
        chunks.append(chunk)
        start = i + 1
    tail = text[start:]
    if "const " in tail and any(token in tail for token in adaptive_tokens):
        tail = tail.replace("const ", "")
        changed = True
    chunks.append(tail)
    if changed:
        dart.write_text("".join(chunks))

# A local const variable becomes a normal final variable when its adaptive
# color is evaluated at runtime.
theme_text = theme.read_text()
theme_text = theme_text.replace(
    "    displayBase = TextStyle(",
    "    final displayBase = TextStyle(",
    1,
)
theme.write_text(theme_text)

checks = {
    "lib/main.dart": [
        "context.select<AppState, bool>",
        "AppColors.setDarkMode(darkMode)",
        "AppTheme.dark()",
    ],
    "lib/state/app_state.dart": [
        "bool _darkMode = false",
        "Future<void> setDarkMode",
        "'darkMode':_darkMode",
    ],
    "lib/theme/app_theme.dart": [
        "static ThemeData dark()",
        "0xFF0C1410",
        "systemNavigationBarIconBrightness",
    ],
    "lib/screens/settings_screen.dart": [
        "SectionLabel('Apparence')",
        "'Mode sombre'",
        "appState.setDarkMode",
    ],
}

for file_name, needles in checks.items():
    text = Path(file_name).read_text()
    for needle in needles:
        if needle not in text:
            raise SystemExit(f"V11.6.56: missing {needle!r} in {file_name}")

print("GardeFlow V11.6.56: persistent dark mode toggle in Réglages + adaptive application palette")
