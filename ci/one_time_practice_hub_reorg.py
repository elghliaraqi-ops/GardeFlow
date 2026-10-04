from __future__ import annotations

from pathlib import Path

ROOT = Path('.')
PRACTICE = ROOT / 'source' / 'lib' / 'screens' / 'practice_screen.dart'

s = PRACTICE.read_text()
state_anchor = 'class _PracticeScreenState extends State<PracticeScreen> {'
state_start = s.find(state_anchor)
if state_start < 0:
    raise SystemExit('Practice state anchor not found')

build_anchor = '  @override\n  Widget build(BuildContext context) {'
build_start = s.find(build_anchor, state_start)
if build_start < 0:
    raise SystemExit('Practice build anchor not found')

build_end_anchor = '\n  String _rankSubtitle(PracticeRanks ranks) {'
build_end = s.find(build_end_anchor, build_start)
if build_end < 0:
    raise SystemExit('Practice build end anchor not found')

new_build = r'''  @override
  Widget build(BuildContext context) {
    final guard = _currentGuard;
    final level = practiceLevelForXp(_all.xp);
    final unlocked = _achievements.where((a) => a.unlocked).length;
    final rankLabel = !_ranks.leaderboardOptIn
        ? 'Désactivé'
        : _ranks.promotionRank != null
        ? '#${_ranks.promotionRank} promo'
        : 'Ouvrir';
    final qcmMeta = _loading
        ? 'Chargement…'
        : '${_qcmMonth.answered} répondus · ${_qcmMonth.accuracy.toStringAsFixed(0)}%';

    return ScreenDecorBackdrop(
      scene: ScreenDecorScene.practice,
      baseColor: PracticeColors.background,
      child: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _load,
          color: PracticeColors.accent,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 34),
            children: [
              _PracticeGameHeader(
                level: level,
                xp: _all.xp,
                streak: _all.streak,
                unlocked: unlocked,
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                _PracticeNotice(icon: Icons.cloud_off_rounded, text: _error!),
              ],

              // 1. L'objectif principal de Practice reste l'entraînement.
              const SizedBox(height: 18),
              const _PracticeHubSectionHeader(
                icon: Icons.school_rounded,
                title: 'S’entraîner',
                subtitle: 'Les deux accès principaux, immédiatement disponibles',
              ),
              const SizedBox(height: 9),
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _PracticePrimaryActionCard(
                      icon: Icons.medical_information_rounded,
                      title: 'Cas cliniques',
                      subtitle: 'Cas interactifs et défis associés',
                      meta: 'Cas + QCM',
                      accent: PracticeColors.gamePurple,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ClinicalCasesScreen(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: _PracticePrimaryActionCard(
                      icon: Icons.quiz_rounded,
                      title: 'QCM',
                      subtitle: 'Répondre, corriger et progresser',
                      meta: qcmMeta,
                      accent: PracticeColors.accent,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PracticeQcmScreen(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // 2. Le suivi de garde vient ensuite : important, mais distinct de l'entraînement.
              const SizedBox(height: 22),
              const _PracticeHubSectionHeader(
                icon: Icons.emergency_rounded,
                title: 'Ma garde',
                subtitle: 'Patients, objectif personnel et historique de garde',
              ),
              const SizedBox(height: 9),
              if (guard == null)
                _NoGuardCard(
                  onHistory: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          PracticeGuardScreen(appState: widget.appState),
                    ),
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
                    MaterialPageRoute(
                      builder: (_) => PracticeGuardScreen(
                        appState: widget.appState,
                        guard: guard,
                      ),
                    ),
                  ),
                  onEditGoal: _editGoal,
                ),
              if (guard != null) ...[
                const SizedBox(height: 9),
                _EncouragementCard(text: _encouragement(guard)),
              ],

              // 3. Toutes les statistiques sont regroupées dans une seule zone.
              const SizedBox(height: 22),
              const _PracticeHubSectionHeader(
                icon: Icons.insights_rounded,
                title: 'Mes résultats',
                subtitle: 'QCM, activité clinique et niveau au même endroit',
              ),
              const SizedBox(height: 9),
              _QcmCanonicalStatsStrip(
                month: _qcmMonth,
                total: _qcmAll,
                loading: _loading,
              ),
              const SizedBox(height: 9),
              _PracticeHubProgressPanel(
                month: _month,
                year: _year,
                all: _all,
                level: level,
                loading: _loading,
              ),

              // 4. Profil et réglages : utiles mais volontairement secondaires.
              const SizedBox(height: 22),
              const _PracticeHubSectionHeader(
                icon: Icons.account_circle_rounded,
                title: 'Mon profil Practice',
                subtitle: 'Classement, succès et progression annuelle',
              ),
              const SizedBox(height: 9),
              _PracticeHubQuickActions(
                rankLabel: rankLabel,
                achievementLabel: '$unlocked/${_achievements.length}',
                yearLabel: '${_year.patients} patients',
                onLeaderboard: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        PracticeLeaderboardScreen(appState: widget.appState),
                  ),
                ),
                onAchievements: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        PracticeAchievementsScreen(appState: widget.appState),
                  ),
                ),
                onProgression: () => _showProgression(context),
              ),
              const SizedBox(height: 10),
              _LeaderboardPreferenceCard(
                value: _prefs.leaderboardOptIn,
                onChanged: (value) async {
                  setState(
                    () => _prefs = PracticePreferences(
                      leaderboardOptIn: value,
                      guardGoal: _prefs.guardGoal,
                    ),
                  );
                  await _service.savePreferences(
                    leaderboardOptIn: value,
                    guardGoal: _prefs.guardGoal,
                  );
                  await _load(silent: true);
                },
              ),
              const SizedBox(height: 14),
              const Text(
                'Les classements Practice et QCM reflètent uniquement l’activité documentée et les exercices pédagogiques. Ils ne mesurent pas la compétence clinique ni la qualité des soins.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: PracticeColors.textSecondary,
                  fontSize: 10.5,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
'''

s = s[:build_start] + new_build + s[build_end:]

primary_card_anchor = 'class _PracticeHubSectionHeader extends StatelessWidget {'
if 'class _PracticePrimaryActionCard extends StatelessWidget {' not in s:
    insert_at = s.find(primary_card_anchor)
    if insert_at < 0:
        raise SystemExit('Practice section header anchor not found')
    primary_card = r'''class _PracticePrimaryActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String meta;
  final Color accent;
  final VoidCallback onTap;

  const _PracticePrimaryActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.meta,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          height: 154,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withOpacity(.22),
                PracticeColors.surface.withOpacity(.96),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accent.withOpacity(.34)),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -8,
                top: -10,
                child: Icon(
                  icon,
                  size: 66,
                  color: accent.withOpacity(.07),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: accent.withOpacity(.14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(icon, color: accent, size: 20),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.arrow_forward_rounded,
                        color: accent.withOpacity(.92),
                        size: 19,
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: PracticeColors.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: PracticeColors.textSecondary,
                      fontSize: 10.5,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: accent,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

'''
    s = s[:insert_at] + primary_card + s[insert_at:]

# Sanity checks: keep all existing business/service hooks intact.
required = (
    'await _service.syncPending()',
    '_service.summary(scope: \'month\')',
    '_qcmService.qcmSummary(period: \'all\')',
    'PracticeCaseFormScreen(',
    '_LeaderboardPreferenceCard(',
    'PracticeGuardScreen(',
    'PracticeQcmScreen()',
    'ClinicalCasesScreen()',
)
for token in required:
    if token not in s:
        raise SystemExit(f'required Practice hook missing after patch: {token}')

if s.count('class _PracticePrimaryActionCard extends StatelessWidget {') != 1:
    raise SystemExit('unexpected number of primary Practice action card classes')

PRACTICE.write_text(s)
print('Practice hub reorganized: Training > Guard > Results > Profile. Business logic preserved.')
