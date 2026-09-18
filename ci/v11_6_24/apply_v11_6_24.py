from pathlib import Path

EXPECTED = "version: 11.6.23+183"
TARGET = "version: 11.6.24+184"
LOGO = "assets/branding/gardeflow_logo.png"

pubspec = Path("pubspec.yaml")
pub = pubspec.read_text()
if EXPECTED not in pub:
    raise SystemExit("V11.6.24: base version mismatch")
pubspec.write_text(pub.replace(EXPECTED, TARGET, 1))

theme = Path("lib/theme/app_theme.dart")
t = theme.read_text()

replacements = {
    '/// GardeFlow V11.6.17 — identité visuelle "Medical Blue".':
        '/// GardeFlow V11.6.24 — identité visuelle vert / rouge.',
    '/// Le chrome de l\'application passe sur une identité bleu / blanc plus nette,':
        '/// Le chrome de l\'application utilise une identité vert / blanc, avec accent rouge,',
    'static const paper = Color(0xFFF4F7FB);':
        'static const paper = Color(0xFFF5F8F6);',
    'static const paperAlt = Color(0xFFECF2F9);':
        'static const paperAlt = Color(0xFFEDF3EF);',
    'static const ink = Color(0xFF10213B);':
        'static const ink = Color(0xFF173127);',
    'static const inkSoft = Color(0xFF62758D);':
        'static const inkSoft = Color(0xFF66776D);',
    'static const inkFaint = Color(0xFF96A5B7);':
        'static const inkFaint = Color(0xFF97A59D);',
    'static const line = Color(0xFFE1E9F2);':
        'static const line = Color(0xFFE0E9E3);',
    'static const brand = Color(0xFF0968D8);':
        'static const brand = Color(0xFF138A55);',
    'static const brandDark = Color(0xFF064A9D);':
        'static const brandDark = Color(0xFF0B633D);',
    'static const brandBright = Color(0xFF139BFF);':
        'static const brandBright = Color(0xFF25A968);',
    'static const brandSoft = Color(0xFFE8F2FF);':
        'static const brandSoft = Color(0xFFE8F6EE);',
    'static const cyan = Color(0xFF19B8D7);':
        'static const cyan = Color(0xFFD94A43);',
    'static const navy = Color(0xFF0A2D59);':
        'static const navy = Color(0xFF173D2E);',
    'const Color(0xFFBCD6F3)':
        'const Color(0xFFBFDCCA)',
    'const Color(0xFFD8E8F9)':
        'const Color(0xFFD7EBDD)',
    'const Color(0xFF0A3D72)':
        'const Color(0xFF174B36)',
    'const Color(0xFF061C38)':
        'const Color(0xFF0D2F22)',
}

for old, new in replacements.items():
    if old in t:
        t = t.replace(old, new)
    else:
        print(f"V11.6.24 theme warning: missing {old}")

theme.write_text(t)

widgets = Path("lib/theme/widgets.dart")
w = widgets.read_text()

old_title_logo = """          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.brandBright, AppColors.brand],
              ),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(Icons.add_rounded, color: Colors.white, size: 24),
          ),"""

new_title_logo = f"""          Container(
            width: 36,
            height: 36,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: AppColors.line),
              boxShadow: AppShadow.low,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Image.asset(
                '{LOGO}',
                fit: BoxFit.contain,
              ),
            ),
          ),"""

if old_title_logo not in w:
    raise SystemExit("V11.6.24: GardeFlowTitle branding block not found")
w = w.replace(old_title_logo, new_title_logo, 1)
widgets.write_text(w)

home = Path("lib/screens/home_screen.dart")
h = home.read_text()

old_home_logo = """          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.brand,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AppColors.brand.withOpacity(0.18),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: const Icon(
              Icons.add_rounded,
              size: 25,
              color: Colors.white,
            ),
          ),"""

new_home_logo = f"""          Container(
            width: 38,
            height: 38,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.line),
              boxShadow: [
                BoxShadow(
                  color: AppColors.navy.withOpacity(0.10),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                '{LOGO}',
                fit: BoxFit.contain,
              ),
            ),
          ),"""

if old_home_logo not in h:
    raise SystemExit("V11.6.24: main GardeFlow logo block not found")
h = h.replace(old_home_logo, new_home_logo, 1)
home.write_text(h)

notifications = Path("lib/screens/notifications_screen.dart")
n = notifications.read_text()

old_notif_mark = """              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.brandSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.notifications_active_outlined,
                  color: AppColors.brand,
                  size: 22,
                ),
              ),"""

new_notif_mark = f"""              Container(
                width: 42,
                height: 42,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.line),
                  boxShadow: AppShadow.low,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: Image.asset(
                    '{LOGO}',
                    fit: BoxFit.contain,
                  ),
                ),
              ),"""

if old_notif_mark in n:
    n = n.replace(old_notif_mark, new_notif_mark, 1)
else:
    print("V11.6.24 warning: notifications branding block not found")

notifications.write_text(n)

print("GardeFlow V11.6.24: thème vert/rouge + vrai logo global")
