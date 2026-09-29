from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count == 0:
        if new in text:
            return text
        raise SystemExit(f'Practice patch: pattern not found for {label}')
    if count != 1:
        raise SystemExit(f'Practice patch: expected one pattern for {label}, found {count}')
    return text.replace(old, new, 1)


home_path = Path('source/lib/screens/home_screen.dart')
home = home_path.read_text(encoding='utf-8')

home = replace_once(
    home,
    "import 'directory_screen.dart';\n",
    "import 'directory_screen.dart';\nimport 'practice_screen.dart';\n",
    'Practice import',
)

home = replace_once(
    home,
    "title: ['Accueil', 'Planning', 'Annuaire', 'Astreintes'][_tab],",
    "title: ['Accueil', 'Planning', 'Practice', 'Astreintes'][_tab],",
    'top title',
)

home = replace_once(
    home,
    "                  DirectoryScreen(embedded: true),\n",
    "                  PracticeScreen(appState: appState),\n",
    'IndexedStack Practice tab',
)

home = replace_once(
    home,
    "                  item(\n                    2,\n                    Icons.badge_outlined,\n                    Icons.badge_rounded,\n                    'Annuaire',\n                  ),",
    "                  item(\n                    2,\n                    Icons.insights_outlined,\n                    Icons.insights_rounded,\n                    'Practice',\n                  ),",
    'bottom navigation Practice',
)

# Move Directory access to the Astreintes hub, above the common Juniors/Seniors stack.
astreinte_anchor = """          Padding(
            padding: EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: _AstreinteModeSwitch(
              showSenior: _showSenior,
              onChanged: (senior) {
                if (senior == _showSenior) return;
                setState(() => _showSenior = senior);
              },
            ),
          ),
          Expanded(
"""
astreinte_replacement = """          Padding(
            padding: EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: _AstreinteModeSwitch(
              showSenior: _showSenior,
              onChanged: (senior) {
                if (senior == _showSenior) return;
                setState(() => _showSenior = senior);
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => DirectoryScreen()),
                ),
                borderRadius: BorderRadius.circular(16),
                child: Ink(
                  height: 46,
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 31,
                        height: 31,
                        decoration: BoxDecoration(
                          color: AppColors.brandSoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.contacts_rounded,
                          size: 18,
                          color: AppColors.brand,
                        ),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Ouvrir l’annuaire',
                          style: TextStyle(
                            color: AppColors.ink,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.inkSoft,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
"""
home = replace_once(home, astreinte_anchor, astreinte_replacement, 'Astreintes Directory access')

# Integrate Practice information directly inside the existing Bonjour/Bonsoir hero card.
greeting_anchor = """                  Text(
                    '$greeting Dr ${me.nom}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'SpaceGrotesk',
                      fontSize: 30,
                      height: 1.08,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.7,
                    ),
                  ),
                  SizedBox(height: 12),
"""
greeting_replacement = """                  Text(
                    '$greeting Dr ${me.nom}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'SpaceGrotesk',
                      fontSize: 30,
                      height: 1.08,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.7,
                    ),
                  ),
                  PracticeHomeSummary(appState: appState, user: me),
                  SizedBox(height: 12),
"""
home = replace_once(home, greeting_anchor, greeting_replacement, 'home hero Practice summary')

# Remove the legacy Directory quick chip so its public entry point is now Astreintes.
legacy_directory_chip = """      _NavItem(
        Icons.badge_rounded,
        'Annuaire',
        AppColors.catService,
        () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => DirectoryScreen()),
        ),
      ),
"""
if legacy_directory_chip in home:
    home = home.replace(legacy_directory_chip, '', 1)

home_path.write_text(home, encoding='utf-8')

# Keep patient lists limited to validated observations if server-side drafts ever exist.
service_path = Path('source/lib/services/practice_service.dart')
service = service_path.read_text(encoding='utf-8')
query_old = "dynamic query = _backend.client.from('practice_cases').select().eq('user_id', uid);"
query_new = "dynamic query = _backend.client.from('practice_cases').select().eq('user_id', uid).eq('is_draft', false);"
service = replace_once(service, query_old, query_new, 'validated Practice case list')
service_path.write_text(service, encoding='utf-8')

# Explicit patient sorting controls requested for Ma garde.
practice_path = Path('source/lib/screens/practice_screen.dart')
practice = practice_path.read_text(encoding='utf-8')
practice = replace_once(
    practice,
    "  String _scope = 'guard';\n  String _filter = 'all';\n  int _offset = 0;",
    "  String _scope = 'guard';\n  String _filter = 'all';\n  String _sort = 'recent';\n  int _offset = 0;",
    'Practice patient sort state',
)

visible_old = """  List<PracticeCase> get _visible {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _cases;
    return _cases.where((item) {
      return item.patientLabel.toLowerCase().contains(q) ||
          item.displayReason.toLowerCase().contains(q) ||
          (item.location ?? '').toLowerCase().contains(q) ||
          (item.specialistService ?? '').toLowerCase().contains(q);
    }).toList();
  }
"""
visible_new = """  List<PracticeCase> get _visible {
    final q = _search.text.trim().toLowerCase();
    final rows = q.isEmpty
        ? List<PracticeCase>.from(_cases)
        : _cases.where((item) {
            return item.patientLabel.toLowerCase().contains(q) ||
                item.displayReason.toLowerCase().contains(q) ||
                (item.location ?? '').toLowerCase().contains(q) ||
                (item.specialistService ?? '').toLowerCase().contains(q);
          }).toList();
    DateTime effectiveTime(PracticeCase item) =>
        item.arrivalTime ?? item.createdAt ?? DateTime.tryParse(item.guardDate) ?? DateTime.fromMillisecondsSinceEpoch(0);
    rows.sort((a, b) {
      switch (_sort) {
        case 'oldest':
          return effectiveTime(a).compareTo(effectiveTime(b));
        case 'patient':
          return a.patientNumber.compareTo(b.patientNumber);
        case 'arrival':
          final aTime = a.arrivalTime;
          final bTime = b.arrivalTime;
          if (aTime == null && bTime == null) return a.patientNumber.compareTo(b.patientNumber);
          if (aTime == null) return 1;
          if (bTime == null) return -1;
          return aTime.compareTo(bTime);
        default:
          return effectiveTime(b).compareTo(effectiveTime(a));
      }
    });
    return rows;
  }
"""
practice = replace_once(practice, visible_old, visible_new, 'Practice sorted patient list')

filter_anchor = """            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip('all', 'Tous'),
                  _filterChip('waiting', 'En attente'),
                  _filterChip('specialist', 'Avis spécialisé'),
                  _filterChip('discharged', 'Sortants'),
                  _filterChip('hospitalized', 'Hospitalisés'),
                  _filterChip('prescription', 'Ordonnance faite'),
                ],
              ),
            ),
            const SizedBox(height: 16),
"""
filter_replacement = """            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip('all', 'Tous'),
                  _filterChip('waiting', 'En attente'),
                  _filterChip('specialist', 'Avis spécialisé'),
                  _filterChip('discharged', 'Sortants'),
                  _filterChip('hospitalized', 'Hospitalisés'),
                  _filterChip('prescription', 'Ordonnance faite'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: PopupMenuButton<String>(
                initialValue: _sort,
                onSelected: (value) => setState(() => _sort = value),
                color: PracticeColors.surface,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'recent', child: Text('Plus récents')),
                  PopupMenuItem(value: 'oldest', child: Text('Plus anciens')),
                  PopupMenuItem(value: 'patient', child: Text('Patient #')),
                  PopupMenuItem(value: 'arrival', child: Text('Heure d’arrivée')),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                  decoration: BoxDecoration(
                    color: PracticeColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: PracticeColors.line),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.sort_rounded, color: PracticeColors.textSecondary, size: 17),
                      SizedBox(width: 6),
                      Text('Trier', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
"""
practice = replace_once(practice, filter_anchor, filter_replacement, 'Practice patient sort menu')
practice_path.write_text(practice, encoding='utf-8')

print('Practice V12 integration patch applied successfully.')
