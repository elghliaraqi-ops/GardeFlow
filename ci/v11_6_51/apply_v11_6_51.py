from pathlib import Path

EXPECTED = "version: 11.6.50+210"
TARGET = "version: 11.6.51+211"

pubspec = Path("pubspec.yaml")
pub = pubspec.read_text()
if EXPECTED not in pub:
    raise SystemExit("V11.6.51: base version mismatch")
pubspec.write_text(pub.replace(EXPECTED, TARGET, 1))

service = Path("lib/services/official_roster_import_service.dart")
s = service.read_text()

old_empty = """    if (charRects.isEmpty) {
      return _rectLooksRed(
        image,
        fallbackBounds,
        pageWidth,
        pageHeight,
      )
          ? text
          : '';
    }"""
new_empty = """    if (charRects.isEmpty) {
      return _rectLooksRed(
        image,
        fallbackBounds,
        pageWidth,
        pageHeight,
        minRatio: 0.55,
      )
          ? text
          : '';
    }"""
if old_empty not in s:
    raise SystemExit("V11.6.51: empty-charRects red fallback anchor missing")
s = s.replace(old_empty, new_empty, 1)

old_tail = """    // Si le moteur renvoie moins de rectangles que de caractères, la couleur
    // du fragment entier reste un filet de sécurité pour les PDF atypiques.
    if (limit == 0 &&
        _rectLooksRed(image, fallbackBounds, pageWidth, pageHeight)) {
      return text;
    }
    return output.toString();
  }

  static bool _rectLooksRed(
    PdfImage image,
    dynamic rect,
    double pageWidth,
    double pageHeight,
  ) {"""
new_tail = """    final extracted = output.toString();

    // Sur certains PDF, pdfrx expose des rectangles caractère par caractère
    // imprécis alors que le rectangle du fragment est correct. Si aucun
    // caractère rouge n'a été identifié, on accepte le fragment entier
    // uniquement lorsqu'il est très majoritairement rouge. Ce seuil élevé
    // évite de marquer les autres médecins d'une cellule mixte.
    if (extracted.replaceAll(' ', '').isEmpty &&
        _rectLooksRed(
          image,
          fallbackBounds,
          pageWidth,
          pageHeight,
          minRatio: 0.55,
        )) {
      return text;
    }

    return extracted;
  }

  static bool _rectLooksRed(
    PdfImage image,
    dynamic rect,
    double pageWidth,
    double pageHeight, {
    double minRatio = 0.08,
  }) {"""
if old_tail not in s:
    raise SystemExit("V11.6.51: red fallback tail anchor missing")
s = s.replace(old_tail, new_tail, 1)

old_ratio = "      return redPixels / inkPixels >= 0.08;"
new_ratio = "      return redPixels / inkPixels >= minRatio;"
if old_ratio not in s:
    raise SystemExit("V11.6.51: red ratio anchor missing")
s = s.replace(old_ratio, new_ratio, 1)

service.write_text(s)

source_sql = Path(__file__).resolve().parent / "disciplinary_registry_hotfix.sql"
if not source_sql.exists():
    raise SystemExit("V11.6.51: Supabase hotfix migration missing")
target_sql = Path("supabase/patch_v11_6_51_disciplinary_registry_hotfix.sql")
target_sql.write_text(source_sql.read_text())

checks = {
    "lib/services/official_roster_import_service.dart": [
        "minRatio: 0.55",
        "extracted.replaceAll(' ', '').isEmpty",
        "double minRatio = 0.08",
    ],
    "supabase/patch_v11_6_51_disciplinary_registry_hotfix.sql": [
        "official_disciplinary_guards",
        "is_current_disciplinary_guard",
        "protect_disciplinary_guard",
    ],
}
for file_name, needles in checks.items():
    text = Path(file_name).read_text()
    for needle in needles:
        if needle not in text:
            raise SystemExit(f"V11.6.51: missing {needle!r} in {file_name}")

print("GardeFlow V11.6.51: robust red-name detection + persistent disciplinary registry")
