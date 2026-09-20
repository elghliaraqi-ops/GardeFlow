from pathlib import Path

EXPECTED = "version: 11.6.65+225"
TARGET = "version: 11.6.66+226"


def replace_once(path: str, old: str, new: str, label: str) -> None:
    p = Path(path)
    text = p.read_text()
    if old not in text:
        if new in text:
            return
        raise SystemExit(f"V11.6.66: {label} anchor missing in {path}")
    p.write_text(text.replace(old, new, 1))


pubspec = Path("pubspec.yaml")
pub = pubspec.read_text()
if EXPECTED not in pub:
    if TARGET not in pub:
        raise SystemExit("V11.6.66: base version mismatch")
else:
    pubspec.write_text(pub.replace(EXPECTED, TARGET, 1))

# ---------------------------------------------------------------------------
# 1) Splash screen: high-contrast branding/slogans on the bright hospital
#    background. Keep the logo and GardeFlow identity but strengthen font size,
#    weight and colors so all slogans remain readable.
# ---------------------------------------------------------------------------
replace_once(
    "lib/screens/splash_screen.dart",
    """                            GardeFlowBrandBlock(),
                            SizedBox(height: 30),
                            Text(
                              'AU SERVICE DES SOIGNANTS\\nAU SERVICE DES PATIENTS',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 10.5,
                                height: 1.55,
                                letterSpacing: 3.0,
                                color: AppColors.brandDark,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
""",
    """                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GardeFlowLogo(size: 108),
                                SizedBox(height: 18),
                                RichText(
                                  textAlign: TextAlign.center,
                                  text: TextSpan(
                                    style: TextStyle(
                                      fontFamily: 'SpaceGrotesk',
                                      fontSize: 48,
                                      height: 1.0,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -1.8,
                                    ),
                                    children: [
                                      TextSpan(
                                        text: 'Garde',
                                        style: TextStyle(
                                          color: Color(0xFF0B633D),
                                        ),
                                      ),
                                      TextSpan(
                                        text: 'Flow',
                                        style: TextStyle(
                                          color: Color(0xFFD94A43),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(height: 14),
                                Text(
                                  'Planning médical intelligent',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: 'SpaceGrotesk',
                                    fontSize: 16.5,
                                    height: 1.15,
                                    letterSpacing: 2.0,
                                    color: Color(0xFF315C49),
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                SizedBox(height: 18),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 58,
                                      height: 1.6,
                                      color: Color(0xFF62B88D),
                                    ),
                                    SizedBox(width: 12),
                                    Icon(
                                      Icons.monitor_heart_outlined,
                                      size: 24,
                                      color: Color(0xFF2F9B67),
                                    ),
                                    SizedBox(width: 12),
                                    Container(
                                      width: 58,
                                      height: 1.6,
                                      color: Color(0xFF62B88D),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 15),
                                Text(
                                  'LE PLANNING DE GARDE POUR GARDER LE FLOW',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: 'SpaceGrotesk',
                                    fontSize: 10.5,
                                    height: 1.3,
                                    letterSpacing: 2.0,
                                    color: Color(0xFF466D5B),
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 26),
                            Text(
                              'AU SERVICE DES SOIGNANTS\\nAU SERVICE DES PATIENTS',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'SpaceGrotesk',
                                fontSize: 12.0,
                                height: 1.55,
                                letterSpacing: 2.35,
                                color: Color(0xFF0B633D),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
""",
    "splash high-contrast branding",
)

# ---------------------------------------------------------------------------
# 2) Past months: make the tile tray visibly and functionally unavailable.
#    placeShift() already blocks past dates; this adds a month-level UI lock.
# ---------------------------------------------------------------------------
replace_once(
    "lib/screens/home_screen.dart",
    """  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
""",
    """  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final visibleMonth = appState.visibleMonth;
    final visibleMonthStart = DateTime(visibleMonth.year, visibleMonth.month, 1);
    final currentMonthStart = DateTime(now.year, now.month, 1);
    final isPastMonth = visibleMonthStart.isBefore(currentMonthStart);

    return Column(
      children: [
""",
    "planning past-month state",
)

replace_once(
    "lib/screens/home_screen.dart",
    """        _ShiftTray(
          enabled: appState.canEditMyPlanningMonth(appState.visibleMonth),
        ),
""",
    """        _ShiftTray(
          enabled: !isPastMonth &&
              appState.canEditMyPlanningMonth(appState.visibleMonth),
        ),
""",
    "disable tile tray for past months",
)

replace_once(
    "lib/screens/home_screen.dart",
    """    final monthStatus =
        appState.myPlanningMonth(month)?.status ?? PlanningMonthStatus.draft;
    final monthEditable = appState.canEditMyPlanningMonth(month);
    final monthApproved = monthStatus == PlanningMonthStatus.approved;
""",
    """    final monthStatus =
        appState.myPlanningMonth(month)?.status ?? PlanningMonthStatus.draft;
    final now = DateTime.now();
    final currentMonthStart = DateTime(now.year, now.month, 1);
    final viewedMonthStart = DateTime(month.year, month.month, 1);
    final isPastMonth = viewedMonthStart.isBefore(currentMonthStart);
    final monthEditable =
        !isPastMonth && appState.canEditMyPlanningMonth(month);
    final monthApproved = monthStatus == PlanningMonthStatus.approved;
""",
    "past month calendar lock",
)

# ---------------------------------------------------------------------------
# 3) Reminder settings become their own dedicated page: no theme selector and
#    no signature/copyright there.
# ---------------------------------------------------------------------------
appearance_block = """          SectionLabel('Apparence'),
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

          SizedBox(height: AppSpace.xl),
"""
settings = Path("lib/screens/settings_screen.dart")
settings_text = settings.read_text()
if appearance_block not in settings_text:
    raise SystemExit("V11.6.66: reminder appearance block missing")
settings_text = settings_text.replace(
    appearance_block,
    """          SectionLabel('Rappels et alarme'),
""",
    1,
)
settings_text = settings_text.replace(
    "title: GardeFlowTitle('Alarme de garde'),",
    "title: GardeFlowTitle('Rappels de garde'),",
    1,
)
settings.write_text(settings_text)

# Dedicated application-settings page with theme selector + signature/footer.
settings = Path("lib/screens/settings_screen.dart")
settings_text = settings.read_text()
app_settings_class = r'''

class ApplicationSettingsScreen extends StatelessWidget {
  const ApplicationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    Widget choice({
      required String label,
      required String subtitle,
      required String value,
      required Color swatch,
    }) {
      return _AppearanceChoice(
        label: label,
        subtitle: subtitle,
        value: value,
        swatch: swatch,
        selected: appState.appearanceTheme == value,
        onTap: () {
          appState.setAppearanceTheme(value);
        },
      );
    }

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: GardeFlowTitle('Réglages de l’application'),
      ),
      body: ListView(
        physics: BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          AppSpace.lg,
          AppSpace.md,
          AppSpace.lg,
          34,
        ),
        children: [
          SectionLabel('Thème de l’application'),
          AppCard(
            padding: EdgeInsets.all(AppSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: AppColors.brandSoft,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.palette_rounded,
                        color: AppColors.brand,
                        size: 25,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Choisissez l’apparence générale de GardeFlow. Le vert reste le thème par défaut.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.inkSoft,
                              height: 1.4,
                            ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: AppSpace.lg),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final itemWidth = (constraints.maxWidth - 10) / 2;
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        SizedBox(
                          width: itemWidth,
                          child: choice(
                            label: 'Vert',
                            subtitle: 'Par défaut',
                            value: 'green',
                            swatch: Color(0xFF138A55),
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: choice(
                            label: 'Rouge',
                            subtitle: 'Rouge profond',
                            value: 'red',
                            swatch: Color(0xFFD94A43),
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: choice(
                            label: 'Blanc',
                            subtitle: 'Ancien mode clair',
                            value: 'white',
                            swatch: Colors.white,
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: choice(
                            label: 'Noir',
                            subtitle: 'Mode sombre',
                            value: 'black',
                            swatch: Color(0xFF101311),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          SizedBox(height: 34),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 280,
                  height: 126,
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Image.asset(
                    'assets/branding/elghali_signature.webp',
                    width: 260,
                    height: 112,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    gaplessPlayback: true,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Elghali Production © 2026',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.inkSoft,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.25,
                  ),
                ),
                SizedBox(height: 7),
                Text(
                  'Version 11.6.66',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.inkFaint,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
'''
if "class ApplicationSettingsScreen extends StatelessWidget" not in settings_text:
    settings.write_text(settings_text.rstrip() + app_settings_class + "\n")

# ---------------------------------------------------------------------------
# 4) Profile navigation: separate app settings from reminder settings and move
#    the signature/copyright out of the profile into app settings.
# ---------------------------------------------------------------------------
replace_once(
    "lib/screens/profile_screen.dart",
    """            tooltip: 'Réglages',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => SettingsScreen()),
            ),
""",
    """            tooltip: 'Réglages de l’application',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ApplicationSettingsScreen(),
              ),
            ),
""",
    "profile top settings action",
)

replace_once(
    "lib/screens/profile_screen.dart",
    """            _ProfileMenuItem(
              icon: Icons.tune_rounded,
              title: 'Réglages',
              subtitle: 'Rappels, alarme longue et notifications',
              color: AppColors.brand,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsScreen())),
            ),
""",
    """            _ProfileMenuItem(
              icon: Icons.settings_suggest_rounded,
              title: 'Réglages de l’application',
              subtitle: 'Thème, apparence et informations',
              color: AppColors.brand,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ApplicationSettingsScreen(),
                ),
              ),
            ),
            _ProfileMenuItem(
              icon: Icons.alarm_rounded,
              title: 'Rappels de garde',
              subtitle: 'Horaires, alarme longue et notifications Android',
              color: AppColors.cyan,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(reminderFocus: true),
                ),
              ),
            ),
""",
    "separate profile settings rows",
)

profile = Path("lib/screens/profile_screen.dart")
p = profile.read_text()
signature_block = """        SizedBox(height: 28),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 280,
                height: 126,
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.line),
                ),
                child: Image.asset(
                  'assets/branding/elghali_signature.webp',
                  width: 260,
                  height: 112,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  gaplessPlayback: true,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Elghali Production © 2026',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.inkFaint,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.25,
                ),
              ),
            ],
          ),
        ),
"""
if signature_block not in p:
    raise SystemExit("V11.6.66: profile signature footer anchor missing")
p = p.replace(signature_block, "", 1)
profile.write_text(p)

# Guardrails.
checks = {
    "lib/screens/splash_screen.dart": [
        "'Planning médical intelligent'",
        "'LE PLANNING DE GARDE POUR GARDER LE FLOW'",
        "fontSize: 12.0",
        "fontWeight: FontWeight.w900",
        "Color(0xFF0B633D)",
    ],
    "lib/screens/home_screen.dart": [
        "final isPastMonth = visibleMonthStart.isBefore(currentMonthStart);",
        "enabled: !isPastMonth",
        "final monthEditable =",
        "!isPastMonth && appState.canEditMyPlanningMonth(month)",
    ],
    "lib/screens/settings_screen.dart": [
        "GardeFlowTitle('Rappels de garde')",
        "class ApplicationSettingsScreen extends StatelessWidget",
        "GardeFlowTitle('Réglages de l’application')",
        "'Elghali Production © 2026'",
        "'Version 11.6.66'",
        "appState.setAppearanceTheme(value)",
    ],
    "lib/screens/profile_screen.dart": [
        "'Réglages de l’application'",
        "'Rappels de garde'",
        "ApplicationSettingsScreen()",
        "SettingsScreen(reminderFocus: true)",
    ],
}
for file_name, needles in checks.items():
    text = Path(file_name).read_text()
    for needle in needles:
        if needle not in text:
            raise SystemExit(f"V11.6.66: missing {needle!r} in {file_name}")

profile_final = Path("lib/screens/profile_screen.dart").read_text()
if "assets/branding/elghali_signature.webp" in profile_final:
    raise SystemExit("V11.6.66: signature must no longer be shown on profile")
if "SectionLabel('Apparence')" in Path("lib/screens/settings_screen.dart").read_text().split("class ApplicationSettingsScreen")[0]:
    raise SystemExit("V11.6.66: appearance still present in reminder settings")

if TARGET not in pubspec.read_text():
    raise SystemExit("V11.6.66: version bump missing")

print("GardeFlow V11.6.66: readable splash + past-month tile lock + separate reminder/app settings")
