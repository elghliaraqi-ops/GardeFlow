from pathlib import Path

EXPECTED = "version: 11.6.53+213"
TARGET = "version: 11.6.54+214"

pubspec = Path("pubspec.yaml")
pub = pubspec.read_text()
if EXPECTED not in pub:
    raise SystemExit("V11.6.54: base version mismatch")
pubspec.write_text(pub.replace(EXPECTED, TARGET, 1))

screen = Path("lib/screens/official_planning_screen.dart")
s = screen.read_text()

old = """      final summary = await _backend.officialRosterMySummary(resource: resource);
      final count = (summary['total'] as num?)?.toInt() ?? 0;
      final disciplinaryCount = (summary['disciplinary'] as num?)?.toInt() ?? 0;
      if (mounted) {
        setState(() {
          _myGuardCounts[slot.id] = count;
          _myDisciplinaryCounts[slot.id] = disciplinaryCount;
        });
      }"""

new = """      // Le résumé affiché doit refléter ce qui est réellement retrouvé
      // dans le PDF, pas seulement les lignes déjà transposées en base.
      // Cela évite de sous-compter une garde quand la superposition n'a pas
      // encore été refaite ou qu'une ancienne ligne a été modifiée.
      final myAssignments = parsed.assignments
          .where((a) => a.profileId == me.id)
          .toList(growable: false);
      final count = myAssignments.length;
      final parsedDisciplinaryCount =
          myAssignments.where((a) => a.isDisciplinary).length;

      // Le serveur peut avoir verrouillé une garde via une règle disciplinaire
      // même si le parser local n'a pas encore mis à jour la ligne affichée.
      // On conserve donc le maximum entre la lecture directe du PDF et le
      // registre serveur.
      final summary =
          await _backend.officialRosterMySummary(resource: resource);
      final serverDisciplinaryCount =
          (summary['disciplinary'] as num?)?.toInt() ?? 0;
      final disciplinaryCount =
          parsedDisciplinaryCount > serverDisciplinaryCount
              ? parsedDisciplinaryCount
              : serverDisciplinaryCount;

      if (mounted) {
        setState(() {
          _myGuardCounts[slot.id] = count;
          _myDisciplinaryCounts[slot.id] = disciplinaryCount;
        });
      }"""

if old not in s:
    raise SystemExit("V11.6.54: PDF summary anchor missing")
s = s.replace(old, new, 1)

s = s.replace(
    "label: const Text('Resynchroniser'),",
    "label: const Text('Refaire la superposition'),",
    1,
)

# Exact requested wording remains singular/plural aware.
screen.write_text(s)

checks = [
    "final myAssignments = parsed.assignments",
    "a.isDisciplinary",
    "serverDisciplinaryCount",
    "Refaire la superposition",
    "gardes retrouvées",
]
text = screen.read_text()
for needle in checks:
    if needle not in text:
        raise SystemExit(f"V11.6.54: missing {needle!r}")

print("GardeFlow V11.6.54: PDF-based guard count + disciplinary count + dedicated overlay button")
