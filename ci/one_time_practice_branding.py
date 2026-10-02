from pathlib import Path

practice = Path('source/lib/screens/practice_screen.dart')
s = practice.read_text()

def once(old, new, label):
    global s
    if new in s:
        return
    if old not in s:
        raise SystemExit(f'anchor missing: {label}')
    s = s.replace(old, new, 1)

once('  QcmRanks _qcmMonth = const QcmRanks();\n','  QcmRanks _qcmMonth = const QcmRanks();\n  QcmStats _qcmAll = const QcmStats();\n','qcm state')
once("        _qcmService.qcmRanks(period: 'month'),\n      ]);","        _qcmService.qcmRanks(period: 'month'),\n        _qcmService.qcmSummary(period: 'all'),\n      ]);",'qcm load')
once('        _qcmMonth = results[8] as QcmRanks;\n        _loading = false;','        _qcmMonth = results[8] as QcmRanks;\n        _qcmAll = results[9] as QcmStats;\n        _loading = false;','qcm assign')
once("              const _PracticeHubSectionHeader(\n                icon: Icons.sports_esports_rounded,\n                title: 'S’entraîner',","              const _PracticeBrandMark(),\n              const SizedBox(height: 16),\n              const _PracticeHubSectionHeader(\n                icon: Icons.sports_esports_rounded,\n                title: 'S’entraîner',",'brand')
once('              ),\n              const SizedBox(height: 20),\n              const _PracticeHubSectionHeader(\n                icon: Icons.insights_rounded,','              ),\n              const SizedBox(height: 10),\n              _QcmCanonicalStatsStrip(month: _qcmMonth, total: _qcmAll, loading: _loading),\n              const SizedBox(height: 20),\n              const _PracticeHubSectionHeader(\n                icon: Icons.insights_rounded,','stats strip')

if 'class _PracticeBrandMark extends StatelessWidget' not in s:
    s += '''\n\nclass _PracticeBrandMark extends StatelessWidget {\n  const _PracticeBrandMark();\n  @override\n  Widget build(BuildContext context) => Container(\n    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),\n    decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), gradient: const LinearGradient(colors: [Color(0xFF0D2D63), Color(0xFF165DCA), Color(0xFF7A36E8)]), border: Border.all(color: const Color(0xFF55C8FF).withOpacity(.45))),\n    child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.assignment_turned_in_rounded, color: Colors.white, size: 30), SizedBox(width: 10), Text('Practice', style: TextStyle(color: Colors.white, fontFamily: 'SpaceGrotesk', fontWeight: FontWeight.w900, fontSize: 25))]),\n  );\n}\n\nclass _QcmCanonicalStatsStrip extends StatelessWidget {\n  final QcmRanks month; final QcmStats total; final bool loading;\n  const _QcmCanonicalStatsStrip({required this.month, required this.total, required this.loading});\n  @override\n  Widget build(BuildContext context) => Container(\n    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),\n    decoration: BoxDecoration(color: PracticeColors.surface.withOpacity(.88), borderRadius: BorderRadius.circular(18), border: Border.all(color: PracticeColors.gameBlue.withOpacity(.35))),\n    child: Row(children: [const Icon(Icons.sync_rounded, color: PracticeColors.accent, size: 20), const SizedBox(width: 9), Expanded(child: Text(loading ? 'Synchronisation…' : '${month.answered} ce mois  •  ${total.answered} au total', style: const TextStyle(color: PracticeColors.text, fontWeight: FontWeight.w800, fontSize: 13.5))), const Text('Auto', style: TextStyle(color: PracticeColors.accent, fontSize: 11, fontWeight: FontWeight.w800))]),\n  );\n}\n'''
practice.write_text(s)

splash = Path('source/lib/screens/splash_screen.dart')
z = splash.read_text().replace('Duration(milliseconds: 2600)', 'Duration(milliseconds: 3200)', 1)
anchor = "                            SizedBox(height: 26),\n                            Text(\n                              'AU SERVICE DES SOIGNANTS\\nAU SERVICE DES PATIENTS',"
replacement = "                            SizedBox(height: 22),\n                            const _FlowSuiteSplashBrands(),\n                            SizedBox(height: 22),\n                            Text(\n                              'AU SERVICE DES SOIGNANTS\\nAU SERVICE DES PATIENTS',"
if '_FlowSuiteSplashBrands(),' not in z:
    if anchor not in z: raise SystemExit('anchor missing: splash')
    z = z.replace(anchor, replacement, 1)
if 'class _FlowSuiteSplashBrands extends StatelessWidget' not in z:
    z += '''\n\nclass _FlowSuiteSplashBrands extends StatelessWidget {\n  const _FlowSuiteSplashBrands();\n  @override\n  Widget build(BuildContext context) => Container(\n    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),\n    decoration: BoxDecoration(color: Colors.white.withOpacity(.80), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF1A7A62).withOpacity(.14))),\n    child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [\n      _SplashBrandChip(icon: Icons.hub_rounded, title: 'FlowSuite', subtitle: 'Écosystème hospitalier', colors: [Color(0xFF08734E), Color(0xFFE53935)]),\n      SizedBox(width: 18),\n      _SplashBrandChip(icon: Icons.assignment_turned_in_rounded, title: 'Practice', subtitle: 'Apprendre · progresser', colors: [Color(0xFF075CCB), Color(0xFF873BE8)]),\n    ]),\n  );\n}\nclass _SplashBrandChip extends StatelessWidget {\n  final IconData icon; final String title; final String subtitle; final List<Color> colors;\n  const _SplashBrandChip({required this.icon, required this.title, required this.subtitle, required this.colors});\n  @override\n  Widget build(BuildContext context) => Flexible(child: Row(mainAxisSize: MainAxisSize.min, children: [\n    Container(width: 38, height: 38, decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), gradient: LinearGradient(colors: colors)), child: Icon(icon, color: Colors.white, size: 22)),\n    const SizedBox(width: 7),\n    Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [\n      ShaderMask(shaderCallback: (r) => LinearGradient(colors: colors).createShader(r), child: Text(title, maxLines: 1, style: const TextStyle(color: Colors.white, fontFamily: 'SpaceGrotesk', fontWeight: FontWeight.w900, fontSize: 16))),\n      Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF607080), fontSize: 8.5, fontWeight: FontWeight.w700)),\n    ])),\n  ]));\n}\n'''
splash.write_text(z)
