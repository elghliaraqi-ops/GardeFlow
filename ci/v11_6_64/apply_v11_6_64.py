from pathlib import Path

EXPECTED = "version: 11.6.63+223"
TARGET = "version: 11.6.64+224"


def replace_once(path: str, old: str, new: str, label: str) -> None:
    p = Path(path)
    text = p.read_text()
    if old not in text:
        if new in text:
            return
        raise SystemExit(f"V11.6.64: {label} anchor missing in {path}")
    p.write_text(text.replace(old, new, 1))


pubspec = Path("pubspec.yaml")
pub = pubspec.read_text()
if EXPECTED not in pub:
    if TARGET not in pub:
        raise SystemExit("V11.6.64: base version mismatch")
else:
    pubspec.write_text(pub.replace(EXPECTED, TARGET, 1))

sheet = Path("lib/screens/exchange_request_sheet.dart")
s = sheet.read_text()

replace_once(
    "lib/screens/exchange_request_sheet.dart",
    """  String? _doctorId;
  String? _targetEntryId;
  String? _error;
""",
    """  String? _doctorId;
  String? _targetEntryId;
  String _doctorSearch = '';
  final TextEditingController _doctorSearchController = TextEditingController();
  String? _error;
""",
    "doctor search state",
)

replace_once(
    "lib/screens/exchange_request_sheet.dart",
    """  @override
  Widget build(BuildContext context) {
""",
    """  @override
  void dispose() {
    _doctorSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
""",
    "dispose doctor search controller",
)

replace_once(
    "lib/screens/exchange_request_sheet.dart",
    """    final targets = state.exchangeTargets(sameServiceOnly: exchangeMode && sourceIsService);
    final dateLabel = DateFormat('EEEE d MMMM', 'fr_FR').format(DateTime.parse(widget.dateStr));
    final selectedDoctor = _doctorId == null ? null : targets.where((c) => c.id == _doctorId).firstOrNull;
""",
    """    final targets = state.exchangeTargets(sameServiceOnly: exchangeMode && sourceIsService);
    final search = _doctorSearch.trim().toLowerCase();
    final filteredTargets = search.isEmpty
        ? targets
        : targets.where((c) {
            final haystack = '${c.name} ${c.service}'.toLowerCase();
            return haystack.contains(search);
          }).toList();
    final dateLabel = DateFormat('EEEE d MMMM', 'fr_FR').format(DateTime.parse(widget.dateStr));
    final selectedDoctor = _doctorId == null ? null : targets.where((c) => c.id == _doctorId).firstOrNull;
""",
    "filtered doctor targets",
)

replace_once(
    "lib/screens/exchange_request_sheet.dart",
    """              DropdownButtonFormField<String>(
                value: selectedDoctor?.id,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Médecin destinataire'),
                items: targets.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (v) => setState(() {
                  _doctorId = v;
                  _targetEntryId = null;
                  _error = null;
                }),
              ),
""",
    """              TextField(
                controller: _doctorSearchController,
                onChanged: (value) => setState(() {
                  _doctorSearch = value;
                  _doctorId = null;
                  _targetEntryId = null;
                  _error = null;
                }),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  labelText: 'Rechercher un médecin',
                  hintText: 'Nom ou service',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _doctorSearch.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Effacer la recherche',
                          onPressed: () => setState(() {
                            _doctorSearchController.clear();
                            _doctorSearch = '';
                            _doctorId = null;
                            _targetEntryId = null;
                            _error = null;
                          }),
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
              ),
              const SizedBox(height: AppSpace.md),
              if (filteredTargets.isEmpty)
                Text(
                  'Aucun médecin ne correspond à votre recherche.',
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else
                DropdownButtonFormField<String>(
                  value: selectedDoctor != null &&
                          filteredTargets.any((c) => c.id == selectedDoctor.id)
                      ? selectedDoctor.id
                      : null,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Médecin destinataire',
                    helperText: search.isEmpty
                        ? '${targets.length} médecin${targets.length > 1 ? 's' : ''} disponible${targets.length > 1 ? 's' : ''}'
                        : '${filteredTargets.length} résultat${filteredTargets.length > 1 ? 's' : ''}',
                  ),
                  items: filteredTargets
                      .map(
                        (c) => DropdownMenuItem(
                          value: c.id,
                          child: Text(
                            '${c.name} · ${c.service}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() {
                    _doctorId = v;
                    _targetEntryId = null;
                    _error = null;
                  }),
                ),
""",
    "searchable doctor selector",
)

final = sheet.read_text()
checks = [
    "String _doctorSearch = '';",
    "final TextEditingController _doctorSearchController = TextEditingController();",
    "_doctorSearchController.dispose();",
    "final filteredTargets = search.isEmpty",
    "labelText: 'Rechercher un médecin'",
    "hintText: 'Nom ou service'",
    "Icons.search_rounded",
    "Aucun médecin ne correspond à votre recherche.",
    "items: filteredTargets",
    "Médecin destinataire",
]
for needle in checks:
    if needle not in final:
        raise SystemExit(f"V11.6.64: missing {needle!r}")

if TARGET not in pubspec.read_text():
    raise SystemExit("V11.6.64: version bump missing")

print("GardeFlow V11.6.64: searchable destination doctor selector for transfers and exchanges")
