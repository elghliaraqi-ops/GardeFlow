from pathlib import Path

EXPECTED = "version: 11.6.32+192"
TARGET = "version: 11.6.33+193"

pubspec = Path("pubspec.yaml")
pub = pubspec.read_text()
if EXPECTED not in pub:
    raise SystemExit("V11.6.33: base version mismatch")
pubspec.write_text(pub.replace(EXPECTED, TARGET, 1))

admin = Path("lib/screens/admin_screen.dart")
text = admin.read_text()

old = "title: const GardeFlowTitle('Vue Admin — gardes par médecin'),"
new = "title: const GardeFlowTitle('Gestion des gardes'),"

if old not in text:
    raise SystemExit("V11.6.33: admin header title not found")

admin.write_text(text.replace(old, new, 1))

print("GardeFlow V11.6.33: header Admin raccourci en Gestion des gardes")
