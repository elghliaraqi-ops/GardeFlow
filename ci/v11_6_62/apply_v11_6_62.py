from pathlib import Path

EXPECTED = "version: 11.6.61+221"
TARGET = "version: 11.6.62+222"


def replace_once(path: str, old: str, new: str, label: str) -> None:
    p = Path(path)
    text = p.read_text()
    if old not in text:
        if new in text:
            return
        raise SystemExit(f"V11.6.62: {label} anchor missing in {path}")
    p.write_text(text.replace(old, new, 1))


pubspec = Path("pubspec.yaml")
pub = pubspec.read_text()
if EXPECTED not in pub:
    if TARGET not in pub:
        raise SystemExit("V11.6.62: base version mismatch")
else:
    pubspec.write_text(pub.replace(EXPECTED, TARGET, 1))

replace_once(
    "lib/screens/auth_screen.dart",
    """        SizedBox(height: compactLogin ? 10 : 18),
        const InstitutionalLogosPanel(compact: true),
""",
    "",
    "login institutional logos",
)

replace_once(
    "lib/screens/splash_screen.dart",
    """                            const SizedBox(height: 28),
                            const InstitutionalLogosPanel(showBouskouraOnOwnRow: true),
                            const SizedBox(height: 24),
""",
    """                            const SizedBox(height: 30),
""",
    "splash institutional logos",
)

for path in ("lib/screens/auth_screen.dart", "lib/screens/splash_screen.dart"):
    text = Path(path).read_text()
    if "InstitutionalLogosPanel" in text:
        raise SystemExit(f"V11.6.62: partner logos still displayed in {path}")
    if "assets/branding/partners/" in text:
        raise SystemExit(f"V11.6.62: direct partner asset still displayed in {path}")

if "GardeFlowBrandBlock" not in Path("lib/screens/auth_screen.dart").read_text():
    raise SystemExit("V11.6.62: GardeFlow branding unexpectedly missing from login")
if "GardeFlowBrandBlock" not in Path("lib/screens/splash_screen.dart").read_text():
    raise SystemExit("V11.6.62: GardeFlow branding unexpectedly missing from splash")
if TARGET not in pubspec.read_text():
    raise SystemExit("V11.6.62: version bump missing")

print("GardeFlow V11.6.62: hospital and AMIUM6 logos removed from splash and login")
