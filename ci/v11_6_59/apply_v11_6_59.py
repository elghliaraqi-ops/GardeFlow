from pathlib import Path

EXPECTED = "version: 11.6.58+218"
TARGET = "version: 11.6.59+219"

pubspec = Path("pubspec.yaml")
pub = pubspec.read_text()
if EXPECTED not in pub:
    raise SystemExit("V11.6.59: base version mismatch")
pubspec.write_text(pub.replace(EXPECTED, TARGET, 1))

backend = Path("lib/services/supabase_backend_service.dart")
s = backend.read_text()

old = """  Future<List<DirectoryContact>> fetchManualDirectoryContacts() async {
    final rows = await client.from('directory_contacts').select().order('name');
    return (rows as List).map((raw) {
      final j = Map<String, dynamic>.from(raw as Map);
      return DirectoryContact(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        phone: (j['phone'] as String?) ?? '',
        hospital: (j['hospital'] as String?) ?? '',
        service: j['service'] as String?,
        categoryId: (j['category'] as String?) ?? '',
        isManual: true,
      );
    }).toList();
  }"""

new = """  Future<List<DirectoryContact>> fetchManualDirectoryContacts() async {
    // Annuaire global : cette RPC expose uniquement les champs nécessaires
    // aux contacts, pour tous les établissements, sans ouvrir tout profiles.
    final rows = await client.rpc('directory_contacts_all');
    return (rows as List).map((raw) {
      final j = Map<String, dynamic>.from(raw as Map);
      return DirectoryContact(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        phone: (j['phone'] as String?) ?? '',
        hospital: (j['hospital'] as String?) ?? '',
        service: j['service'] as String?,
        gradeLabel: j['grade_label'] as String?,
        isAdmin: j['is_admin'] as bool? ?? false,
        categoryId: (j['category'] as String?) ?? '',
        isManual: j['is_manual'] as bool? ?? true,
      );
    }).toList();
  }"""

if old not in s:
    raise SystemExit("V11.6.59: directory backend anchor missing")
backend.write_text(s.replace(old, new, 1))

directory = Path("lib/screens/directory_screen.dart")
s = directory.read_text()

old_init = """    if (_activeHospital == null) {
      final userHospital = appState.currentUser?.hospital;
      _activeHospital = userHospital != null && kHospitals.contains(userHospital)
          ? userHospital
          : _kAllHospitals;
    }"""
new_init = """    if (_activeHospital == null) {
      // Toujours afficher l'annuaire complet à l'ouverture.
      _activeHospital = _kAllHospitals;
    }"""
if old_init not in s:
    raise SystemExit("V11.6.59: directory initial hospital anchor missing")
s = s.replace(old_init, new_init, 1)

old_query = """    final query = _normalized(_query);
    final items = <_DirectoryItem>[];"""
new_query = """    final query = _normalized(_query);
    final myHospital = appState.currentUser?.hospital;
    final items = <_DirectoryItem>[];"""
if old_query not in s:
    raise SystemExit("V11.6.59: directory query anchor missing")
s = s.replace(old_query, new_query, 1)

old_sort = """    items.sort((a, b) {
      final byCategory = a.section.label.compareTo(b.section.label);
      if (byCategory != 0 && _activeCategory == _kAllCategories) return byCategory;
      return a.contact.name.toLowerCase().compareTo(b.contact.name.toLowerCase());
    });"""
new_sort = """    items.sort((a, b) {
      // L'établissement du médecin connecté est toujours prioritaire.
      final aMine = myHospital != null && a.contact.hospital == myHospital;
      final bMine = myHospital != null && b.contact.hospital == myHospital;
      if (aMine != bMine) return aMine ? -1 : 1;

      final byHospital = hospitalDisplayName(a.contact.hospital)
          .toLowerCase()
          .compareTo(
            hospitalDisplayName(b.contact.hospital).toLowerCase(),
          );
      if (byHospital != 0 && !aMine) return byHospital;

      final byCategory = a.section.label
          .toLowerCase()
          .compareTo(b.section.label.toLowerCase());
      if (byCategory != 0 && _activeCategory == _kAllCategories) {
        return byCategory;
      }

      return a.contact.name
          .toLowerCase()
          .compareTo(b.contact.name.toLowerCase());
    });

    final hospitalItems = <String>[
      if (myHospital != null && kHospitals.contains(myHospital)) myHospital,
      ...kHospitals.where((h) => h != myHospital),
    ];"""
if old_sort not in s:
    raise SystemExit("V11.6.59: directory sort anchor missing")
s = s.replace(old_sort, new_sort, 1)

old_hospitals = """                ...kHospitals.map((h) => DropdownMenuItem(
                      value: h,
                      child: Text("""
new_hospitals = """                ...hospitalItems.map((h) => DropdownMenuItem(
                      value: h,
                      child: Text("""
if old_hospitals not in s:
    raise SystemExit("V11.6.59: directory dropdown anchor missing")
s = s.replace(old_hospitals, new_hospitals, 1)

directory.write_text(s)

source_sql = Path(__file__).resolve().parent / "global_directory.sql"
if not source_sql.exists():
    raise SystemExit("V11.6.59: Supabase migration source missing")
target_sql = Path("supabase/patch_v11_6_59_global_directory.sql")
target_sql.write_text(source_sql.read_text())

checks = {
    "lib/services/supabase_backend_service.dart": [
        "directory_contacts_all",
        "is_manual",
        "grade_label",
    ],
    "lib/screens/directory_screen.dart": [
        "_activeHospital = _kAllHospitals",
        "final myHospital = appState.currentUser?.hospital",
        "aMine ? -1 : 1",
        "hospitalItems",
    ],
    "supabase/patch_v11_6_59_global_directory.sql": [
        "directory_contacts_all",
        "current_account_active()",
        "directory_contacts_read",
        "medecins-juniors",
        "medecins-seniors",
    ],
}

for file_name, needles in checks.items():
    text = Path(file_name).read_text()
    for needle in needles:
        if needle not in text:
            raise SystemExit(f"V11.6.59: missing {needle!r} in {file_name}")

print("GardeFlow V11.6.59: annuaire global tous établissements, établissement du médecin prioritaire")
