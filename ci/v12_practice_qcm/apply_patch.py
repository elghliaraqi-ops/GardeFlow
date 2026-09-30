from pathlib import Path
import re


def once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected 1 match, found {count}')
    return text.replace(old, new, 1)

# ---------------- HOME ----------------
home_path = Path('source/lib/screens/home_screen.dart')
home = home_path.read_text(encoding='utf-8')

if 'final ScrollController _homeScrollController' not in home:
    home = once(
        home,
        '  final GlobalKey _clinicalCasesFeedKey = GlobalKey();',
        '  final GlobalKey _clinicalCasesFeedKey = GlobalKey();\n  final ScrollController _homeScrollController = ScrollController();',
        'home scroll controller field',
    )
    home = once(
        home,
        '  @override\n  Widget build(BuildContext context) {',
        '  @override\n  void dispose() {\n    _homeScrollController.dispose();\n    super.dispose();\n  }\n\n  @override\n  Widget build(BuildContext context) {',
        'home dispose',
    )

if 'scrollController: _homeScrollController' not in home:
    home = once(
        home,
        '                    clinicalCasesFeedKey: _clinicalCasesFeedKey,',
        '                    clinicalCasesFeedKey: _clinicalCasesFeedKey,\n                    scrollController: _homeScrollController,',
        'dashboard scroll controller arg',
    )

if 'final ScrollController scrollController;' not in home:
    home = once(
        home,
        '  final GlobalKey clinicalCasesFeedKey;\n  final VoidCallback onOpenPlanning;',
        '  final GlobalKey clinicalCasesFeedKey;\n  final ScrollController scrollController;\n  final VoidCallback onOpenPlanning;',
        'dashboard scroll field',
    )
    home = once(
        home,
        '    required this.clinicalCasesFeedKey,\n    required this.onOpenPlanning,',
        '    required this.clinicalCasesFeedKey,\n    required this.scrollController,\n    required this.onOpenPlanning,',
        'dashboard scroll ctor',
    )

if 'controller: scrollController,' not in home:
    dashboard_idx = home.index('class _DashboardView')
    list_idx = home.index('    return ListView(', dashboard_idx)
    home = home[:list_idx] + home[list_idx:].replace(
        '    return ListView(\n      physics:',
        '    return ListView(\n      controller: scrollController,\n      physics:',
        1,
    )

# Make the clinical-cases CTA reliable even when the lazy ListView has not built the target yet.
pattern = re.compile(
    r"onTap: \(\) \{\s*final targetContext = clinicalCasesFeedKey\.currentContext;\s*if \(targetContext == null\) return;\s*Scrollable\.ensureVisible\(\s*targetContext,\s*duration: const Duration\(milliseconds: 520\),\s*curve: Curves\.easeOutCubic,\s*alignment: 0\.04,\s*\);\s*\},"
)
if pattern.search(home):
    home = pattern.sub(
        "onTap: () async {\n"
        "                if (scrollController.hasClients) {\n"
        "                  await scrollController.animateTo(\n"
        "                    scrollController.position.maxScrollExtent,\n"
        "                    duration: const Duration(milliseconds: 560),\n"
        "                    curve: Curves.easeOutCubic,\n"
        "                  );\n"
        "                }\n"
        "                await Future<void>.delayed(const Duration(milliseconds: 40));\n"
        "                final targetContext = clinicalCasesFeedKey.currentContext;\n"
        "                if (targetContext == null) return;\n"
        "                await Scrollable.ensureVisible(\n"
        "                  targetContext,\n"
        "                  duration: const Duration(milliseconds: 260),\n"
        "                  curve: Curves.easeOutCubic,\n"
        "                  alignment: 0.02,\n"
        "                );\n"
        "              },",
        home,
        count=1,
    )
elif 'scrollController.position.maxScrollExtent' not in home:
    raise SystemExit('clinical cases CTA handler not found')

# Central Rappels label must contrast with the green button.
rappels = re.compile(r"('Rappels',\s*style: TextStyle\(\s*)color: AppColors\.brandDark,")
home, n = rappels.subn(r"\1color: Colors.white,", home, count=1)
if n != 1 and "'Rappels'" in home and 'color: Colors.white,' not in home[home.index("'Rappels'"):home.index("'Rappels'")+220]:
    raise SystemExit('Rappels label color not patched')

home_path.write_text(home, encoding='utf-8')

# ---------------- PRACTICE ----------------
practice_path = Path('source/lib/screens/practice_screen.dart')
practice = practice_path.read_text(encoding='utf-8')

if "import '../models/qcm_models.dart';" not in practice:
    practice = once(practice, "import '../models/practice_models.dart';", "import '../models/practice_models.dart';\nimport '../models/qcm_models.dart';", 'qcm model import')
if "import '../services/clinical_case_service.dart';" not in practice:
    practice = once(practice, "import '../services/practice_service.dart';", "import '../services/practice_service.dart';\nimport '../services/clinical_case_service.dart';", 'qcm service import')
if "import 'practice_qcm_screen.dart';" not in practice:
    practice = once(practice, "import '../state/app_state.dart';", "import '../state/app_state.dart';\nimport 'practice_qcm_screen.dart';", 'qcm screen import')

if 'final _qcmService = ClinicalCaseService.instance;' not in practice:
    practice = once(
        practice,
        '  final _service = PracticeService.instance;',
        '  final _service = PracticeService.instance;\n  final _qcmService = ClinicalCaseService.instance;',
        'qcm service field',
    )
if 'QcmRanks _qcmMonth' not in practice:
    practice = once(
        practice,
        '  PracticeRanks _ranks = const PracticeRanks();',
        '  PracticeRanks _ranks = const PracticeRanks();\n  QcmRanks _qcmMonth = const QcmRanks();',
        'qcm month field',
    )
if '_qcmService.revision.addListener(_onRevision);' not in practice:
    practice = once(
        practice,
        '    _service.revision.addListener(_onRevision);\n    _load();',
        '    _service.revision.addListener(_onRevision);\n    _qcmService.revision.addListener(_onRevision);\n    _load();',
        'qcm listener init',
    )
if '_qcmService.revision.removeListener(_onRevision);' not in practice:
    practice = once(
        practice,
        '    _service.revision.removeListener(_onRevision);\n    super.dispose();',
        '    _service.revision.removeListener(_onRevision);\n    _qcmService.revision.removeListener(_onRevision);\n    super.dispose();',
        'qcm listener dispose',
    )
if "_qcmService.qcmRanks(period: 'month')" not in practice:
    practice = once(
        practice,
        '        _service.monthlyCounts(year: DateTime.now().year),\n      ]);',
        "        _service.monthlyCounts(year: DateTime.now().year),\n        _qcmService.qcmRanks(period: 'month'),\n      ]);",
        'qcm load future',
    )
    practice = once(
        practice,
        '        _monthly = results[7] as List<int>;\n        _loading = false;',
        '        _monthly = results[7] as List<int>;\n        _qcmMonth = results[8] as QcmRanks;\n        _loading = false;',
        'qcm load assign',
    )

state_idx = practice.index('class _PracticeScreenState')
build_start = practice.index('  @override\n  Widget build(BuildContext context) {', state_idx)
build_end = practice.index('  String _rankSubtitle(', build_start)
new_build = r'''  @override
  Widget build(BuildContext context) {
    final guard = _currentGuard;
    final level = practiceLevelForXp(_all.xp);
    final unlocked = _achievements.where((a) => a.unlocked).length;
    return ColoredBox(
      color: PracticeColors.background,
      child: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _load,
          color: PracticeColors.accent,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 34),
            children: [
              const Text(
                'Practice',
                style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: -0.8),
              ),
              const SizedBox(height: 4),
              const Text(
                'Gardes, cas documentés et apprentissage en un seul espace.',
                style: TextStyle(color: PracticeColors.textSecondary, fontSize: 13.5, fontWeight: FontWeight.w600),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                _PracticeNotice(icon: Icons.cloud_off_rounded, text: _error!),
              ],
              const SizedBox(height: 20),
              _sectionLabel('GARDE EN COURS'),
              const SizedBox(height: 10),
              if (guard == null)
                _NoGuardCard(
                  onHistory: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => PracticeGuardScreen(appState: widget.appState)),
                  ),
                )
              else
                _CurrentGuardCard(
                  guard: guard,
                  stats: _guard,
                  goal: _prefs.guardGoal,
                  onNewCase: _newCase,
                  onOpenGuard: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => PracticeGuardScreen(appState: widget.appState, guard: guard)),
                  ),
                  onEditGoal: _editGoal,
                ),
              const SizedBox(height: 22),
              _sectionLabel('VUE D’ENSEMBLE'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _StatCard(value: '${_month.patients}', label: 'Ce mois', loading: _loading)),
                  const SizedBox(width: 8),
                  Expanded(child: _StatCard(value: '${_year.patients}', label: 'Cette année', loading: _loading)),
                  const SizedBox(width: 8),
                  Expanded(child: _StatCard(value: '${_all.patients}', label: 'Total', loading: _loading)),
                ],
              ),
              const SizedBox(height: 12),
              _LevelCard(level: level, xp: _all.xp, streak: _all.streak),
              const SizedBox(height: 22),
              _sectionLabel('APPRENTISSAGE QCM'),
              const SizedBox(height: 10),
              _QcmPracticeCard(
                stats: _qcmMonth,
                loading: _loading,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PracticeQcmScreen()),
                ),
              ),
              const SizedBox(height: 22),
              _sectionLabel('PROGRESSION'),
              const SizedBox(height: 10),
              _PracticeActionTile(
                icon: Icons.emoji_events_rounded,
                title: 'Classement Practice',
                subtitle: _rankSubtitle(_ranks),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => PracticeLeaderboardScreen(appState: widget.appState)),
                ),
              ),
              const SizedBox(height: 9),
              _PracticeActionTile(
                icon: Icons.workspace_premium_rounded,
                title: 'Succès',
                subtitle: '$unlocked / ${_achievements.length} succès débloqués',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => PracticeAchievementsScreen(appState: widget.appState)),
                ),
              ),
              const SizedBox(height: 9),
              _PracticeActionTile(
                icon: Icons.insights_rounded,
                title: 'Progression annuelle',
                subtitle: '${_year.patients} patients documentés cette année',
                onTap: () => _showProgression(context),
              ),
              const SizedBox(height: 16),
              _EncouragementCard(text: _encouragement(guard)),
              const SizedBox(height: 22),
              _sectionLabel('PRÉFÉRENCES'),
              const SizedBox(height: 10),
              _LeaderboardPreferenceCard(
                value: _prefs.leaderboardOptIn,
                onChanged: (value) async {
                  setState(() => _prefs = PracticePreferences(leaderboardOptIn: value, guardGoal: _prefs.guardGoal));
                  await _service.savePreferences(leaderboardOptIn: value, guardGoal: _prefs.guardGoal);
                  await _load(silent: true);
                },
              ),
              const SizedBox(height: 15),
              const Text(
                'Les classements Practice et QCM reflètent uniquement l’activité documentée et les exercices pédagogiques. Ils ne mesurent pas la compétence clinique ni la qualité des soins.',
                textAlign: TextAlign.center,
                style: TextStyle(color: PracticeColors.textSecondary, fontSize: 10.5, height: 1.4, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

'''
practice = practice[:build_start] + new_build + practice[build_end:]

if 'class _QcmPracticeCard extends StatelessWidget' not in practice:
    insert_at = practice.index('class PracticeGuardScreen')
    qcm_card = r'''class _QcmPracticeCard extends StatelessWidget {
  final QcmRanks stats;
  final bool loading;
  final VoidCallback onTap;

  const _QcmPracticeCard({required this.stats, required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final rankText = !stats.leaderboardOptIn
        ? 'Classement désactivé'
        : stats.promotionRank != null
            ? '${stats.promotionRank}e dans votre promo'
            : stats.globalRank != null
                ? '${stats.globalRank}e toutes promotions'
                : 'Classement après votre première réponse';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: PracticeColors.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: PracticeColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(color: PracticeColors.elevated, borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.quiz_rounded, color: PracticeColors.accent),
                  ),
                  const SizedBox(width: 11),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('QCM des cas cliniques', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900)),
                        SizedBox(height: 2),
                        Text('Statistiques du mois et classement QCM', style: TextStyle(color: PracticeColors.textSecondary, fontSize: 10.5, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: PracticeColors.textSecondary),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: _QcmMiniMetric(value: loading ? '—' : '${stats.answered}', label: 'Répondus')),
                  const SizedBox(width: 8),
                  Expanded(child: _QcmMiniMetric(value: loading ? '—' : '${stats.correct}', label: 'Corrects')),
                  const SizedBox(width: 8),
                  Expanded(child: _QcmMiniMetric(value: loading ? '—' : '${stats.accuracy.toStringAsFixed(0)}%', label: 'Réussite')),
                ],
              ),
              const SizedBox(height: 11),
              Row(
                children: [
                  const Icon(Icons.emoji_events_outlined, size: 17, color: PracticeColors.accent),
                  const SizedBox(width: 7),
                  Expanded(child: Text(rankText, style: const TextStyle(color: PracticeColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w800))),
                  const Text('Voir le classement', style: TextStyle(color: PracticeColors.accent, fontSize: 10.5, fontWeight: FontWeight.w900)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QcmMiniMetric extends StatelessWidget {
  final String value;
  final String label;
  const _QcmMiniMetric({required this.value, required this.label});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(color: PracticeColors.background.withOpacity(0.34), borderRadius: BorderRadius.circular(13)),
        child: Column(
          children: [
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: PracticeColors.textSecondary, fontSize: 9.5, fontWeight: FontWeight.w700)),
          ],
        ),
      );
}

'''
    practice = practice[:insert_at] + qcm_card + practice[insert_at:]

practice_path.write_text(practice, encoding='utf-8')

# ---------------- CLINICAL CASE QCM ----------------
case_path = Path('source/lib/screens/clinical_cases_section.dart')
case = case_path.read_text(encoding='utf-8')

if 'bool _submitting = false;' not in case:
    case = once(
        case,
        'class _ClinicalCaseCardState extends State<_ClinicalCaseCard> {\n  int? _selected;\n  bool _expanded = false;',
        "class _ClinicalCaseCardState extends State<_ClinicalCaseCard> {\n  int? _selected;\n  bool _expanded = false;\n  bool _submitting = false;\n\n  @override\n  void initState() {\n    super.initState();\n    _selected = widget.post.mySelectedIndex;\n  }\n\n  @override\n  void didUpdateWidget(covariant _ClinicalCaseCard oldWidget) {\n    super.didUpdateWidget(oldWidget);\n    if (widget.post.id != oldWidget.post.id || widget.post.mySelectedIndex != oldWidget.post.mySelectedIndex) {\n      _selected = widget.post.mySelectedIndex;\n    }\n  }\n\n  Future<void> _answer(int index) async {\n    if (_selected != null || _submitting) return;\n    setState(() => _submitting = true);\n    try {\n      final result = await ClinicalCaseService.instance.submitAnswer(postId: widget.post.id, selectedIndex: index);\n      if (!mounted) return;\n      setState(() => _selected = result.selectedIndex);\n    } catch (_) {\n      if (!mounted) return;\n      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impossible d’enregistrer cette réponse QCM.')));\n    } finally {\n      if (mounted) setState(() => _submitting = false);\n    }\n  }",
        'clinical card answer state',
    )

case = case.replace(
    '                    onTap: answered ? null : () => setState(() => _selected = index),',
    '                    onTap: answered || _submitting ? null : () => _answer(index),',
    1,
)

case_path.write_text(case, encoding='utf-8')
print('Practice/QCM UI patch applied.')
