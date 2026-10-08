import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../models/app_user.dart';
import '../models/practice_models.dart';
import '../models/qcm_models.dart';
import '../services/practice_service.dart';
import '../services/clinical_case_service.dart';
import '../services/random_clinical_case_service.dart';
import '../state/app_state.dart';
import '../widgets/profile_avatar.dart';
import 'practice_qcm_screen.dart';
import 'clinical_cases_screen.dart';
import '../theme/screen_decor.dart';

abstract final class PracticeColors {
  static const background = Color(0xFF071526);
  static const surface = Color(0xFF10243A);
  static const elevated = Color(0xFF17314E);
  static const accent = Color(0xFF5BE7B0);
  static const gamePurple = Color(0xFF8B6CFF);
  static const gameBlue = Color(0xFF3295FF);
  static const gameGold = Color(0xFFFFD166);
  static const gamePink = Color(0xFFFF6FAE);
  static const text = Color(0xFFF5F8FF);
  static const textSecondary = Color(0xFFB9CBE0);
  static const line = Color(0xFF244B68);
  static const waiting = Color(0xFFF2AD45);
  static const specialist = Color(0xFF5AA8FF);
  static const discharged = Color(0xFF2BC878);
  static const hospitalized = Color(0xFFE25A56);
  static const prescription = Color(0xFF35C3D8);
}

const practiceSpecialties = <String>[
  'Chirurgie viscérale',
  'Orthopédie',
  'Cardiologie',
  'Neurologie',
  'Urologie',
  'ORL',
  'Gynécologie',
  'Réanimation',
  'Pneumologie',
  'Gastro-entérologie',
  'Néphrologie',
  'Endocrinologie',
  'Dermatologie',
  'Psychiatrie',
  'Pédiatrie',
  'Ophtalmologie',
  'Neurochirurgie',
  'Chirurgie thoracique',
  'Chirurgie vasculaire',
  'Maladies infectieuses',
  'Médecine interne',
  'Autre',
];

class PracticeScreen extends StatefulWidget {
  final AppState appState;
  const PracticeScreen({super.key, required this.appState});

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> {
  final _service = PracticeService.instance;
  final _qcmService = ClinicalCaseService.instance;
  bool _loading = true;
  PracticeStats _guard = const PracticeStats();
  PracticeStats _month = const PracticeStats();
  PracticeStats _year = const PracticeStats();
  PracticeStats _all = const PracticeStats();
  PracticePreferences _prefs = const PracticePreferences();
  PracticeRanks _ranks = const PracticeRanks();
  QcmRanks _qcmMonth = const QcmRanks();
  QcmStats _qcmAll = const QcmStats();
  List<PracticeAchievement> _achievements = const [];
  List<int> _monthly = List<int>.filled(12, 0);
  String? _error;

  AppUser? get _me => widget.appState.currentUser;
  PracticeGuard? get _currentGuard {
    final me = _me;
    if (me == null) return null;
    return PracticeGuard.current(entries: widget.appState.planning, user: me);
  }

  @override
  void initState() {
    super.initState();
    _service.revision.addListener(_onRevision);
    _qcmService.revision.addListener(_onRevision);
    _load();
  }

  @override
  void dispose() {
    _service.revision.removeListener(_onRevision);
    _qcmService.revision.removeListener(_onRevision);
    super.dispose();
  }

  void _onRevision() {
    if (mounted) _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    final guard = _currentGuard;
    try {
      try {
        await _service.syncPending();
      } catch (_) {}
      final results = await Future.wait<dynamic>([
        if (guard != null)
          _service.summary(scope: 'guard', guardId: guard.id)
        else
          Future.value(const PracticeStats()),
        _service.summary(scope: 'month'),
        _service.summary(scope: 'year'),
        _service.summary(scope: 'all'),
        _service.preferences(),
        _service.ranks(period: 'month'),
        _service.achievements(),
        _service.monthlyCounts(year: DateTime.now().year),
        _qcmService.qcmRanks(period: 'month'),
        _qcmService.qcmSummary(period: 'all'),
      ]);
      if (!mounted) return;
      setState(() {
        _guard = results[0] as PracticeStats;
        _month = results[1] as PracticeStats;
        _year = results[2] as PracticeStats;
        _all = results[3] as PracticeStats;
        _prefs = results[4] as PracticePreferences;
        _ranks = results[5] as PracticeRanks;
        _achievements = results[6] as List<PracticeAchievement>;
        _monthly = results[7] as List<int>;
        _qcmMonth = results[8] as QcmRanks;
        _qcmAll = results[9] as QcmStats;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Certaines données Practice ne sont pas disponibles hors connexion.';
      });
    }
  }

  Future<void> _newCase() async {
    final guard = _currentGuard;
    if (guard == null) return;
    final number = await _service.nextPatientNumber(guard);
    if (!mounted) return;
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => PracticeCaseFormScreen(
          appState: widget.appState,
          guard: guard,
          suggestedNumber: number,
        ),
      ),
    );
    if (!mounted) return;
    await _load(silent: true);
    if (result == 'addAnother') _newCase();
  }

  Future<void> _newStandaloneCase() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => PracticeCaseFormScreen(
          appState: widget.appState,
          standalone: true,
        ),
      ),
    );
    if (!mounted) return;
    await _load(silent: true);
    if (result == 'addAnother') {
      await _newStandaloneCase();
    }
  }

  Future<void> _newRandomClinicalCase() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => PracticeCaseFormScreen(
          appState: widget.appState,
          standalone: true,
          autoGenerateRandomCase: true,
        ),
      ),
    );
    if (!mounted) return;
    await _load(silent: true);
    if (result == 'addAnother') await _newStandaloneCase();
  }

  Future<void> _editPublishedCase(String practiceCaseId) async {
    try {
      final existing = await _service.fetchCaseById(practiceCaseId);
      if (!mounted) return;
      if (existing == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ce cas ne peut pas être modifié depuis ce compte.')),
        );
        return;
      }
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => PracticeCaseFormScreen(
            appState: widget.appState,
            guard: null,
            existing: existing,
          ),
        ),
      );
      if (mounted) await _load(silent: true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d’ouvrir ce cas en modification.')),
      );
    }
  }

  Future<void> _editGoal() async {
    final controller = TextEditingController(
      text: _prefs.guardGoal?.toString() ?? '',
    );
    final value = await showDialog<int?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Objectif personnel de garde'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Nombre de patients',
            hintText: 'Ex. 8',
            helperText: 'Facultatif · entre 1 et 100',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, -1),
            child: const Text('Retirer'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = int.tryParse(controller.text.trim());
              if (parsed == null || parsed < 1 || parsed > 100) return;
              Navigator.pop(dialogContext, parsed);
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || !mounted) return;
    await _service.savePreferences(
      leaderboardOptIn: _prefs.leaderboardOptIn,
      guardGoal: value == -1 ? null : value,
    );
    await _load(silent: true);
  }

  @override
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
                crossAxisAlignment: CrossAxisAlignment.start,
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
                          builder: (_) => ClinicalCasesScreen(
                            onEditCase: _editPublishedCase,
                          ),
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
              const SizedBox(height: 9),
              _PracticePrimaryActionCard(
                icon: Icons.add_circle_outline_rounded,
                title: 'Ajouter un cas clinique',
                subtitle:
                    'Documenter un cas rencontré en dehors d’une garde aux urgences',
                meta: 'Hors garde',
                accent: PracticeColors.specialist,
                onTap: _newStandaloneCase,
              ),
              const SizedBox(height: 9),
              _PracticePrimaryActionCard(
                icon: Icons.auto_awesome_rounded,
                title: 'Génère-moi un cas au hasard',
                subtitle: 'Cas fictif créé par IA, modifiable avant publication',
                meta: 'IA · Aléatoire',
                accent: PracticeColors.gameGold,
                onTap: _newRandomClinicalCase,
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

  String _rankSubtitle(PracticeRanks ranks) {
    if (!ranks.leaderboardOptIn)
      return 'Participation au classement désactivée';
    if (!ranks.hasActivity)
      return 'Disponible après votre première activité Practice';
    final promo = ranks.promotionRank == null
        ? '—'
        : '${ranks.promotionRank}e dans votre promo';
    final global = ranks.globalRank == null
        ? '—'
        : '${ranks.globalRank}e toutes promotions';
    return '$promo · $global';
  }

  String _encouragement(PracticeGuard? guard) {
    if (_achievements.any(
      (a) =>
          a.unlockedAt != null &&
          a.unlockedAt!.isAfter(
            DateTime.now().subtract(const Duration(hours: 24)),
          ),
    )) {
      final latest = _achievements.firstWhere(
        (a) =>
            a.unlockedAt != null &&
            a.unlockedAt!.isAfter(
              DateTime.now().subtract(const Duration(hours: 24)),
            ),
      );
      return 'Succès débloqué : ${latest.name}.';
    }
    if (guard != null &&
        _prefs.guardGoal != null &&
        _guard.patients >= _prefs.guardGoal!) {
      return 'Objectif de garde atteint. Belle garde, continuez avec la même rigueur.';
    }
    if (guard != null && _guard.patients >= 10)
      return '${_guard.patients} observations cette garde. Beau travail.';
    if (_all.streak >= 3)
      return '🔥 Série de ${_all.streak} gardes documentées. Continuez régulièrement.';
    return 'Chaque malade est une nouvelle occasion d’apprendre.';
  }

  void _showProgression(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PracticeColors.background,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Progression annuelle',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(height: 220, child: _MonthlyBars(values: _monthly)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MiniMetric(label: 'Gardes', value: '${_year.guardsCount}'),
                  _MiniMetric(
                    label: 'Moyenne / garde',
                    value: _year.averagePerGuard.toStringAsFixed(1),
                  ),
                  _MiniMetric(
                    label: 'Meilleure garde',
                    value: '${_year.bestGuard}',
                  ),
                  _MiniMetric(
                    label: 'Observations complètes',
                    value: '${_year.completeObservations}',
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

class _PracticePrimaryActionCard extends StatelessWidget {
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

class _PracticeHubSectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _PracticeHubSectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: PracticeColors.accent.withOpacity(.10),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: PracticeColors.accent.withOpacity(.16)),
          ),
          child: Icon(icon, color: PracticeColors.accent, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: PracticeColors.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
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
            ],
          ),
        ),
      ],
    );
  }
}

class _PracticeHubTrainingGrid extends StatelessWidget {
  final Widget casesCard;
  final Widget qcmCard;

  const _PracticeHubTrainingGrid({
    required this.casesCard,
    required this.qcmCard,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 720) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: casesCard),
              const SizedBox(width: 10),
              Expanded(child: qcmCard),
            ],
          );
        }
        return Column(
          children: [casesCard, const SizedBox(height: 10), qcmCard],
        );
      },
    );
  }
}

class _PracticeHubProgressPanel extends StatelessWidget {
  final PracticeStats month;
  final PracticeStats year;
  final PracticeStats all;
  final PracticeLevel level;
  final bool loading;

  const _PracticeHubProgressPanel({
    required this.month,
    required this.year,
    required this.all,
    required this.level,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: PracticeColors.surface.withOpacity(.86),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: PracticeColors.line.withOpacity(.72)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  value: '${month.patients}',
                  label: 'Ce mois',
                  loading: loading,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: _StatCard(
                  value: '${year.patients}',
                  label: 'Cette année',
                  loading: loading,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: _StatCard(
                  value: '${all.patients}',
                  label: 'Total',
                  loading: loading,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          _LevelCard(level: level, xp: all.xp, streak: all.streak),
        ],
      ),
    );
  }
}

class _PracticeHubQuickActions extends StatelessWidget {
  final String rankLabel;
  final String achievementLabel;
  final String yearLabel;
  final VoidCallback onLeaderboard;
  final VoidCallback onAchievements;
  final VoidCallback onProgression;

  const _PracticeHubQuickActions({
    required this.rankLabel,
    required this.achievementLabel,
    required this.yearLabel,
    required this.onLeaderboard,
    required this.onAchievements,
    required this.onProgression,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _PracticeHubAction(
            icon: Icons.emoji_events_rounded,
            title: 'Classement',
            detail: rankLabel,
            accent: PracticeColors.gameGold,
            onTap: onLeaderboard,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _PracticeHubAction(
            icon: Icons.workspace_premium_rounded,
            title: 'Succès',
            detail: achievementLabel,
            accent: PracticeColors.gamePurple,
            onTap: onAchievements,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _PracticeHubAction(
            icon: Icons.insights_rounded,
            title: 'Année',
            detail: yearLabel,
            accent: PracticeColors.gameBlue,
            onTap: onProgression,
          ),
        ),
      ],
    );
  }
}

class _PracticeHubAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final Color accent;
  final VoidCallback onTap;

  const _PracticeHubAction({
    required this.icon,
    required this.title,
    required this.detail,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          height: 102,
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
          decoration: BoxDecoration(
            color: PracticeColors.surface.withOpacity(.90),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: PracticeColors.line.withOpacity(.72)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withOpacity(.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: accent, size: 18),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: PracticeColors.text,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: PracticeColors.textSecondary,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PracticeGameHeader extends StatelessWidget {
  final PracticeLevel level;
  final int xp;
  final int streak;
  final int unlocked;

  const _PracticeGameHeader({
    required this.level,
    required this.xp,
    required this.streak,
    required this.unlocked,
  });

  @override
  Widget build(BuildContext context) {
    final progress = level.progressFor(xp);
    final xpIntoLevel = level.xpIntoLevel(xp);
    final xpForLevel = level.xpForLevel;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5D47D8), Color(0xFF1D5AA4), Color(0xFF087B6D)],
          stops: [0, .58, 1],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(.14)),
        boxShadow: [
          BoxShadow(
            color: PracticeColors.gamePurple.withOpacity(.18),
            blurRadius: 22,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -8,
            top: -14,
            child: Icon(
              Icons.sports_esports_rounded,
              size: 82,
              color: Colors.white.withOpacity(.07),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 43,
                    height: 43,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(.13),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withOpacity(.14)),
                    ),
                    child: const Icon(
                      Icons.bolt_rounded,
                      color: PracticeColors.gameGold,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'PRACTICE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .8,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Niveau ${level.number} · ${level.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withOpacity(.83),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$xp XP',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 13),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 7,
                  backgroundColor: Colors.black.withOpacity(.18),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    PracticeColors.accent,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$xpIntoLevel / $xpForLevel XP vers le prochain niveau',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(.72),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _PracticeGameBadge(
                    icon: Icons.local_fire_department_rounded,
                    label: 'Série $streak',
                    color: PracticeColors.gamePink,
                  ),
                  const SizedBox(width: 6),
                  _PracticeGameBadge(
                    icon: Icons.workspace_premium_rounded,
                    label: '$unlocked',
                    color: PracticeColors.gameGold,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PracticeGameBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _PracticeGameBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.black.withOpacity(.15),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withOpacity(.34)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9.5,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

class _ClinicalCasesGameCard extends StatelessWidget {
  final VoidCallback onTap;
  const _ClinicalCasesGameCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                PracticeColors.gamePurple.withOpacity(.34),
                PracticeColors.surface,
                PracticeColors.gameBlue.withOpacity(.20),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: PracticeColors.gamePurple.withOpacity(.48),
            ),
            boxShadow: [
              BoxShadow(
                color: PracticeColors.gamePurple.withOpacity(.15),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                right: -8,
                top: -20,
                child: Icon(
                  Icons.psychology_alt_rounded,
                  size: 92,
                  color: Colors.white.withOpacity(.055),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          PracticeColors.gamePurple.withOpacity(.42),
                          PracticeColors.gameBlue.withOpacity(.28),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(
                        color: PracticeColors.gameGold.withOpacity(.28),
                      ),
                    ),
                    child: const Icon(
                      Icons.medical_information_rounded,
                      color: PracticeColors.gameGold,
                      size: 27,
                    ),
                  ),
                  const SizedBox(width: 13),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'CAS CLINIQUES',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                letterSpacing: .35,
                              ),
                            ),
                            SizedBox(width: 7),
                            Icon(
                              Icons.auto_awesome_rounded,
                              color: PracticeColors.gameGold,
                              size: 15,
                            ),
                          ],
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Ouvrir les dossiers anonymisés et leurs défis QCM',
                          style: TextStyle(
                            color: PracticeColors.textSecondary,
                            fontSize: 10.8,
                            height: 1.35,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_forward_rounded,
                      color: Colors.white,
                      size: 20,
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

class _QcmPracticeCard extends StatelessWidget {
  final QcmRanks stats;
  final bool loading;
  final VoidCallback onTap;

  const _QcmPracticeCard({
    required this.stats,
    required this.loading,
    required this.onTap,
  });

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
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                PracticeColors.gamePurple.withOpacity(.30),
                PracticeColors.surface,
                PracticeColors.gameBlue.withOpacity(.16),
              ],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: PracticeColors.gamePurple.withOpacity(.44),
            ),
            boxShadow: [
              BoxShadow(
                color: PracticeColors.gamePurple.withOpacity(.16),
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: PracticeColors.elevated,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.quiz_rounded,
                      color: PracticeColors.accent,
                    ),
                  ),
                  const SizedBox(width: 11),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Défi QCM · cas cliniques',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Statistiques du mois et classement QCM',
                          style: TextStyle(
                            color: PracticeColors.textSecondary,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: PracticeColors.textSecondary,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _QcmMiniMetric(
                      value: loading ? '—' : '${stats.answered}',
                      label: 'Répondus',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _QcmMiniMetric(
                      value: loading ? '—' : '${stats.correct}',
                      label: 'Corrects',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _QcmMiniMetric(
                      value: loading
                          ? '—'
                          : '${stats.accuracy.toStringAsFixed(0)}%',
                      label: 'Réussite',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 11),
              Row(
                children: [
                  const Icon(
                    Icons.emoji_events_outlined,
                    size: 17,
                    color: PracticeColors.accent,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      rankText,
                      style: const TextStyle(
                        color: PracticeColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Text(
                    'Voir le classement',
                    style: TextStyle(
                      color: PracticeColors.accent,
                      fontSize: 10.5,
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

class _QcmMiniMetric extends StatelessWidget {
  final String value;
  final String label;
  const _QcmMiniMetric({required this.value, required this.label});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
    decoration: BoxDecoration(
      color: PracticeColors.background.withOpacity(0.34),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: PracticeColors.textSecondary,
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class PracticeGuardScreen extends StatefulWidget {
  final AppState appState;
  final PracticeGuard? guard;
  const PracticeGuardScreen({super.key, required this.appState, this.guard});

  @override
  State<PracticeGuardScreen> createState() => _PracticeGuardScreenState();
}

class _PracticeGuardScreenState extends State<PracticeGuardScreen> {
  final _service = PracticeService.instance;
  final _search = TextEditingController();
  bool _loading = true;
  bool _loadingMore = false;
  String _scope = 'guard';
  String _filter = 'all';
  String _sort = 'recent';
  int _offset = 0;
  static const _pageSize = 50;
  bool _hasMore = false;
  List<PracticeCase> _cases = <PracticeCase>[];
  PracticeStats _stats = const PracticeStats();

  @override
  void initState() {
    super.initState();
    if (widget.guard == null) _scope = 'month';
    _search.addListener(() => setState(() {}));
    _service.revision.addListener(_revision);
    _load();
  }

  @override
  void dispose() {
    _service.revision.removeListener(_revision);
    _search.dispose();
    super.dispose();
  }

  void _revision() {
    if (mounted) _load(silent: true);
  }

  String? get _status => _filter == 'all' ? null : _filter;

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      await _service.syncPending();
    } catch (_) {}
    final scopeForApi = _scope == 'guard' ? 'guard' : _scope;
    final guardId = _scope == 'guard' ? widget.guard?.id : null;
    try {
      final results = await Future.wait<dynamic>([
        _service.fetchCases(
          guardId: guardId,
          scope: scopeForApi,
          status: _status,
          limit: _pageSize,
        ),
        _service.summary(scope: scopeForApi, guardId: guardId),
      ]);
      if (!mounted) return;
      final rows = (results[0] as List<PracticeCase>)
          .where((item) => !item.isDraft)
          .toList();
      setState(() {
        _cases = rows;
        _stats = results[1] as PracticeStats;
        _offset = rows.length;
        _hasMore = rows.length >= _pageSize;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _more() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final rows = await _service.fetchCases(
      guardId: _scope == 'guard' ? widget.guard?.id : null,
      scope: _scope,
      status: _status,
      offset: _offset,
      limit: _pageSize,
      includePending: false,
    );
    if (!mounted) return;
    setState(() {
      _cases.addAll(rows.where((item) => !item.isDraft));
      _offset += rows.length;
      _hasMore = rows.length >= _pageSize;
      _loadingMore = false;
    });
  }

  Future<void> _newCase() async {
    final guard = widget.guard;
    if (guard == null) return;
    final number = await _service.nextPatientNumber(guard);
    if (!mounted) return;
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => PracticeCaseFormScreen(
          appState: widget.appState,
          guard: guard,
          suggestedNumber: number,
        ),
      ),
    );
    if (!mounted) return;
    await _load(silent: true);
    if (result == 'addAnother') _newCase();
  }

  List<PracticeCase> get _visible {
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
        item.arrivalTime ??
        item.createdAt ??
        DateTime.tryParse(item.guardDate) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    rows.sort((a, b) {
      switch (_sort) {
        case 'oldest':
          return effectiveTime(a).compareTo(effectiveTime(b));
        case 'patient':
          return a.patientNumber.compareTo(b.patientNumber);
        case 'arrival':
          final aTime = a.arrivalTime;
          final bTime = b.arrivalTime;
          if (aTime == null && bTime == null)
            return a.patientNumber.compareTo(b.patientNumber);
          if (aTime == null) return 1;
          if (bTime == null) return -1;
          return aTime.compareTo(bTime);
        default:
          return effectiveTime(b).compareTo(effectiveTime(a));
      }
    });
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    return DecorScaffold(
      scene: ScreenDecorScene.practice,
      backgroundColor: PracticeColors.background,
      appBar: AppBar(
        backgroundColor: PracticeColors.background,
        foregroundColor: Colors.white,
        title: Text(
          widget.guard == null
              ? 'Practice · Historique'
              : 'Practice · Ma garde',
        ),
      ),
      floatingActionButton: widget.guard == null
          ? null
          : FloatingActionButton(
              onPressed: _newCase,
              tooltip: 'Ajouter un malade',
              backgroundColor: PracticeColors.accent,
              foregroundColor: PracticeColors.background,
              child: const Icon(Icons.add_rounded, size: 28),
            ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: PracticeColors.accent,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 100),
          children: [
            if (widget.guard != null) ...[
              Text(
                widget.guard!.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.guard!.timeLabel,
                style: const TextStyle(
                  color: PracticeColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
            ],
            _HistorySummaryCard(stats: _stats),
            const SizedBox(height: 14),
            SizedBox(
              height: 50,
              child: TextField(
                controller: _search,
                style: const TextStyle(color: Colors.white, fontSize: 13.5),
                decoration: _historySearchDecoration(),
              ),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(right: 18),
              child: Row(
                children: <Widget>[
                  if (widget.guard != null) _scopeChip('guard', 'Cette garde'),
                  _scopeChip('month', 'Ce mois'),
                  _scopeChip('year', 'Cette année'),
                  _scopeChip('all', 'Toutes'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(right: 18),
              child: Row(
                children: [
                  _filterChip('all', 'Tous'),
                  _filterChip('waiting', 'En attente'),
                  _filterChip('specialist', 'Avis'),
                  _filterChip('discharged', 'Sortants'),
                  _filterChip('hospitalized', 'Hospitalisés'),
                  _filterChip('prescription', 'Ordonnance faite'),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Patients · ${_visible.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  initialValue: _sort,
                  onSelected: (value) => setState(() => _sort = value),
                  color: PracticeColors.surface,
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'recent', child: Text('Plus récents')),
                    PopupMenuItem(value: 'oldest', child: Text('Plus anciens')),
                    PopupMenuItem(value: 'patient', child: Text('Patient #')),
                    PopupMenuItem(
                      value: 'arrival',
                      child: Text('Heure d’arrivée'),
                    ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: PracticeColors.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.sort_rounded,
                          color: PracticeColors.textSecondary,
                          size: 17,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Trier',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(
                    color: PracticeColors.accent,
                  ),
                ),
              )
            else if (_visible.isEmpty)
              const _PracticeEmpty(
                text: 'Aucun patient ne correspond à ces critères.',
              )
            else
              ..._visible.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: _PatientTile(
                    value: item,
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PracticeCaseFormScreen(
                            appState: widget.appState,
                            guard: widget.guard,
                            existing: item,
                          ),
                        ),
                      );
                      if (mounted) _load(silent: true);
                    },
                  ),
                ),
              ),
            if (_hasMore) ...[
              const SizedBox(height: 6),
              OutlinedButton(
                onPressed: _loadingMore ? null : _more,
                style: OutlinedButton.styleFrom(
                  foregroundColor: PracticeColors.accent,
                  side: const BorderSide(color: PracticeColors.line),
                ),
                child: Text(_loadingMore ? 'Chargement…' : 'Charger plus'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _scopeChip(String key, String label) {
    final selected = _scope == key;
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: ChoiceChip(
        selected: selected,
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        label: Text(label),
        onSelected: (_) {
          setState(() => _scope = key);
          _load();
        },
        selectedColor: PracticeColors.elevated,
        backgroundColor: PracticeColors.surface,
        labelStyle: TextStyle(
          color: selected ? PracticeColors.accent : PracticeColors.text,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
        side: BorderSide(
          color: selected
              ? PracticeColors.accent.withOpacity(.32)
              : Colors.transparent,
        ),
      ),
    );
  }

  Widget _filterChip(String key, String label) {
    final selected = _filter == key;
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: FilterChip(
        selected: selected,
        visualDensity: VisualDensity.compact,
        label: Text(label),
        onSelected: (_) {
          setState(() => _filter = key);
          _load();
        },
        selectedColor: PracticeColors.elevated,
        backgroundColor: PracticeColors.surface,
        checkmarkColor: PracticeColors.accent,
        labelStyle: TextStyle(
          color: selected ? PracticeColors.accent : PracticeColors.text,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
        side: BorderSide(
          color: selected
              ? PracticeColors.accent.withOpacity(.28)
              : PracticeColors.line.withOpacity(.38),
        ),
      ),
    );
  }
}

class PracticeCaseFormScreen extends StatefulWidget {
  final AppState appState;
  final PracticeGuard? guard;
  final PracticeCase? existing;
  final int? suggestedNumber;
  final bool standalone;
  final bool autoGenerateRandomCase;
  const PracticeCaseFormScreen({
    super.key,
    required this.appState,
    this.guard,
    this.existing,
    this.suggestedNumber,
    this.standalone = false,
    this.autoGenerateRandomCase = false,
  });

  @override
  State<PracticeCaseFormScreen> createState() => _PracticeCaseFormScreenState();
}

class _PracticeCaseFormScreenState extends State<PracticeCaseFormScreen> {
  final _service = PracticeService.instance;
  final _formKey = GlobalKey<FormState>();
  final stt.SpeechToText _speech = stt.SpeechToText();
  TextEditingController? _dictatingController;
  String? _dictatingLabel;
  bool _speechReady = false;
  bool _speechInitializing = false;
  String? _speechLocaleId;
  Timer? _speechRestartTimer;
  bool _dictationRequested = false;
  bool _speechStarting = false;
  int _speechSession = 0;
  int _consecutiveSpeechErrors = 0;

  static const List<String> _medicalSpeechHints = <String>[
    'douleur abdominale',
    'épigastre',
    'hypochondre droit',
    'hypochondre gauche',
    'fosse iliaque droite',
    'fosse iliaque gauche',
    'point de McBurney',
    'défense abdominale',
    'contracture abdominale',
    'nausées',
    'vomissements',
    'diarrhée',
    'constipation',
    'dyspnée',
    'dysurie',
    'hématurie',
    'hématémèse',
    'méléna',
    'tachycardie',
    'hypotension',
    'hypertension',
    'saturation',
    'auscultation',
    'appendicite',
    'cholécystite',
    'pancréatite',
    'péritonite',
    'occlusion intestinale',
    'scanner abdominal',
    'échographie abdominale',
    'TDM',
    'IRM',
    'ECG',
    'CRP',
    'leucocytes',
    'hémoglobine',
    'créatinine',
    'natrémie',
    'kaliémie',
    'troponine',
    'conduite à tenir',
  ];
  final _age = TextEditingController();
  final _location = TextEditingController();
  final _chiefComplaint = TextEditingController();
  final _interrogatoire = TextEditingController();
  final _personalSurgical = TextEditingController();
  final _personalMedical = TextEditingController();
  final _familySurgical = TextEditingController();
  final _familyMedical = TextEditingController();
  final _consultationReason = TextEditingController();
  final _illnessHistory = TextEditingController();
  final _clinicalExam = TextEditingController();
  final _complementary = TextEditingController();
  final _imaging = TextEditingController();
  final _assessment = TextEditingController();
  final _plan = TextEditingController();

  Timer? _autosave;
  bool _saving = false;
  bool _restoring = true;
  bool _generatingRandomCase = false;
  bool _generatedByAi = false;
  String _syncLabel = 'Brouillon local';
  String? _sex;
  DateTime? _arrivalTime;
  bool _specialist = false;
  String? _specialistService;
  bool _specialistDone = false;
  bool _waiting = false;
  bool _prescription = false;
  bool _discharged = false;
  bool _hospitalized = false;
  String? _hospitalizationService;
  late String _clientId;
  late int _patientNumber;
  late DateTime _standaloneDate;

  List<TextEditingController> get _controllers => [
    _age,
    _location,
    _chiefComplaint,
    _interrogatoire,
    _personalSurgical,
    _personalMedical,
    _familySurgical,
    _familyMedical,
    _consultationReason,
    _illnessHistory,
    _clinicalExam,
    _complementary,
    _imaging,
    _assessment,
    _plan,
  ];

  AppUser? get _me => widget.appState.currentUser;
  bool get _isStandalone =>
      widget.standalone || widget.existing?.isStandalone == true;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _clientId =
        existing?.clientId ??
        '${DateTime.now().microsecondsSinceEpoch}-${_me?.id ?? 'local'}';
    _patientNumber = existing?.patientNumber ?? widget.suggestedNumber ?? 1;
    _standaloneDate = DateTime.tryParse(existing?.guardDate ?? '') ??
        DateTime.now();
    if (existing != null) _apply(existing);
    for (final controller in _controllers) {
      controller.addListener(_changed);
    }
    _restoreDraft();
  }

  @override
  void dispose() {
    _autosave?.cancel();
    _speechRestartTimer?.cancel();
    _dictationRequested = false;
    _speechSession++;
    if (_speech.isListening) {
      unawaited(_speech.cancel());
    }
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _restoreDraft() async {
    final me = _me;
    final guardId = widget.existing?.guardId ??
        widget.guard?.id ??
        (_isStandalone ? practiceStandaloneLocalGuardId : null);
    if (me == null || guardId == null) {
      if (mounted) setState(() => _restoring = false);
      return;
    }
    final draft = await _service.loadLocalDraft(
      userId: me.id,
      guardId: guardId,
    );
    if (draft != null) {
      final relevant = widget.existing == null
          ? draft.id == null
          : draft.clientId == widget.existing!.clientId;
      if (relevant) {
        _clientId = draft.clientId;
        _patientNumber = draft.patientNumber;
        _apply(draft);
        if (mounted) setState(() => _syncLabel = 'Brouillon restauré');
      }
    }
    if (mounted) setState(() => _restoring = false);
    if (widget.autoGenerateRandomCase && widget.existing == null &&
        _isStandalone && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_generateRandomCase());
      });
    }
  }

  void _apply(PracticeCase value) {
    _age.text = value.age?.toString() ?? '';
    _location.text = value.location ?? '';
    _chiefComplaint.text = value.chiefComplaint ?? '';
    _interrogatoire.text = value.interrogatoire;
    _personalSurgical.text = value.personalSurgicalHistory;
    _personalMedical.text = value.personalMedicalHistory;
    _familySurgical.text = value.familySurgicalHistory;
    _familyMedical.text = value.familyMedicalHistory;
    _consultationReason.text = value.consultationReason;
    _illnessHistory.text = value.illnessHistory;
    _clinicalExam.text = value.clinicalExam;
    _complementary.text = value.complementaryExams;
    _imaging.text = value.imagingConclusion;
    _assessment.text = value.assessment;
    _plan.text = value.plan;
    _generatedByAi = value.consultationReason.startsWith('[SIMULATION IA]');
    _sex = value.sex;
    _arrivalTime = value.arrivalTime;
    _specialist = value.specialistOpinionRequested;
    _specialistService = value.specialistService;
    _specialistDone = value.specialistOpinionDone;
    _waiting = value.waiting;
    _prescription = value.prescriptionDone;
    _discharged = value.discharged;
    _hospitalized = value.hospitalized;
    _hospitalizationService = value.hospitalizationService;
  }

  Future<void> _generateRandomCase() async {
    if (_generatingRandomCase || _saving || _restoring ||
        !_isStandalone || widget.existing != null) return;

    // Never silently overwrite a restored or user-edited draft.
    if (_controllers.any((field) => field.text.trim().isNotEmpty)) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Remplacer le contenu actuel ?'),
          content: const Text(
            'Le nouveau cas remplacera les rubriques déjà remplies. '
            'La génération ne publie aucun dossier automatiquement.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Générer'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => _generatingRandomCase = true);
    try {
      final generated = await RandomClinicalCaseService.instance.generate();
      if (!mounted) return;
      _restoring = true;
      try {
        _age.text = generated.age.toString();
        _sex = generated.sex;
        _location.text = generated.text('location');
        _chiefComplaint.text = generated.text('chief_complaint');
        _interrogatoire.text = generated.text('interrogatoire');
        _personalSurgical.text = generated.text('personal_surgical_history');
        _personalMedical.text = generated.text('personal_medical_history');
        _familySurgical.text = generated.text('family_surgical_history');
        _familyMedical.text = generated.text('family_medical_history');
        _consultationReason.text = generated.text('consultation_reason');
        _illnessHistory.text = generated.text('illness_history');
        _clinicalExam.text = generated.text('clinical_exam');
        _complementary.text = generated.text('complementary_exams');
        _imaging.text = generated.text('imaging_conclusion');
        _assessment.text = generated.text('assessment');
        _plan.text = generated.text('plan');
        _arrivalTime = null;
        _specialist = generated.flag('specialist_opinion_requested');
        final specialty = generated.text('specialist_service');
        _specialistService = _specialist
            ? (practiceSpecialties.contains(specialty) ? specialty : 'Autre')
            : null;
        _specialistDone = _specialist &&
            generated.flag('specialist_opinion_done');
        _waiting = generated.flag('waiting');
        _prescription = generated.flag('prescription_done');
        _discharged = generated.flag('discharged');
        _hospitalized = generated.flag('hospitalized');
        final destination = generated.text('hospitalization_service');
        _hospitalizationService = _hospitalized
            ? (practiceSpecialties.contains(destination) ? destination : 'Autre')
            : null;
      } finally {
        _restoring = false;
      }
      setState(() {
        _generatedByAi = true;
        _syncLabel = 'Cas fictif IA · à relire';
      });
      _changed(); // Draft-only until the physician saves it manually.
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Génération impossible : $error')),
      );
    } finally {
      if (mounted) setState(() => _generatingRandomCase = false);
    }
  }

  Future<bool> _ensureSpeechReady() async {
    if (_speechReady) return true;
    if (_speechInitializing) return false;
    if (mounted) setState(() => _speechInitializing = true);
    try {
      final available = await _speech.initialize(
        onStatus: _handleSpeechStatus,
        onError: _handleSpeechError,
        finalTimeout: const Duration(seconds: 3),
        options: kIsWeb
            ? <stt.SpeechConfigOption>[stt.SpeechToText.webDoNotAggregate]
            : null,
      );
      if (!available) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'La dictée vocale est indisponible. Autorisez le microphone et la reconnaissance vocale, ou utilisez un navigateur compatible.',
              ),
            ),
          );
        }
        return false;
      }

      final locales = await _speech.locales();
      final systemLocale = await _speech.systemLocale();

      String normalizedLocale(String value) =>
          value.toLowerCase().replaceAll('-', '_');

      String? exactLocale(String wanted) {
        final normalizedWanted = normalizedLocale(wanted);
        for (final locale in locales) {
          if (normalizedLocale(locale.localeId) == normalizedWanted) {
            return locale.localeId;
          }
        }
        return null;
      }

      String? french;
      final systemId = systemLocale?.localeId;
      if (systemId != null && normalizedLocale(systemId).startsWith('fr')) {
        french = exactLocale(systemId);
      }
      french ??= exactLocale('fr_FR');
      french ??= exactLocale('fr_MA');
      if (french == null) {
        for (final locale in locales) {
          if (normalizedLocale(locale.localeId).startsWith('fr')) {
            french = locale.localeId;
            break;
          }
        }
      }
      _speechLocaleId = french ?? systemId;
      _speechReady = true;
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impossible d’activer la dictée vocale : $e')),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _speechInitializing = false);
    }
  }

  void _handleSpeechStatus(String status) {
    if (mounted) setState(() {});
    if (!_dictationRequested) return;
    final normalized = status.toLowerCase();
    if (normalized == stt.SpeechToText.doneStatus.toLowerCase() ||
        normalized == stt.SpeechToText.notListeningStatus.toLowerCase()) {
      _scheduleSpeechRestart();
    }
  }

  bool _isRecoverableSpeechError(String error) {
    final normalized = error.toLowerCase();
    return normalized.contains('no_match') ||
        normalized.contains('speech_timeout') ||
        normalized.contains('retry') ||
        normalized.contains('busy') ||
        normalized.contains('network_timeout') ||
        normalized.contains('server_disconnected') ||
        normalized == 'error_network' ||
        normalized == 'error_server';
  }

  String _friendlySpeechError(String error) {
    final normalized = error.toLowerCase();
    if (normalized.contains('permission')) {
      return 'Microphone non autorisé. Activez l’accès au micro pour GardeFlow dans les réglages de l’appareil.';
    }
    if (normalized.contains('language_not_supported') ||
        normalized.contains('language_unavailable')) {
      return 'La reconnaissance vocale française n’est pas disponible sur cet appareil. Installez ou activez le français dans les réglages de reconnaissance vocale.';
    }
    if (normalized.contains('recognizer_disabled')) {
      return 'La reconnaissance vocale est désactivée sur cet appareil.';
    }
    if (normalized.contains('too_many_requests')) {
      return 'Le service de reconnaissance vocale reçoit trop de requêtes. Réessayez dans quelques instants.';
    }
    if (normalized.contains('network')) {
      return 'La reconnaissance vocale a perdu la connexion. Vérifiez le réseau puis relancez le micro.';
    }
    return 'Dictée interrompue : ${error.replaceAll('_', ' ')}';
  }

  void _handleSpeechError(dynamic error) {
    final message = error.errorMsg?.toString() ?? error.toString();
    if (_dictationRequested && _isRecoverableSpeechError(message)) {
      _consecutiveSpeechErrors++;
      if (_consecutiveSpeechErrors <= 4) {
        if (_speech.isListening) unawaited(_speech.cancel());
        final delay = Duration(
          milliseconds: 350 + ((_consecutiveSpeechErrors - 1) * 250),
        );
        _scheduleSpeechRestart(delay: delay);
        return;
      }
    }

    _dictationRequested = false;
    _speechRestartTimer?.cancel();
    _speechSession++;
    if (!mounted) return;
    setState(() {
      _dictatingController = null;
      _dictatingLabel = null;
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(_friendlySpeechError(message))));
  }

  String _normalizeSpeechTranscript(String raw) {
    final cleaned = raw
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAllMapped(
          RegExp(r'\s+([,.;:!?…])'),
          (match) => match.group(1)!,
        );
    if (!kIsWeb || cleaned.isEmpty) return cleaned;

    String keyOf(String token) => token.toLowerCase().replaceAll(
      RegExp(r'^[\s.,;:!?…]+|[\s.,;:!?…]+$'),
      '',
    );

    // Le mode webDoNotAggregate évite le principal bug de doublons de Chrome
    // Android. On conserve seulement une protection prudente contre la
    // répétition immédiate d’un bloc entier, sans supprimer les vrais mots
    // répétés (« très très », « non non », etc.).
    final tokens = cleaned.split(' ');
    var maxBlock = tokens.length ~/ 2;
    if (maxBlock > 16) maxBlock = 16;
    for (var block = maxBlock; block >= 3; block--) {
      var index = 0;
      while (index + (block * 2) <= tokens.length) {
        var identicalBlocks = true;
        for (var offset = 0; offset < block; offset++) {
          if (keyOf(tokens[index + offset]) !=
              keyOf(tokens[index + block + offset])) {
            identicalBlocks = false;
            break;
          }
        }
        if (identicalBlocks) {
          tokens.removeRange(index + block, index + (block * 2));
        } else {
          index++;
        }
      }
    }

    return tokens.join(' ').trim();
  }

  String _combineSpeechSegments(String committed, String incoming) {
    final current = committed.trim();
    final next = incoming.trim();
    if (current.isEmpty) return next;
    if (next.isEmpty) return current;

    final currentKey = current.toLowerCase();
    final nextKey = next.toLowerCase();
    if (nextKey.startsWith('$currentKey ')) return next;
    return '$current $next';
  }

  void _scheduleSpeechRestart({
    Duration delay = const Duration(milliseconds: 450),
  }) {
    if (!_dictationRequested || !mounted) return;
    final controller = _dictatingController;
    final label = _dictatingLabel;
    if (controller == null || label == null) return;

    _speechRestartTimer?.cancel();
    _speechRestartTimer = Timer(delay, () {
      if (!mounted ||
          !_dictationRequested ||
          !identical(_dictatingController, controller)) {
        return;
      }
      unawaited(_startSpeechSession(controller, label));
    });
  }

  Future<void> _startSpeechSession(
    TextEditingController controller,
    String label,
  ) async {
    if (!mounted ||
        !_dictationRequested ||
        !identical(_dictatingController, controller) ||
        _speechStarting ||
        _speech.isListening) {
      return;
    }

    _speechRestartTimer?.cancel();
    _speechStarting = true;
    final session = ++_speechSession;
    final sessionBase = controller.text.trimRight();
    var committedSpeech = '';
    String? lastFinalChunk;
    DateTime? lastFinalAt;

    try {
      final started = await _speech.listen(
        onResult: (result) {
          if (!mounted ||
              !_dictationRequested ||
              session != _speechSession ||
              !identical(_dictatingController, controller)) {
            return;
          }

          final words = _normalizeSpeechTranscript(result.recognizedWords);
          if (words.isEmpty) return;
          _consecutiveSpeechErrors = 0;
          _speech.changePauseFor(Duration(seconds: kIsWeb ? 5 : 7));

          var speechForDisplay = words;
          if (result.finalResult) {
            final now = DateTime.now();
            final rapidDuplicate =
                lastFinalChunk != null &&
                lastFinalChunk!.toLowerCase() == words.toLowerCase() &&
                lastFinalAt != null &&
                now.difference(lastFinalAt!).inMilliseconds < 1200;
            if (!rapidDuplicate) {
              committedSpeech = _combineSpeechSegments(committedSpeech, words);
              lastFinalChunk = words;
              lastFinalAt = now;
            }
            speechForDisplay = committedSpeech;
          } else if (committedSpeech.isNotEmpty) {
            speechForDisplay = _combineSpeechSegments(committedSpeech, words);
          }

          if (speechForDisplay.isEmpty) return;
          final separator = sessionBase.isEmpty ? '' : ' ';
          final nextText = '$sessionBase$separator$speechForDisplay'
              .trimRight();
          controller.value = TextEditingValue(
            text: nextText,
            selection: TextSelection.collapsed(offset: nextText.length),
          );
          setState(() {});
        },
        listenOptions: stt.SpeechListenOptions(
          localeId: _speechLocaleId,
          listenFor: const Duration(minutes: 3),
          pauseFor: Duration(seconds: kIsWeb ? 7 : 10),
          partialResults: true,
          cancelOnError: false,
          onDevice: false,
          listenMode: stt.ListenMode.dictation,
          autoPunctuation: true,
          enableHapticFeedback: false,
          contextualPhrases: _medicalSpeechHints,
        ),
      );
      if (started == false && _dictationRequested) {
        _scheduleSpeechRestart();
      }
    } catch (e) {
      if (!mounted ||
          !_dictationRequested ||
          session != _speechSession ||
          !identical(_dictatingController, controller)) {
        return;
      }
      _consecutiveSpeechErrors++;
      if (_consecutiveSpeechErrors <= 4) {
        _scheduleSpeechRestart(
          delay: Duration(milliseconds: 400 + (_consecutiveSpeechErrors * 250)),
        );
      } else {
        _dictationRequested = false;
        setState(() {
          _dictatingController = null;
          _dictatingLabel = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impossible de relancer la dictée : $e')),
        );
      }
    } finally {
      _speechStarting = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _stopDictation() async {
    _dictationRequested = false;
    _speechRestartTimer?.cancel();
    _speechSession++;
    if (_speech.isListening) await _speech.stop();
    if (!mounted) return;
    setState(() {
      _dictatingController = null;
      _dictatingLabel = null;
    });
  }

  Future<void> _toggleDictation(
    TextEditingController controller,
    String label,
  ) async {
    if (_speechInitializing || _speechStarting) return;

    if (identical(_dictatingController, controller) && _dictationRequested) {
      await _stopDictation();
      return;
    }

    if (_dictationRequested || _speech.isListening) {
      await _stopDictation();
    }
    if (!await _ensureSpeechReady()) return;

    _consecutiveSpeechErrors = 0;
    _dictationRequested = true;
    if (mounted) {
      setState(() {
        _dictatingController = controller;
        _dictatingLabel = label;
      });
    }
    await _startSpeechSession(controller, label);
  }

  void _changed() {
    if (_restoring) return;
    _autosave?.cancel();
    if (mounted) setState(() => _syncLabel = 'Sauvegarde…');
    _autosave = Timer(const Duration(milliseconds: 550), _autosaveNow);
  }

  Future<void> _autosaveNow() async {
    final draft = _buildCase(isDraft: true);
    if (draft == null) return;
    await _service.saveLocalDraft(draft);
    if (mounted) setState(() => _syncLabel = 'Brouillon sauvegardé');
  }

  PracticeCase? _buildCase({required bool isDraft}) {
    final me = _me;
    final standalone = _isStandalone;
    final guardId = widget.existing?.guardId ??
        widget.guard?.id ??
        (standalone ? practiceStandaloneLocalGuardId : null);
    final guardDate = widget.existing?.guardDate ??
        widget.guard?.dateStr ??
        (standalone ? DateFormat('yyyy-MM-dd').format(_standaloneDate) : null);
    final guardShiftId = widget.existing?.guardShiftId ??
        widget.guard?.shiftId ??
        (standalone ? practiceStandaloneEncounterContext : null);
    if (me == null ||
        guardId == null ||
        guardDate == null ||
        guardShiftId == null) {
      return null;
    }
    return PracticeCase(
      id: widget.existing?.id,
      userId: me.id,
      encounterContext: standalone
          ? practiceStandaloneEncounterContext
          : practiceEmergencyEncounterContext,
      guardId: guardId,
      guardDate: guardDate,
      guardShiftId: guardShiftId,
      clientId: _clientId,
      patientNumber: _patientNumber,
      age: int.tryParse(_age.text.trim()),
      sex: _sex,
      arrivalTime: _arrivalTime,
      location: _location.text,
      chiefComplaint: _chiefComplaint.text,
      interrogatoire: _interrogatoire.text,
      personalSurgicalHistory: _personalSurgical.text,
      personalMedicalHistory: _personalMedical.text,
      familySurgicalHistory: _familySurgical.text,
      familyMedicalHistory: _familyMedical.text,
      consultationReason: _consultationReason.text,
      illnessHistory: _illnessHistory.text,
      clinicalExam: _clinicalExam.text,
      complementaryExams: _complementary.text,
      imagingConclusion: _imaging.text,
      assessment: _assessment.text,
      plan: _plan.text,
      specialistOpinionRequested: _specialist,
      specialistService: _specialist ? _specialistService : null,
      specialistOpinionDone: _specialist && _specialistDone,
      waiting: _waiting,
      prescriptionDone: _prescription,
      discharged: _discharged,
      hospitalized: _hospitalized,
      hospitalizationService: _hospitalized ? _hospitalizationService : null,
      isDraft: isDraft,
    );
  }

  Future<void> _save({required bool addAnother}) async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    final value = _buildCase(isDraft: false);
    if (value == null) return;
    if (!value.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ajoutez un motif de consultation et au moins une section clinique : histoire, examen, bilan ou conduite à tenir.',
          ),
        ),
      );
      return;
    }
    setState(() {
      _saving = true;
      _syncLabel = 'Synchronisation…';
    });
    try {
      final result = await _service.saveValidated(value);
      await _service.clearLocalDraft(
        userId: value.userId,
        guardId: value.guardId,
      );
      if (!mounted) return;
      final completeBonus = value.isComplete
          ? ' · Observation complète : +2 XP'
          : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.pendingSync
                ? (_isStandalone
                    ? 'Cas clinique enregistré localement · À synchroniser'
                    : 'Observation enregistrée localement · À synchroniser')
                : (_isStandalone
                    ? 'Cas clinique ajouté à Practice'
                    : 'Observation enregistrée : +10 XP$completeBonus'),
          ),
        ),
      );
      Navigator.pop(context, addAnother ? 'addAnother' : 'saved');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _syncLabel = 'Brouillon sauvegardé';
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Enregistrement impossible : $e')));
    }
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer cette observation ?'),
        content: Text('${existing.patientLabel} sera supprimé de Practice.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _service.deleteCase(existing);
    if (mounted) Navigator.pop(context, 'deleted');
  }

  Future<void> _pickStandaloneDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _standaloneDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _standaloneDate = picked;
      if (_arrivalTime != null) {
        _arrivalTime = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _arrivalTime!.hour,
          _arrivalTime!.minute,
        );
      }
    });
    _changed();
  }

  Future<void> _pickArrivalTime() async {
    final initial = _arrivalTime ?? DateTime.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (picked == null || !mounted) return;
    final day = _isStandalone ? _standaloneDate : DateTime.now();
    setState(
      () => _arrivalTime = DateTime(
        day.year,
        day.month,
        day.day,
        picked.hour,
        picked.minute,
      ),
    );
    _changed();
  }

  @override
  Widget build(BuildContext context) {
    final number = _patientNumber.toString().padLeft(3, '0');
    return DecorScaffold(
      scene: ScreenDecorScene.practice,
      backgroundColor: PracticeColors.background,
      appBar: AppBar(
        backgroundColor: PracticeColors.background,
        foregroundColor: Colors.white,
        title: Text(
          _isStandalone
              ? (widget.existing == null
                  ? 'Nouveau cas clinique'
                  : 'Modifier le cas clinique')
              : (widget.existing == null ? 'Nouveau malade' : 'Patient #$number'),
        ),
        actions: [
          if (widget.existing != null)
            IconButton(
              onPressed: _delete,
              tooltip: 'Supprimer',
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      body: _restoring
          ? const Center(
              child: CircularProgressIndicator(color: PracticeColors.accent),
            )
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(15, 4, 15, 28),
                children: [
                  _FormHeader(
                    patientNumber: number,
                    syncLabel: _syncLabel,
                    pending: widget.existing?.pendingSync == true,
                    standalone: _isStandalone,
                  ),
                  const SizedBox(height: 10),
                  if (_isStandalone) ...[
                    const _PracticeNotice(
                      icon: Icons.add_circle_outline_rounded,
                      text:
                          'Ce cas est indépendant de vos gardes aux urgences. Il apparaîtra dans les cas cliniques Practice sans modifier vos patients, statistiques ou objectifs de garde.',
                    ),
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: _pickStandaloneDate,
                      borderRadius: BorderRadius.circular(14),
                      child: InputDecorator(
                        decoration: _practiceInputDecoration(
                          'Date de la rencontre',
                          Icons.calendar_month_rounded,
                        ),
                        child: Text(
                          DateFormat('dd/MM/yyyy').format(_standaloneDate),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (_isStandalone && widget.existing == null) ...[
                    OutlinedButton.icon(
                      onPressed: _saving || _generatingRandomCase
                          ? null : _generateRandomCase,
                      icon: _generatingRandomCase
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.auto_awesome_rounded),
                      label: Text(_generatingRandomCase
                          ? 'Génération du cas clinique…'
                          : 'Générer un autre cas clinique au hasard'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: PracticeColors.gameGold,
                        minimumSize: const Size.fromHeight(52),
                        side: const BorderSide(color: PracticeColors.gameGold),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (_generatedByAi) ...[
                    const _PracticeNotice(
                      icon: Icons.science_outlined,
                      text: 'Simulation IA entièrement fictive : relisez '
                          'les données et les décisions avant publication. '
                          'Aucun patient réel n’est associé à ce dossier.',
                    ),
                    const SizedBox(height: 10),
                  ],
                  const _PracticeNotice(
                    icon: Icons.mic_rounded,
                    text: 'Dictée vocale : touchez le micro d’une rubrique puis dictez. Le texte s’ajoute à ce qui est déjà saisi. GardeFlow ne conserve aucun enregistrement audio.',
                  ),
                  const SizedBox(height: 16),
                  _formSection(
                    title: 'IDENTIFICATION PSEUDONYMISÉE',
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _field(
                              _age,
                              'Âge',
                              icon: Icons.cake_outlined,
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _sex,
                              dropdownColor: PracticeColors.surface,
                              style: const TextStyle(color: Colors.white),
                              decoration: _practiceInputDecoration(
                                'Sexe',
                                Icons.person_outline_rounded,
                              ),
                              items: const ['F', 'M', 'Autre', 'Non précisé']
                                  .map(
                                    (s) => DropdownMenuItem(
                                      value: s,
                                      child: Text(s),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                setState(() => _sex = value);
                                _changed();
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _field(
                              _location,
                              _isStandalone ? 'Service / lieu' : 'Box / zone',
                              icon: Icons.place_outlined,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: InkWell(
                              onTap: _pickArrivalTime,
                              borderRadius: BorderRadius.circular(14),
                              child: InputDecorator(
                                decoration: _practiceInputDecoration(
                                  'Heure d’arrivée',
                                  Icons.schedule_rounded,
                                ),
                                child: Text(
                                  _arrivalTime == null
                                      ? 'Facultatif'
                                      : DateFormat('HH:mm')
                                            .format(_arrivalTime!),
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _field(
                        _chiefComplaint,
                        'Motif principal (facultatif)',
                        icon: Icons.short_text_rounded,
                        voice: true,
                        voiceLabel: 'Motif principal',
                      ),
                    ],
                  ),
                  _formChapterTitle(
                    'INTERROGATOIRE',
                    Icons.forum_outlined,
                    'Antécédents et histoire de la maladie',
                  ),
                  _doubleClinicalSection(
                    'ANTÉCÉDENTS PERSONNELS',
                    'Chirurgicaux',
                    _personalSurgical,
                    'Médicaux',
                    _personalMedical,
                  ),
                  _doubleClinicalSection(
                    'ANTÉCÉDENTS FAMILIAUX',
                    'Chirurgicaux',
                    _familySurgical,
                    'Médicaux',
                    _familyMedical,
                  ),
                  _clinicalSection(
                    'MOTIF DE CONSULTATION *',
                    _consultationReason,
                    'Motif de consultation…',
                  ),
                  _clinicalSection(
                    'HISTOIRE DE LA MALADIE',
                    _illnessHistory,
                    'Chronologie, symptômes, contexte…',
                  ),
                  _formChapterTitle(
                    'EXAMEN ET SYNTHÈSE',
                    Icons.medical_services_outlined,
                    'Examen, explorations et prise en charge',
                  ),
                  _clinicalSection(
                    'EXAMEN CLINIQUE',
                    _clinicalExam,
                    'Constantes, examen général et ciblé…',
                  ),
                  _clinicalSection(
                    'EXAMENS COMPLÉMENTAIRES',
                    _complementary,
                    'Biologie, ECG, autres examens…',
                  ),
                  _clinicalSection(
                    'IMAGERIE — CONCLUSION',
                    _imaging,
                    'Radiographie :\n\nTDM :\n\nÉchographie :\n\nIRM :',
                  ),
                  _clinicalSection(
                    'BILAN',
                    _assessment,
                    'Synthèse clinique / diagnostic retenu…',
                  ),
                  _clinicalSection(
                    'CONDUITE À TENIR',
                    _plan,
                    'Traitement, surveillance, orientation…',
                  ),
                  _formSection(
                    title: 'DÉCISIONS ET SUIVI',
                    children: [
                      _yesNo('Avis spécialisé ?', _specialist, (value) {
                        setState(() => _specialist = value);
                        _changed();
                      }),
                      if (_specialist) ...[
                        const SizedBox(height: 8),
                        _specialtyDropdown('Service', _specialistService, (
                          value,
                        ) {
                          setState(() => _specialistService = value);
                          _changed();
                        }),
                        const SizedBox(height: 8),
                        _yesNo('Avis fait ?', _specialistDone, (value) {
                          setState(() => _specialistDone = value);
                          _changed();
                        }),
                      ],
                      const Divider(color: PracticeColors.line, height: 22),
                      _yesNo('Malade en attente ?', _waiting, (value) {
                        setState(() => _waiting = value);
                        _changed();
                      }),
                      const SizedBox(height: 8),
                      _yesNo('Ordonnance faite ?', _prescription, (value) {
                        setState(() => _prescription = value);
                        _changed();
                      }),
                      const SizedBox(height: 8),
                      _yesNo('Malade sortant ?', _discharged, (value) {
                        setState(() => _discharged = value);
                        _changed();
                      }),
                      const SizedBox(height: 8),
                      _yesNo('Hospitalisé ?', _hospitalized, (value) {
                        setState(() => _hospitalized = value);
                        _changed();
                      }),
                      if (_hospitalized) ...[
                        const SizedBox(height: 8),
                        _specialtyDropdown(
                          'Service d’hospitalisation',
                          _hospitalizationService,
                          (value) {
                            setState(() => _hospitalizationService = value);
                            _changed();
                          },
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 14),
                  const _PracticeNotice(
                    icon: Icons.lock_outline_rounded,
                    text: 'Aucune donnée nominative n’est requise. Les observations cliniques restent privées et ne sont jamais exposées au leaderboard.',
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _saving ? null : () => _save(addAnother: false),
                    style: FilledButton.styleFrom(
                      backgroundColor: PracticeColors.accent,
                      foregroundColor: PracticeColors.background,
                      minimumSize: const Size.fromHeight(54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_rounded),
                    label: Text(
                      _isStandalone
                          ? 'Ajouter le cas clinique'
                          : 'Enregistrer le malade',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(height: 9),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : () => _save(addAnother: true),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: PracticeColors.accent,
                      side: const BorderSide(color: PracticeColors.accent),
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    label: Text(
                      _isStandalone
                          ? 'Ajouter et saisir un autre cas'
                          : 'Enregistrer et ajouter un autre',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _formChapterTitle(String title, IconData icon, String subtitle) =>
      Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(0, 14, 0, 11),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              PracticeColors.accent.withOpacity(.16),
              PracticeColors.elevated.withOpacity(.52),
            ],
          ),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: PracticeColors.accent.withOpacity(.22)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: PracticeColors.accent.withOpacity(.16),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: PracticeColors.accent.withOpacity(.24),
                ),
              ),
              child: Icon(icon, color: PracticeColors.accent, size: 20),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: PracticeColors.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .85,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: PracticeColors.textSecondary,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  IconData _formSectionIcon(String title) {
    if (title.contains('IDENTIFICATION')) return Icons.badge_outlined;
    if (title.contains('ANTÉCÉDENTS')) return Icons.history_rounded;
    if (title.contains('MOTIF')) return Icons.chat_bubble_outline_rounded;
    if (title.contains('HISTOIRE')) return Icons.timeline_rounded;
    if (title.contains('EXAMEN CLINIQUE'))
      return Icons.medical_services_outlined;
    if (title.contains('COMPLÉMENTAIRES')) return Icons.biotech_outlined;
    if (title.contains('IMAGERIE')) return Icons.image_search_outlined;
    if (title.contains('BILAN')) return Icons.fact_check_outlined;
    if (title.contains('CONDUITE')) return Icons.route_outlined;
    if (title.contains('DÉCISIONS')) return Icons.task_alt_rounded;
    return Icons.description_outlined;
  }

  Widget _formSection({
    required String title,
    required List<Widget> children,
  }) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          PracticeColors.surface,
          PracticeColors.elevated.withOpacity(.86),
        ],
      ),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: PracticeColors.accent.withOpacity(.20)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(.16),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 34,
              decoration: BoxDecoration(
                color: PracticeColors.accent,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(width: 9),
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: PracticeColors.accent.withOpacity(.14),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                _formSectionIcon(title),
                color: PracticeColors.accent,
                size: 18,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: PracticeColors.text,
                  fontSize: 11.8,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .72,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ...children,
      ],
    ),
  );

  Widget _clinicalSection(
    String title,
    TextEditingController controller,
    String hint,
  ) => _formSection(
    title: title,
    children: [
      _field(
        controller,
        hint,
        lines: 4,
        voice: true,
        voiceLabel: title.replaceAll(' *', ''),
      ),
    ],
  );

  Widget _doubleClinicalSection(
    String title,
    String firstLabel,
    TextEditingController first,
    String secondLabel,
    TextEditingController second,
  ) => _formSection(
    title: title,
    children: [
      Text(
        firstLabel.toUpperCase(),
        style: const TextStyle(
          color: PracticeColors.textSecondary,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 6),
      _field(
        first,
        '$firstLabel…',
        lines: 2,
        voice: true,
        voiceLabel: '$title · $firstLabel',
      ),
      const SizedBox(height: 10),
      Text(
        secondLabel.toUpperCase(),
        style: const TextStyle(
          color: PracticeColors.textSecondary,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 6),
      _field(
        second,
        '$secondLabel…',
        lines: 2,
        voice: true,
        voiceLabel: '$title · $secondLabel',
      ),
    ],
  );

  Widget _field(
    TextEditingController controller,
    String hint, {
    IconData? icon,
    int lines = 1,
    TextInputType? keyboardType,
    bool voice = false,
    String? voiceLabel,
  }) {
    final active =
        voice &&
        identical(_dictatingController, controller) &&
        _dictationRequested;
    final activelyListening = active && _speech.isListening;
    return TextFormField(
      controller: controller,
      maxLines: lines,
      keyboardType:
          keyboardType ??
          (lines > 1 ? TextInputType.multiline : TextInputType.text),
      style: const TextStyle(
        color: Colors.white,
        fontSize: 13.5,
        height: 1.36,
        fontWeight: FontWeight.w600,
      ),
      decoration: _practiceInputDecoration(hint, icon).copyWith(
        helperText: active
            ? (activelyListening
                  ? 'Écoute en cours · continuez à parler · touchez le micro pour arrêter'
                  : 'Dictée active · reprise automatique de l’écoute…')
            : null,
        helperStyle: const TextStyle(
          color: PracticeColors.accent,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
        suffixIcon: voice
            ? IconButton(
                tooltip: active
                    ? 'Arrêter la dictée'
                    : 'Dicter ${voiceLabel ?? hint}',
                onPressed: _speechInitializing
                    ? null
                    : () => _toggleDictation(controller, voiceLabel ?? hint),
                icon:
                    _speechInitializing &&
                        identical(_dictatingController, controller)
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: PracticeColors.accent,
                        ),
                      )
                    : Icon(
                        active ? Icons.stop_circle_rounded : Icons.mic_rounded,
                        color: active
                            ? PracticeColors.hospitalized
                            : PracticeColors.accent,
                      ),
              )
            : null,
      ),
    );
  }

  Widget _yesNo(String label, bool value, ValueChanged<bool> onChanged) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: PracticeColors.background.withOpacity(.34),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: PracticeColors.line.withOpacity(.72)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Oui')),
                ButtonSegment(value: false, label: Text('Non')),
              ],
              selected: <bool>{value},
              onSelectionChanged: (selection) => onChanged(selection.first),
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? PracticeColors.background
                      : PracticeColors.textSecondary,
                ),
                backgroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? PracticeColors.accent
                      : PracticeColors.elevated,
                ),
                side: WidgetStatePropertyAll(
                  BorderSide(color: PracticeColors.line.withOpacity(.85)),
                ),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _specialtyDropdown(
    String label,
    String? value,
    ValueChanged<String?> onChanged,
  ) => DropdownButtonFormField<String>(
    value: practiceSpecialties.contains(value) ? value : null,
    dropdownColor: PracticeColors.surface,
    style: const TextStyle(color: Colors.white, fontSize: 13),
    decoration: _practiceInputDecoration(
      label,
      Icons.medical_services_outlined,
    ),
    isExpanded: true,
    items: practiceSpecialties
        .map(
          (service) => DropdownMenuItem(
            value: service,
            child: Text(service, overflow: TextOverflow.ellipsis),
          ),
        )
        .toList(),
    onChanged: onChanged,
  );
}

class PracticeAchievementsScreen extends StatefulWidget {
  final AppState appState;
  const PracticeAchievementsScreen({super.key, required this.appState});

  @override
  State<PracticeAchievementsScreen> createState() =>
      _PracticeAchievementsScreenState();
}

class _PracticeAchievementsScreenState
    extends State<PracticeAchievementsScreen> {
  bool _loading = true;
  List<PracticeAchievement> _items = const [];
  PracticeStats _all = const PracticeStats();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait<dynamic>([
      PracticeService.instance.achievements(),
      PracticeService.instance.summary(scope: 'all'),
    ]);
    if (!mounted) return;
    setState(() {
      _items = results[0] as List<PracticeAchievement>;
      _all = results[1] as PracticeStats;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final level = practiceLevelForXp(_all.xp);
    return DecorScaffold(
      scene: ScreenDecorScene.practice,
      backgroundColor: PracticeColors.background,
      appBar: AppBar(
        backgroundColor: PracticeColors.background,
        foregroundColor: Colors.white,
        title: const Text('Succès'),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: PracticeColors.accent),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(15, 8, 15, 30),
                children: [
                  _LevelCard(level: level, xp: _all.xp, streak: _all.streak),
                  const SizedBox(height: 16),
                  ..._items.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: PracticeColors.surface,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: item.unlocked
                                ? PracticeColors.accent
                                : PracticeColors.line,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color:
                                    (item.unlocked
                                            ? PracticeColors.accent
                                            : PracticeColors.elevated)
                                        .withOpacity(.16),
                                borderRadius: BorderRadius.circular(15),
                              ),
                              child: Icon(
                                _achievementIcon(item.icon),
                                color: item.unlocked
                                    ? PracticeColors.accent
                                    : PracticeColors.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    item.description,
                                    style: const TextStyle(
                                      color: PracticeColors.textSecondary,
                                      fontSize: 11,
                                      height: 1.35,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(99),
                                    child: LinearProgressIndicator(
                                      value: item.ratio,
                                      minHeight: 6,
                                      backgroundColor:
                                          PracticeColors.background,
                                      color: PracticeColors.accent,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    '${item.progress} / ${item.threshold}',
                                    style: const TextStyle(
                                      color: PracticeColors.textSecondary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (item.unlocked)
                              const Padding(
                                padding: EdgeInsets.only(left: 8),
                                child: Icon(
                                  Icons.check_circle_rounded,
                                  color: PracticeColors.accent,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class PracticeLeaderboardScreen extends StatefulWidget {
  final AppState appState;
  const PracticeLeaderboardScreen({super.key, required this.appState});

  @override
  State<PracticeLeaderboardScreen> createState() =>
      _PracticeLeaderboardScreenState();
}

class _PracticeLeaderboardScreenState extends State<PracticeLeaderboardScreen> {
  String _period = 'month';
  bool _promotionOnly = true;
  bool _loading = true;
  List<PracticeRankEntry> _items = const [];
  PracticePreferences _prefs = const PracticePreferences();

  int? get _promotion => widget.appState.currentUser?.promotionNumber;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait<dynamic>([
      PracticeService.instance.leaderboard(
        period: _period,
        promotion: _promotionOnly ? _promotion : null,
      ),
      PracticeService.instance.preferences(),
    ]);
    if (!mounted) return;
    setState(() {
      _items = results[0] as List<PracticeRankEntry>;
      _prefs = results[1] as PracticePreferences;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final me = widget.appState.currentUser;
    return DecorScaffold(
      scene: ScreenDecorScene.practice,
      backgroundColor: PracticeColors.background,
      appBar: AppBar(
        backgroundColor: PracticeColors.background,
        foregroundColor: Colors.white,
        title: const Text('Classement des internes'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: PracticeColors.accent,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(15, 6, 15, 30),
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'month', label: Text('Ce mois')),
                ButtonSegment(value: 'year', label: Text('Cette année')),
              ],
              selected: <String>{_period},
              onSelectionChanged: (selection) {
                _period = selection.first;
                _load();
              },
              style: _segmentStyle(),
            ),
            const SizedBox(height: 10),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Ma promo')),
                ButtonSegment(value: false, label: Text('Toutes les promos')),
              ],
              selected: <bool>{_promotionOnly},
              onSelectionChanged: (selection) {
                _promotionOnly = selection.first;
                _load();
              },
              style: _segmentStyle(),
            ),
            const SizedBox(height: 14),
            _LeaderboardPreferenceCard(
              value: _prefs.leaderboardOptIn,
              onChanged: (value) async {
                await PracticeService.instance.savePreferences(
                  leaderboardOptIn: value,
                  guardGoal: _prefs.guardGoal,
                );
                await _load();
              },
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(42),
                  child: CircularProgressIndicator(
                    color: PracticeColors.accent,
                  ),
                ),
              )
            else if (_items.isEmpty)
              const _PracticeEmpty(
                text: 'Aucune activité Practice classée pour cette période.',
              )
            else ...[
              if (_items.length >= 3)
                _TopThree(
                  items: _items.take(3).toList(),
                  currentUserId: me?.id,
                ),
              const SizedBox(height: 12),
              ..._items.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: _RankRow(
                    entry: entry,
                    highlighted: entry.userId == me?.id,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            const Text(
              'Practice valorise l’activité documentée uniquement. Ce classement ne mesure ni la compétence médicale, ni la qualité, ni la rapidité des soins.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: PracticeColors.textSecondary,
                fontSize: 11,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  ButtonStyle _segmentStyle() => ButtonStyle(
    foregroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.selected)
          ? PracticeColors.background
          : Colors.white,
    ),
    backgroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.selected)
          ? PracticeColors.accent
          : PracticeColors.surface,
    ),
    side: const WidgetStatePropertyAll(BorderSide(color: PracticeColors.line)),
  );
}

class PracticeHomeSummary extends StatefulWidget {
  final AppState appState;
  final AppUser user;
  const PracticeHomeSummary({
    super.key,
    required this.appState,
    required this.user,
  });

  @override
  State<PracticeHomeSummary> createState() => _PracticeHomeSummaryState();
}

class _PracticeHomeSummaryState extends State<PracticeHomeSummary> {
  final _service = PracticeService.instance;
  PracticeStats _stats = const PracticeStats();
  PracticeRanks _ranks = const PracticeRanks();
  bool _loading = true;

  PracticeGuard? get _guard => PracticeGuard.current(
    entries: widget.appState.planning,
    user: widget.user,
  );

  @override
  void initState() {
    super.initState();
    _service.revision.addListener(_changed);
    _load();
  }

  @override
  void didUpdateWidget(covariant PracticeHomeSummary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.id != widget.user.id) _load();
  }

  @override
  void dispose() {
    _service.revision.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    final guard = _guard;
    try {
      final results = await Future.wait<dynamic>([
        if (guard != null)
          _service.summary(scope: 'guard', guardId: guard.id)
        else
          Future.value(const PracticeStats()),
        _service.ranks(period: 'month'),
      ]);
      if (!mounted) return;
      setState(() {
        _stats = results[0] as PracticeStats;
        _ranks = results[1] as PracticeRanks;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox(height: 6);
    final guard = _guard;
    final showRank = _ranks.leaderboardOptIn;
    if (guard == null && !showRank) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF6E56E8), Color(0xFF247FD5), Color(0xFF13A982)],
            stops: [0, .54, 1],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withOpacity(.28)),
          boxShadow: [
            BoxShadow(
              color: PracticeColors.gamePurple.withOpacity(.30),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
            BoxShadow(
              color: PracticeColors.gameBlue.withOpacity(.12),
              blurRadius: 42,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        PracticeColors.gameGold.withOpacity(.30),
                        Colors.white.withOpacity(.12),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: PracticeColors.gameGold.withOpacity(.60),
                    ),
                  ),
                  child: const Icon(
                    Icons.sports_esports_rounded,
                    color: PracticeColors.gameGold,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PRACTICE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .8,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'MODE JEU · progression clinique',
                        style: TextStyle(
                          color: Color(0xFFDCEBE4),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                if (guard != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: PracticeColors.accent.withOpacity(.16),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: PracticeColors.accent.withOpacity(.28),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.circle,
                          color: PracticeColors.accent,
                          size: 7,
                        ),
                        SizedBox(width: 5),
                        Text(
                          'GARDE ACTIVE',
                          style: TextStyle(
                            color: PracticeColors.accent,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .45,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            if (guard != null) ...[
              const SizedBox(height: 12),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PracticeGuardScreen(
                        appState: widget.appState,
                        guard: guard,
                      ),
                    ),
                  ),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(.14)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(.10),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.description_rounded,
                            color: Colors.white,
                            size: 19,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _stats.patients == 0
                                    ? 'Votre garde vient de commencer'
                                    : '${_stats.patients} patient${_stats.patients > 1 ? 's' : ''} documenté${_stats.patients > 1 ? 's' : ''}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${guard.title} · ${guard.timeLabel}',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(.76),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 9),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  _homeStatChip(
                                    Icons.people_alt_outlined,
                                    '${_stats.patients} vus',
                                  ),
                                  _homeStatChip(
                                    Icons.hourglass_bottom_rounded,
                                    '${_stats.waiting} attente',
                                  ),
                                  _homeStatChip(
                                    Icons.logout_rounded,
                                    '${_stats.discharged} sortants',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Icon(
                            Icons.chevron_right_rounded,
                            color: Colors.white.withOpacity(.78),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            if (showRank) ...[
              const SizedBox(height: 8),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          PracticeLeaderboardScreen(appState: widget.appState),
                    ),
                  ),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(.055),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.emoji_events_outlined,
                          color: PracticeColors.gameGold,
                          size: 17,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _ranks.hasActivity
                                ? 'Classement : ${_ranks.promotionRank == null ? '—' : '${_ranks.promotionRank}e'} promo · ${_ranks.globalRank == null ? '—' : '${_ranks.globalRank}e'} global'
                                : 'Classement disponible après votre première activité Practice.',
                            style: TextStyle(
                              color: Colors.white.withOpacity(.90),
                              fontSize: 10.8,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.white.withOpacity(.66),
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _homeStatChip(IconData icon, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.black.withOpacity(.12),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: Colors.white.withOpacity(.10)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: PracticeColors.gameGold, size: 12),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _CurrentGuardCard extends StatelessWidget {
  final PracticeGuard guard;
  final PracticeStats stats;
  final int? goal;
  final VoidCallback onNewCase;
  final VoidCallback onOpenGuard;
  final VoidCallback onEditGoal;
  const _CurrentGuardCard({
    required this.guard,
    required this.stats,
    required this.goal,
    required this.onNewCase,
    required this.onOpenGuard,
    required this.onEditGoal,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = goal == null ? 0.0 : (stats.patients / goal!).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            PracticeColors.gameBlue.withOpacity(.24),
            PracticeColors.surface,
            PracticeColors.gamePurple.withOpacity(.13),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: PracticeColors.gameBlue.withOpacity(.38)),
        boxShadow: [
          BoxShadow(
            color: PracticeColors.gameBlue.withOpacity(.10),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: PracticeColors.accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              const Text(
                'MISSION ACTIVE',
                style: TextStyle(
                  color: PracticeColors.accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            guard.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${DateFormat('d MMMM yyyy', 'fr_FR').format(guard.start)} · ${guard.timeLabel}',
            style: const TextStyle(
              color: PracticeColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MiniMetric(label: 'Vus', value: '${stats.patients}'),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: _MiniMetric(label: 'Attente', value: '${stats.waiting}'),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: _MiniMetric(
                  label: 'Sortants',
                  value: '${stats.discharged}',
                ),
              ),
            ],
          ),
          if (goal != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Objectif : ${stats.patients} / $goal',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${(ratio * 100).round()} %',
                  style: const TextStyle(
                    color: PracticeColors.accent,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 7,
                color: PracticeColors.accent,
                backgroundColor: PracticeColors.background,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              stats.patients >= goal!
                  ? 'Objectif atteint.'
                  : 'Encore ${goal! - stats.patients} observation${goal! - stats.patients > 1 ? 's' : ''} pour atteindre votre objectif.',
              style: const TextStyle(
                color: PracticeColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onOpenGuard,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: PracticeColors.line),
                  ),
                  child: const Text('Ma garde'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: onEditGoal,
                tooltip: 'Objectif',
                icon: const Icon(Icons.flag_outlined),
                color: PracticeColors.textSecondary,
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onNewCase,
              style: FilledButton.styleFrom(
                backgroundColor: PracticeColors.accent,
                foregroundColor: PracticeColors.background,
                minimumSize: const Size.fromHeight(52),
              ),
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'Nouveau malade',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoGuardCard extends StatelessWidget {
  final VoidCallback onHistory;
  const _NoGuardCard({required this.onHistory});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: PracticeColors.surface,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: PracticeColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.event_available_rounded,
          color: PracticeColors.textSecondary,
          size: 30,
        ),
        const SizedBox(height: 10),
        const Text(
          'Aucune garde Urgences en cours.',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          'Vous pouvez consulter votre historique, vos statistiques et votre progression.',
          style: TextStyle(color: PracticeColors.textSecondary, height: 1.4),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onHistory,
          icon: const Icon(Icons.history_rounded),
          label: const Text('Voir l’historique'),
          style: OutlinedButton.styleFrom(
            foregroundColor: PracticeColors.accent,
            side: const BorderSide(color: PracticeColors.line),
          ),
        ),
      ],
    ),
  );
}

class _LevelCard extends StatelessWidget {
  final PracticeLevel level;
  final int xp;
  final int streak;
  const _LevelCard({
    required this.level,
    required this.xp,
    required this.streak,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          PracticeColors.gamePurple.withOpacity(.26),
          PracticeColors.surface,
          PracticeColors.gameBlue.withOpacity(.12),
        ],
      ),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: PracticeColors.gamePurple.withOpacity(.40)),
      boxShadow: [
        BoxShadow(
          color: PracticeColors.gamePurple.withOpacity(.11),
          blurRadius: 18,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'NIVEAU ${level.number}',
                    style: const TextStyle(
                      color: PracticeColors.accent,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .8,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    level.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '🔥 Série de $streak garde${streak > 1 ? 's' : ''}',
              style: const TextStyle(
                color: PracticeColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: level.progressFor(xp),
            minHeight: 8,
            color: PracticeColors.gameGold,
            backgroundColor: PracticeColors.background,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${level.xpIntoLevel(xp)} / ${level.xpForLevel} XP · $xp XP au total',
          style: const TextStyle(
            color: PracticeColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final bool loading;
  const _StatCard({
    required this.value,
    required this.label,
    required this.loading,
  });
  @override
  Widget build(BuildContext context) => Container(
    height: 90,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          PracticeColors.gameBlue.withOpacity(.18),
          PracticeColors.surface,
        ],
      ),
      borderRadius: BorderRadius.circular(17),
      border: Border.all(color: PracticeColors.gameBlue.withOpacity(.28)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(.10),
          blurRadius: 12,
          offset: Offset(0, 6),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          loading ? '…' : value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: PracticeColors.textSecondary,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _PracticeActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _PracticeActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              PracticeColors.gamePurple.withOpacity(.15),
              PracticeColors.surface,
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: PracticeColors.gamePurple.withOpacity(.24)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: PracticeColors.elevated,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: PracticeColors.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: PracticeColors.textSecondary,
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: PracticeColors.textSecondary,
            ),
          ],
        ),
      ),
    ),
  );
}

class _HistorySummaryCard extends StatelessWidget {
  final PracticeStats stats;
  const _HistorySummaryCard({required this.stats});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
    decoration: BoxDecoration(
      color: PracticeColors.surface,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      children: [
        Expanded(
          child: _HistoryMetric(value: '${stats.patients}', label: 'Vus'),
        ),
        const _HistoryMetricDivider(),
        Expanded(
          child: _HistoryMetric(value: '${stats.waiting}', label: 'Attente'),
        ),
        const _HistoryMetricDivider(),
        Expanded(
          child: _HistoryMetric(
            value: '${stats.discharged}',
            label: 'Sortants',
          ),
        ),
        const _HistoryMetricDivider(),
        Expanded(
          child: _HistoryMetric(
            value: '${stats.specialistOpinions}',
            label: 'Avis',
          ),
        ),
      ],
    ),
  );
}

class _HistoryMetric extends StatelessWidget {
  final String value;
  final String label;
  const _HistoryMetric({required this.value, required this.label});

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        value,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 19,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: PracticeColors.textSecondary,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class _HistoryMetricDivider extends StatelessWidget {
  const _HistoryMetricDivider();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 34,
    color: PracticeColors.line.withOpacity(.55),
  );
}

class _PatientTile extends StatelessWidget {
  final PracticeCase value;
  final VoidCallback onTap;
  const _PatientTile({required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final timeLabel = value.arrivalTime == null
        ? ''
        : DateFormat('HH:mm').format(value.arrivalTime!);
    final locationLabel = _practiceCaseLocationLabel(value.location);
    final badges = _caseBadges(value);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
          decoration: BoxDecoration(
            color: PracticeColors.surface,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            value.patientLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        if (value.pendingSync) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.cloud_upload_outlined,
                            color: PracticeColors.waiting,
                            size: 14,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (timeLabel.isNotEmpty)
                    Text(
                      timeLabel,
                      style: const TextStyle(
                        color: PracticeColors.textSecondary,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: PracticeColors.textSecondary,
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                value.displayReason,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: PracticeColors.textSecondary,
                  fontSize: 13.2,
                  height: 1.32,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (locationLabel.isNotEmpty) ...[
                const SizedBox(height: 7),
                Row(
                  children: [
                    const Icon(
                      Icons.place_outlined,
                      color: PracticeColors.textSecondary,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      locationLabel,
                      style: const TextStyle(
                        color: PracticeColors.textSecondary,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
              if (badges.isNotEmpty) ...[
                const SizedBox(height: 9),
                Wrap(spacing: 5, runSpacing: 5, children: badges),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LeaderboardPreferenceCard extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _LeaderboardPreferenceCard({
    required this.value,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: PracticeColors.surface,
      borderRadius: BorderRadius.circular(17),
      border: Border.all(color: PracticeColors.line),
    ),
    child: Row(
      children: [
        const Icon(Icons.leaderboard_outlined, color: PracticeColors.accent),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Participer au classement',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Vos statistiques privées restent inchangées.',
                style: TextStyle(
                  color: PracticeColors.textSecondary,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: PracticeColors.accent,
        ),
      ],
    ),
  );
}

class _TopThree extends StatelessWidget {
  final List<PracticeRankEntry> items;
  final String? currentUserId;
  const _TopThree({required this.items, required this.currentUserId});
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: _TopPodium(
          entry: items[1],
          height: 88,
          currentUserId: currentUserId,
        ),
      ),
      const SizedBox(width: 7),
      Expanded(
        child: _TopPodium(
          entry: items[0],
          height: 108,
          currentUserId: currentUserId,
        ),
      ),
      const SizedBox(width: 7),
      Expanded(
        child: _TopPodium(
          entry: items[2],
          height: 76,
          currentUserId: currentUserId,
        ),
      ),
    ],
  );
}

class _TopPodium extends StatelessWidget {
  final PracticeRankEntry entry;
  final double height;
  final String? currentUserId;
  const _TopPodium({
    required this.entry,
    required this.height,
    required this.currentUserId,
  });
  @override
  Widget build(BuildContext context) => Container(
    height: height,
    padding: const EdgeInsets.all(9),
    decoration: BoxDecoration(
      color: entry.userId == currentUserId
          ? PracticeColors.elevated
          : PracticeColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: entry.userId == currentUserId
            ? PracticeColors.accent
            : PracticeColors.line,
      ),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          entry.rank == 1
              ? '🥇'
              : entry.rank == 2
              ? '🥈'
              : '🥉',
          style: const TextStyle(fontSize: 20),
        ),
        Text(
          entry.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10.5,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '${entry.xp} XP',
          style: const TextStyle(
            color: PracticeColors.accent,
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

class _RankRow extends StatelessWidget {
  final PracticeRankEntry entry;
  final bool highlighted;
  const _RankRow({required this.entry, required this.highlighted});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    decoration: BoxDecoration(
      color: highlighted ? PracticeColors.elevated : PracticeColors.surface,
      borderRadius: BorderRadius.circular(15),
      border: Border.all(
        color: highlighted ? PracticeColors.accent : PracticeColors.line,
      ),
    ),
    child: Row(
      children: [
        SizedBox(
          width: 34,
          child: Text(
            '${entry.rank}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        ProfileAvatar(
          profileId: entry.userId,
          initials: _initials(entry.displayName),
          isJunior: true,
          radius: 17,
          backgroundColor: PracticeColors.background,
          foregroundColor: PracticeColors.accent,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                [
                  if (entry.promotionNumber != null)
                    'Promo ${entry.promotionNumber}',
                  if (entry.hospital.trim().isNotEmpty) entry.hospital,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: PracticeColors.textSecondary,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
        Text(
          '${entry.xp} XP',
          style: const TextStyle(
            color: PracticeColors.accent,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

class _FormHeader extends StatelessWidget {
  final String patientNumber;
  final String syncLabel;
  final bool pending;
  final bool standalone;
  const _FormHeader({
    required this.patientNumber,
    required this.syncLabel,
    required this.pending,
    this.standalone = false,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [PracticeColors.elevated, PracticeColors.surface],
      ),
      borderRadius: BorderRadius.circular(23),
      border: Border.all(color: PracticeColors.line),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(.14),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: PracticeColors.accent.withOpacity(.12),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: PracticeColors.accent.withOpacity(.26)),
          ),
          child: const Icon(
            Icons.assignment_outlined,
            color: PracticeColors.accent,
            size: 25,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'OBSERVATION CLINIQUE',
                style: TextStyle(
                  color: PracticeColors.textSecondary,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .9,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                standalone ? 'Cas clinique hors garde' : 'Patient #$patientNumber',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color:
                      (pending ? PracticeColors.waiting : PracticeColors.accent)
                          .withOpacity(.11),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  pending ? 'À synchroniser' : syncLabel,
                  style: TextStyle(
                    color: pending
                        ? PracticeColors.waiting
                        : PracticeColors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: PracticeColors.background.withOpacity(.55),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.shield_outlined,
            color: PracticeColors.textSecondary,
            size: 19,
          ),
        ),
      ],
    ),
  );
}

class _EncouragementCard extends StatelessWidget {
  final String text;
  const _EncouragementCard({required this.text});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: PracticeColors.elevated,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      children: [
        const Icon(Icons.auto_awesome_rounded, color: PracticeColors.accent),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              height: 1.4,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    ),
  );
}

class _PracticeNotice extends StatelessWidget {
  final IconData icon;
  final String text;
  const _PracticeNotice({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: PracticeColors.surface,
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: PracticeColors.line),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: PracticeColors.textSecondary, size: 18),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: PracticeColors.textSecondary,
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );
}

class _PracticeEmpty extends StatelessWidget {
  final String text;
  const _PracticeEmpty({required this.text});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: PracticeColors.surface,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: PracticeColors.textSecondary,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _MiniMetric extends StatelessWidget {
  final String label;
  final String value;
  const _MiniMetric({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 86),
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
    decoration: BoxDecoration(
      color: PracticeColors.background.withOpacity(.65),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: PracticeColors.textSecondary,
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _MonthlyBars extends StatelessWidget {
  final List<int> values;
  const _MonthlyBars({required this.values});
  @override
  Widget build(BuildContext context) {
    const labels = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];
    final maxValue = values.isEmpty
        ? 1
        : values.reduce((a, b) => a > b ? a : b).clamp(1, 1000000);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(12, (i) {
        final value = i < values.length ? values[i] : 0;
        final ratio = value / maxValue;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  '$value',
                  style: const TextStyle(
                    color: PracticeColors.textSecondary,
                    fontSize: 8,
                  ),
                ),
                const SizedBox(height: 3),
                Container(
                  height: 150 * ratio + 5,
                  decoration: BoxDecoration(
                    color: PracticeColors.accent.withOpacity(.35 + .65 * ratio),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  labels[i],
                  style: const TextStyle(
                    color: PracticeColors.textSecondary,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

List<Widget> _caseBadges(PracticeCase value) {
  final items = <Widget>[];
  if (value.waiting)
    items.add(const _StatusBadge('En attente', PracticeColors.waiting));
  if (value.specialistOpinionRequested)
    items.add(
      _StatusBadge(
        value.specialistService == null
            ? 'Avis spécialisé'
            : 'Avis ${value.specialistService}',
        PracticeColors.specialist,
      ),
    );
  if (value.discharged)
    items.add(const _StatusBadge('Sortant', PracticeColors.discharged));
  if (value.hospitalized)
    items.add(const _StatusBadge('Hospitalisé', PracticeColors.hospitalized));
  if (value.prescriptionDone)
    items.add(
      const _StatusBadge('Ordonnance faite', PracticeColors.prescription),
    );
  if (value.pendingSync)
    items.add(const _StatusBadge('À synchroniser', PracticeColors.waiting));
  return items;
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusBadge(this.label, this.color);
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxWidth: 190),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withOpacity(.14),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withOpacity(.45)),
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: color,
        fontSize: 9.5,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

InputDecoration _historySearchDecoration() => InputDecoration(
  hintText: 'Rechercher un patient, motif, box…',
  hintStyle: const TextStyle(
    color: PracticeColors.textSecondary,
    fontSize: 12.5,
    fontWeight: FontWeight.w600,
  ),
  prefixIcon: const Icon(
    Icons.search_rounded,
    color: PracticeColors.textSecondary,
    size: 20,
  ),
  filled: true,
  fillColor: PracticeColors.surface,
  contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(
      color: PracticeColors.line.withOpacity(.52),
      width: .8,
    ),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: const BorderSide(color: PracticeColors.accent, width: 1.2),
  ),
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
);

String _practiceCaseLocationLabel(String? raw) {
  final value = (raw ?? '').trim();
  if (value.isEmpty) return '';
  final lower = value.toLowerCase();
  if (lower.startsWith('box ') || lower.startsWith('zone ')) return value;
  if (RegExp(r'^\d+$').hasMatch(value)) return 'Box $value';
  return value;
}

InputDecoration _practiceInputDecoration(String hint, [IconData? icon]) =>
    InputDecoration(
      hintText: hint,
      labelText: null,
      hintStyle: const TextStyle(
        color: PracticeColors.textSecondary,
        fontSize: 12.2,
        fontWeight: FontWeight.w600,
      ),
      prefixIcon: icon == null
          ? null
          : Icon(icon, color: PracticeColors.accent.withOpacity(.78), size: 19),
      filled: true,
      fillColor: PracticeColors.background.withOpacity(.58),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: PracticeColors.line.withOpacity(.82)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: PracticeColors.accent, width: 1.6),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
    );

Widget _sectionLabel(String label) => Text(
  label,
  style: const TextStyle(
    color: PracticeColors.textSecondary,
    fontSize: 10.5,
    fontWeight: FontWeight.w900,
    letterSpacing: .9,
  ),
);

IconData _achievementIcon(String key) {
  switch (key) {
    case 'flag':
      return Icons.flag_rounded;
    case 'clinical_notes':
      return Icons.description_rounded;
    case 'verified':
      return Icons.verified_rounded;
    case 'groups':
      return Icons.groups_rounded;
    case 'calendar_month':
      return Icons.calendar_month_rounded;
    case 'local_fire_department':
      return Icons.local_fire_department_rounded;
    case 'workspace_premium':
      return Icons.workspace_premium_rounded;
    default:
      return Icons.military_tech_rounded;
  }
}

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((e) => e.isNotEmpty && e.toLowerCase() != 'dr')
      .toList();
  if (parts.isEmpty) return 'DR';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
}


class _QcmCanonicalStatsStrip extends StatelessWidget {
  final QcmRanks month; final QcmStats total; final bool loading;
  const _QcmCanonicalStatsStrip({required this.month, required this.total, required this.loading});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    decoration: BoxDecoration(color: PracticeColors.surface.withOpacity(.88), borderRadius: BorderRadius.circular(18), border: Border.all(color: PracticeColors.gameBlue.withOpacity(.35))),
    child: Row(children: [const Icon(Icons.sync_rounded, color: PracticeColors.accent, size: 20), const SizedBox(width: 9), Expanded(child: Text(loading ? 'Synchronisation…' : '${month.answered} ce mois  •  ${total.answered} au total', style: const TextStyle(color: PracticeColors.text, fontWeight: FontWeight.w800, fontSize: 13.5))), const Text('Auto', style: TextStyle(color: PracticeColors.accent, fontSize: 11, fontWeight: FontWeight.w800))]),
  );
}
