from pathlib import Path

EXPECTED = "version: 11.6.57+217"
TARGET = "version: 11.6.58+218"

pubspec = Path("pubspec.yaml")
pub = pubspec.read_text()
if EXPECTED not in pub:
    raise SystemExit("V11.6.58: base version mismatch")
pubspec.write_text(pub.replace(EXPECTED, TARGET, 1))

# ---------------------------------------------------------------------------
# Dark mode becomes the default appearance.
# Existing installations are migrated once to dark mode; after that, the
# user's manual setting remains persistent normally.
# ---------------------------------------------------------------------------
state = Path("lib/state/app_state.dart")
s = state.read_text()

old = """  bool _darkMode = false;
  bool get darkMode => _darkMode;"""
new = """  bool _darkMode = true;
  bool _darkDefaultAppliedV58 = false;
  bool get darkMode => _darkMode;"""
if old not in s:
    raise SystemExit("V11.6.58: dark-mode default field anchor missing")
s = s.replace(old, new, 1)

old = """'planningCounter':_planningCounter,'exchangeCounter':_exchangeCounter,'leaveCounter':_leaveCounter,'reminderCounter':_reminderCounter,'darkMode':_darkMode,"""
new = """'planningCounter':_planningCounter,'exchangeCounter':_exchangeCounter,'leaveCounter':_leaveCounter,'reminderCounter':_reminderCounter,'darkMode':_darkMode,'darkDefaultAppliedV58':true,"""
if old not in s:
    raise SystemExit("V11.6.58: persisted dark-mode anchor missing")
s = s.replace(old, new, 1)

old = """_delayMinutes=(j['delayMinutes'] as num?)?.toInt()??60;_notificationsOn=j['notificationsOn'] as bool? ?? true;_darkMode=j['darkMode'] as bool? ?? false;"""
new = """_delayMinutes=(j['delayMinutes'] as num?)?.toInt()??60;_notificationsOn=j['notificationsOn'] as bool? ?? true;_darkDefaultAppliedV58=j['darkDefaultAppliedV58'] as bool? ?? false;_darkMode=_darkDefaultAppliedV58 ? (j['darkMode'] as bool? ?? true) : true;_darkDefaultAppliedV58=true;"""
if old not in s:
    raise SystemExit("V11.6.58: restored dark-mode anchor missing")
s = s.replace(old, new, 1)

state.write_text(s)


# ---------------------------------------------------------------------------
# Planning calendar: in dark mode the small date badge on a guard must not
# remain white while its text becomes white. Use an adaptive dark surface.
# ---------------------------------------------------------------------------
home = Path("lib/screens/home_screen.dart")
s = home.read_text()

old = """                      color: isToday
                          ? AppColors.brand
                          : shift != null
                              ? Colors.white.withOpacity(0.78)
                              : Colors.transparent,"""
new = """                      color: isToday
                          ? AppColors.brand
                          : shift != null
                              ? (AppColors.isDarkMode
                                  ? AppColors.paperAlt.withOpacity(0.96)
                                  : Colors.white.withOpacity(0.78))
                              : Colors.transparent,"""
if old not in s:
    raise SystemExit("V11.6.58: planning calendar date badge anchor missing")
s = s.replace(old, new, 1)
home.write_text(s)


# ---------------------------------------------------------------------------
# Annuaire categories: the "Tous" category previously used AppColors.ink as
# its active background. In dark mode AppColors.ink is white, producing
# white text on white. Keep the active chip branded green instead.
# ---------------------------------------------------------------------------
directory = Path("lib/screens/directory_screen.dart")
s = directory.read_text()

old = """                          color: AppColors.ink,
                          textColor: Colors.white,"""
new = """                          color: AppColors.brand,
                          textColor: Colors.white,"""
if old not in s:
    raise SystemExit("V11.6.58: directory all-category chip anchor missing")
s = s.replace(old, new, 1)
directory.write_text(s)


# ---------------------------------------------------------------------------
# Password recovery still contained hardcoded white cards/fields. They are
# converted to the adaptive card surface to avoid white-on-white text.
# ---------------------------------------------------------------------------
forgot = Path("lib/screens/forgot_password_screen.dart")
s = forgot.read_text()

if "        fillColor: Colors.white," not in s:
    raise SystemExit("V11.6.58: forgot-password input white surface missing")
s = s.replace(
    "        fillColor: Colors.white,",
    "        fillColor: AppColors.card,",
    1,
)

old_card = """                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),"""
new_card = """                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(24),"""
if old_card not in s:
    raise SystemExit("V11.6.58: forgot-password white card anchor missing")
s = s.replace(old_card, new_card, 1)
forgot.write_text(s)


# ---------------------------------------------------------------------------
# Global theme hardening:
# - picker dates always use readable adaptive text/surfaces
# - dropdown/menu surfaces follow dark mode
# - generic unselected chips have readable dark-mode labels
# ---------------------------------------------------------------------------
theme = Path("lib/theme/app_theme.dart")
s = theme.read_text()

old_chip = """labelStyle: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 11.5, color: AppColors.brandDark),"""
new_chip = """labelStyle: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 11.5, color: isDark ? AppColors.ink : AppColors.brandDark),"""
if old_chip not in s:
    raise SystemExit("V11.6.58: chip label-style anchor missing")
s = s.replace(old_chip, new_chip, 1)

old_popup = """      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.card,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdR),
      ),"""
new_popup = """      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.card,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdR),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: AppColors.brandDark,
        headerForegroundColor: Colors.white,
        weekdayStyle: TextStyle(
          color: AppColors.inkSoft,
          fontWeight: FontWeight.w800,
        ),
        dayStyle: TextStyle(
          color: AppColors.ink,
          fontWeight: FontWeight.w700,
        ),
        dayForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          if (states.contains(WidgetState.disabled)) return AppColors.inkFaint;
          return AppColors.ink;
        }),
        dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.brand;
          return Colors.transparent;
        }),
        todayForegroundColor: WidgetStatePropertyAll(AppColors.brand),
        todayBorder: BorderSide(color: AppColors.brand),
        yearForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return AppColors.ink;
        }),
        yearBackgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.brand;
          return Colors.transparent;
        }),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: TextStyle(
          color: AppColors.ink,
          fontWeight: FontWeight.w600,
        ),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(AppColors.card),
          surfaceTintColor:
              const WidgetStatePropertyAll(Colors.transparent),
        ),
      ),"""
if old_popup not in s:
    raise SystemExit("V11.6.58: popup-menu theme anchor missing")
s = s.replace(old_popup, new_popup, 1)

old_base = """      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.paper,
      splashFactory: InkSparkle.splashFactory,"""
new_base = """      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.paper,
      canvasColor: AppColors.card,
      dividerColor: AppColors.line,
      splashFactory: InkSparkle.splashFactory,"""
if old_base not in s:
    raise SystemExit("V11.6.58: ThemeData base anchor missing")
s = s.replace(old_base, new_base, 1)

theme.write_text(s)


checks = {
    "lib/state/app_state.dart": [
        "bool _darkMode = true",
        "darkDefaultAppliedV58",
        "_darkMode=_darkDefaultAppliedV58 ?",
    ],
    "lib/screens/home_screen.dart": [
        "AppColors.isDarkMode",
        "AppColors.paperAlt.withOpacity(0.96)",
    ],
    "lib/screens/directory_screen.dart": [
        "label: 'Tous'",
        "color: AppColors.brand",
    ],
    "lib/screens/forgot_password_screen.dart": [
        "fillColor: AppColors.card",
        "color: AppColors.card",
    ],
    "lib/theme/app_theme.dart": [
        "datePickerTheme: DatePickerThemeData",
        "dropdownMenuTheme: DropdownMenuThemeData",
        "canvasColor: AppColors.card",
        "isDark ? AppColors.ink : AppColors.brandDark",
    ],
}

for file_name, needles in checks.items():
    text = Path(file_name).read_text()
    for needle in needles:
        if needle not in text:
            raise SystemExit(f"V11.6.58: missing {needle!r} in {file_name}")

print("GardeFlow V11.6.58: dark mode default + calendar/directory/global contrast fixes")
