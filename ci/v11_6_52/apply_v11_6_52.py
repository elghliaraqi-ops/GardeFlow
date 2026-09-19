from pathlib import Path

EXPECTED = "version: 11.6.51+211"
TARGET = "version: 11.6.52+212"

pubspec = Path("pubspec.yaml")
pub = pubspec.read_text()
if EXPECTED not in pub:
    raise SystemExit("V11.6.52: base version mismatch")
pubspec.write_text(pub.replace(EXPECTED, TARGET, 1))

service = Path("lib/services/official_roster_import_service.dart")
s = service.read_text()

assignment_anchor = """class OfficialRosterParseResult {"""
if assignment_anchor not in s:
    raise SystemExit("V11.6.52: parse result anchor missing")

disciplinary_class = r"""
class OfficialRosterDisciplinaryMark {
  final String dateStr;
  final String shiftId;
  final String redText;

  const OfficialRosterDisciplinaryMark({
    required this.dateStr,
    required this.shiftId,
    required this.redText,
  });

  Map<String, dynamic> toJson() => {
        'date': dateStr,
        'shift_id': shiftId,
        'red_text': redText,
        'parser_revision': 'v11.6.52-r1',
      };
}

"""
s = s.replace(assignment_anchor, disciplinary_class + assignment_anchor, 1)

s = s.replace(
"""  final List<Map<String, dynamic>> unmatchedCells;
  final int detectedRows;""",
"""  final List<Map<String, dynamic>> unmatchedCells;
  final List<OfficialRosterDisciplinaryMark> disciplinaryMarks;
  final int detectedRows;""",
1)

s = s.replace(
"""    required this.assignments,
    required this.unmatchedCells,
    required this.detectedRows,""",
"""    required this.assignments,
    required this.unmatchedCells,
    required this.disciplinaryMarks,
    required this.detectedRows,""",
1)

s = s.replace(
"""        'is_disciplinary': isDisciplinary,
      };""",
"""        'is_disciplinary': isDisciplinary,
        'parser_revision': 'v11.6.52-r1',
      };""",
1)

s = s.replace(
"""    final unmatched = <Map<String, dynamic>>[];
    final rawAssignments = <OfficialRosterAssignment>[];""",
"""    final unmatched = <Map<String, dynamic>>[];
    final disciplinaryMarks = <OfficialRosterDisciplinaryMark>[];
    final rawAssignments = <OfficialRosterAssignment>[];""",
1)

cell_anchor = """      for (final cell in row.cells) {
        detectedCells++;
        final matched = _matchProfiles(cell.text, candidateProfiles);"""
if cell_anchor not in s:
    raise SystemExit("V11.6.52: cell loop anchor missing")
s = s.replace(
cell_anchor,
"""      for (final cell in row.cells) {
        detectedCells++;

        final redText = _cellRedText(cell);
        if (redText.isNotEmpty) {
          disciplinaryMarks.add(
            OfficialRosterDisciplinaryMark(
              dateStr: dateStr,
              shiftId: cell.shiftId,
              redText: redText,
            ),
          );
        }

        final matched = _matchProfiles(cell.text, candidateProfiles);""",
1)

s = s.replace(
"""      assignments: assignments,
      unmatchedCells: unmatched,
      detectedRows: rows.length,""",
"""      assignments: assignments,
      unmatchedCells: unmatched,
      disciplinaryMarks: disciplinaryMarks,
      detectedRows: rows.length,""",
1)

profile_marker = """  static bool _profileMarkedRed("""
idx = s.find(profile_marker)
if idx < 0:
    raise SystemExit("V11.6.52: profile red helper anchor missing")
cell_helper = r"""  static String _cellRedText(_RosterCell cell) {
    return cell.fragments
        .map((f) => f.redText)
        .where((value) => value.trim().isNotEmpty)
        .join(' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

"""
s = s[:idx] + cell_helper + s[idx:]

old_orientation = """    // Selon le backend PDF, les rectangles peuvent être exprimés dans un
    // repère Y descendant ou Y montant. Tester les deux garde la détection
    // fiable sur Android/iOS/web sans OCR.
    if (sample(minY, maxY)) return true;
    final flippedTop = pageHeight - maxY;
    final flippedBottom = pageHeight - minY;
    return sample(flippedTop, flippedBottom);"""
new_orientation = """    // PdfRect utilise le repère PDF : origine en bas à gauche, axe Y vers le haut.
    // PdfImage est un bitmap : origine en haut à gauche. Il faut donc inverser Y.
    final imageTop = pageHeight - maxY;
    final imageBottom = pageHeight - minY;
    return sample(imageTop, imageBottom);"""
if old_orientation not in s:
    raise SystemExit("V11.6.52: PDF coordinate conversion anchor missing")
s = s.replace(old_orientation, new_orientation, 1)

service.write_text(s)

backend = Path("lib/services/supabase_backend_service.dart")
b = backend.read_text()
import_anchor = """  Future<bool> officialRosterProfileSyncIsCurrent({"""
if import_anchor not in b:
    raise SystemExit("V11.6.52: backend import anchor missing")
register_method = r"""  Future<Map<String, dynamic>> registerOfficialDisciplinaryMarks({
    required SharedResource resource,
    required List<Map<String, dynamic>> marks,
  }) async {
    final result = await client.rpc(
      'register_official_disciplinary_marks',
      params: {
        'p_resource_id': resource.id,
        'p_resource_updated_at': resource.updatedAt.toUtc().toIso8601String(),
        'p_marks': marks,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

"""
b = b.replace(import_anchor, register_method + import_anchor, 1)
backend.write_text(b)

screen = Path("lib/screens/official_planning_screen.dart")
o = screen.read_text()
old_call = """      final result = await _backend.importOfficialEmergencyRoster(
        resource: resource,
        assignments: parsed.assignments.map((a) => a.toJson()).toList(growable: false),
        unmatchedCells: parsed.unmatchedCells,
      );"""
new_call = """      final result = await _backend.importOfficialEmergencyRoster(
        resource: resource,
        assignments: parsed.assignments.map((a) => a.toJson()).toList(growable: false),
        unmatchedCells: parsed.unmatchedCells,
      );

      await _backend.registerOfficialDisciplinaryMarks(
        resource: resource,
        marks: parsed.disciplinaryMarks
            .map((m) => m.toJson())
            .toList(growable: false),
      );"""
if old_call not in o:
    raise SystemExit("V11.6.52: official import call anchor missing")
o = o.replace(old_call, new_call, 1)

screen.write_text(o)

source_sql = Path(__file__).resolve().parent / "disciplinary_rules.sql"
if not source_sql.exists():
    raise SystemExit("V11.6.52: Supabase migration source missing")
target_sql = Path("supabase/patch_v11_6_52_disciplinary_rules.sql")
target_sql.write_text(source_sql.read_text())

checks = {
    "lib/services/official_roster_import_service.dart": [
        "OfficialRosterDisciplinaryMark",
        "disciplinaryMarks",
        "parser_revision",
        "_cellRedText",
        "final imageTop = pageHeight - maxY",
    ],
    "lib/services/supabase_backend_service.dart": [
        "registerOfficialDisciplinaryMarks",
        "register_official_disciplinary_marks",
    ],
    "lib/screens/official_planning_screen.dart": [
        "parsed.disciplinaryMarks",
    ],
    "supabase/patch_v11_6_52_disciplinary_rules.sql": [
        "official_disciplinary_name_rules",
        "register_official_disciplinary_marks",
        "is_current_disciplinary_guard",
    ],
}
for file_name, needles in checks.items():
    text = Path(file_name).read_text()
    for needle in needles:
        if needle not in text:
            raise SystemExit(f"V11.6.52: missing {needle!r} in {file_name}")

print("GardeFlow V11.6.52: server-backed disciplinary rules for all doctors")
