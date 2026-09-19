from pathlib import Path
import re

EXPECTED = "version: 11.6.59+219"
TARGET = "version: 11.6.60+220"

pubspec = Path("pubspec.yaml")
pub = pubspec.read_text()
if EXPECTED not in pub:
    raise SystemExit("V11.6.60: base version mismatch")
pubspec.write_text(pub.replace(EXPECTED, TARGET, 1))

auth = Path("lib/screens/auth_screen.dart")
s = auth.read_text()

# ---------------------------------------------------------------------------
# Login screen dark-mode contrast hardening.
# The login background was still forced to a light glass composition while
# the global dark theme turned text white, causing white-on-white content.
# ---------------------------------------------------------------------------
old_blur = """                child: Container(
                  color: Colors.white.withOpacity(0.05 + (0.10 * t)),
                ),"""
new_blur = """                child: Container(
                  color: AppColors.isDarkMode
                      ? const Color(0xFF07110C).withOpacity(0.42 + (0.16 * t))
                      : Colors.white.withOpacity(0.05 + (0.10 * t)),
                ),"""
if old_blur not in s:
    raise SystemExit("V11.6.60: login blur overlay anchor missing")
s = s.replace(old_blur, new_blur, 1)

old_gradient = """                colors: [
                  Colors.white.withOpacity(0.68),
                  Colors.white.withOpacity(0.34),
                  Colors.white.withOpacity(0.54),
                  const Color(0xFFEAF7EF).withOpacity(0.78),
                ],
                stops: const [0, 0.28, 0.70, 1],"""
new_gradient = """                colors: AppColors.isDarkMode
                    ? [
                        const Color(0xFF08120D).withOpacity(0.92),
                        const Color(0xFF0B1711).withOpacity(0.78),
                        const Color(0xFF101D17).withOpacity(0.86),
                        const Color(0xFF0C1410).withOpacity(0.96),
                      ]
                    : [
                        Colors.white.withOpacity(0.68),
                        Colors.white.withOpacity(0.34),
                        Colors.white.withOpacity(0.54),
                        const Color(0xFFEAF7EF).withOpacity(0.78),
                      ],
                stops: const [0, 0.28, 0.70, 1],"""
if old_gradient not in s:
    raise SystemExit("V11.6.60: login gradient anchor missing")
s = s.replace(old_gradient, new_gradient, 1)

# Make text fields follow the adaptive palette whenever they still use a
# hardcoded white fill.
s = re.sub(
    r"fillColor:\\s*(?:const\\s+)?Colors\\.white",
    "fillColor: AppColors.paperAlt",
    s,
)

# The auth glass card itself predates dark mode. Scope the replacement to this
# private widget so white foregrounds on branded buttons remain untouched.
class_marker = "class _GlassCard extends StatelessWidget"
class_start = s.find(class_marker)
if class_start < 0:
    raise SystemExit("V11.6.60: _GlassCard class missing")
class_brace = s.find("{", class_start)
depth = 0
class_end = None
for i in range(class_brace, len(s)):
    if s[i] == "{":
        depth += 1
    elif s[i] == "}":
        depth -= 1
        if depth == 0:
            class_end = i + 1
            break
if class_end is None:
    raise SystemExit("V11.6.60: _GlassCard closing brace missing")

glass = s[class_start:class_end]
original_glass = glass

glass = glass.replace(
    "Colors.white.withOpacity(",
    "(AppColors.isDarkMode ? AppColors.card : Colors.white).withOpacity(",
)
glass = glass.replace(
    "color: Colors.white,",
    "color: AppColors.card,",
)
glass = glass.replace(
    "color: const Color(0xFFFFFFFF),",
    "color: AppColors.card,",
)
glass = glass.replace(
    "color: const Color(0xFFF5F8F6),",
    "color: AppColors.paperAlt,",
)

if glass == original_glass and "AppColors.card" not in glass:
    raise SystemExit("V11.6.60: no adaptive surface could be applied to _GlassCard")
s = s[:class_start] + glass + s[class_end:]

# Some older login helpers used fixed light neutral input fills. Convert only
# explicit fillColor declarations, never button foreground colors.
light_fill_replacements = {
    "fillColor: const Color(0xFFF5F8F6)": "fillColor: AppColors.paperAlt",
    "fillColor: const Color(0xFFF7FAF8)": "fillColor: AppColors.paperAlt",
    "fillColor: const Color(0xFFF8FAF9)": "fillColor: AppColors.paperAlt",
    "fillColor: const Color(0xFFF2F7F4)": "fillColor: AppColors.paperAlt",
}
for old, new in light_fill_replacements.items():
    s = s.replace(old, new)

auth.write_text(s)

checks = [
    "AppColors.isDarkMode",
    "0xFF07110C",
    "0xFF0C1410",
    "class _GlassCard extends StatelessWidget",
]
final = auth.read_text()
for needle in checks:
    if needle not in final:
        raise SystemExit(f"V11.6.60: missing {needle!r} in auth_screen.dart")

if TARGET not in pubspec.read_text():
    raise SystemExit("V11.6.60: version bump missing")

print("GardeFlow V11.6.60: login dark-mode contrast fixed")
