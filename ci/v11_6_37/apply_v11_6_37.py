from pathlib import Path

EXPECTED = "version: 11.6.36+196"
TARGET = "version: 11.6.37+197"

pubspec = Path("pubspec.yaml")
pub = pubspec.read_text()
if EXPECTED not in pub:
    raise SystemExit("V11.6.37: base version mismatch")
pubspec.write_text(pub.replace(EXPECTED, TARGET, 1))

# ---------------------------------------------------------------------------
# Login branding: replace the old uppercase slogan and remove all bottom slogans.
# ---------------------------------------------------------------------------
brand = Path("lib/widgets/brand_identity.dart")
b = brand.read_text()

old_brand_slogan = "'PLUS CLAIR · PLUS RAPIDE · TOUJOURS AVEC VOUS'"
new_brand_slogan = "'LE PLANNING DE GARDE POUR GARDER LE FLOW'"
if old_brand_slogan not in b:
    raise SystemExit("V11.6.37: brand slogan anchor missing")
b = b.replace(old_brand_slogan, new_brand_slogan, 1)
brand.write_text(b)

auth = Path("lib/screens/auth_screen.dart")
a = auth.read_text()

panel_marker = "        const InstitutionalLogosPanel(compact: true),"
panel_start = a.find(panel_marker)
if panel_start < 0:
    raise SystemExit("V11.6.37: institutional logos panel missing")
tail_start = panel_start + len(panel_marker)
tail_end_marker = "\n      ],\n    );\n  }\n\n  Widget _buildLoginForm()"
tail_end = a.find(tail_end_marker, tail_start)
if tail_end < 0:
    raise SystemExit("V11.6.37: auth content tail marker missing")

# Keep the institutional logos but remove every slogan below them.
a = a[:tail_start] + a[tail_end:]
auth.write_text(a)

# ---------------------------------------------------------------------------
# Instagram news: AMI UM6 first, more cards, and real refresh via Supabase RPC.
# ---------------------------------------------------------------------------
news = Path("lib/screens/daily_news_section.dart")
n = news.read_text()

old_state = """class _DailyNewsSectionState extends State<DailyNewsSection> {
  late Future<List<_DailyNewsItem>> _future;"""
new_state = """class _DailyNewsSectionState extends State<DailyNewsSection> {
  late Future<List<_DailyNewsItem>> _future;
  bool _refreshing = false;"""
if old_state not in n:
    raise SystemExit("V11.6.37: news state anchor missing")
n = n.replace(old_state, new_state, 1)

n = n.replace(".limit(24);", ".limit(40);", 1)

old_rows = """    final rows = List<Map<String, dynamic>>.from(response as List);
    final instagramRows = rows.where((row) {
      final mediaType = (row['media_type'] ?? '').toString().toUpperCase();
      final externalId = (row['external_id'] ?? '').toString();
      return mediaType != 'WEB' && !externalId.startsWith('web-');
    });
    final all = instagramRows.map(_DailyNewsItem.fromMap).toList();
    return all.take(8).toList();"""

new_rows = """    final rows = List<Map<String, dynamic>>.from(response as List);
    final instagramRows = rows.where((row) {
      final mediaType = (row['media_type'] ?? '').toString().toUpperCase();
      final externalId = (row['external_id'] ?? '').toString();
      return mediaType != 'WEB' && !externalId.startsWith('web-');
    }).toList();

    // AMI UM6 est prioritaire : ses publications apparaissent toujours
    // en premier, même si d'autres comptes ont publié plus récemment.
    final ami = instagramRows
        .where((row) => row['source_key']?.toString() == 'ami_um6')
        .take(4);
    final others = instagramRows
        .where((row) => row['source_key']?.toString() != 'ami_um6');

    final ordered = <Map<String, dynamic>>[
      ...ami,
      ...others,
    ];

    return ordered.take(12).map(_DailyNewsItem.fromMap).toList();"""

if old_rows not in n:
    raise SystemExit("V11.6.37: news ordering block missing")
n = n.replace(old_rows, new_rows, 1)

old_reload = """  void _reload() {
    setState(() => _future = _loadNews());
  }"""

new_reload = """  Future<void> _reload() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);

    try {
      // Déclenche une vraie synchronisation Instagram côté serveur.
      // La fonction SQL est sécurisée et ne révèle jamais le token Meta.
      await Supabase.instance.client.rpc('request_daily_news_refresh');

      // pg_net exécute la synchronisation en arrière-plan. On laisse le temps
      // au flux Instagram de se mettre à jour avant de relire la table.
      await Future<void>.delayed(const Duration(seconds: 4));
    } catch (_) {
      // Même si la synchronisation distante échoue momentanément,
      // on recharge le cache Instagram déjà disponible.
    }

    if (!mounted) return;
    setState(() {
      _future = _loadNews();
      _refreshing = false;
    });
  }"""

if old_reload not in n:
    raise SystemExit("V11.6.37: news reload block missing")
n = n.replace(old_reload, new_reload, 1)

old_button = """                IconButton(
                  onPressed: snapshot.connectionState == ConnectionState.waiting
                      ? null
                      : _reload,
                  tooltip: 'Actualiser',
                  icon: const Icon(Icons.refresh_rounded),
                ),"""

new_button = """                IconButton(
                  onPressed: snapshot.connectionState == ConnectionState.waiting ||
                          _refreshing
                      ? null
                      : _reload,
                  tooltip: _refreshing
                      ? 'Synchronisation Instagram…'
                      : 'Actualiser Instagram',
                  icon: _refreshing
                      ? const SizedBox(
                          width: 19,
                          height: 19,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        )
                      : const Icon(Icons.refresh_rounded),
                ),"""

if old_button not in n:
    raise SystemExit("V11.6.37: refresh button block missing")
n = n.replace(old_button, new_button, 1)

n = n.replace(
    "'Publications Instagram officielles'",
    "'Instagram officiel · AMI UM6 en priorité'",
    1,
)

news.write_text(n)

print("GardeFlow V11.6.37: login slogans nettoyés + AMI UM6 prioritaire + vrai refresh Instagram")
