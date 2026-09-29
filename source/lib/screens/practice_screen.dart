import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/app_user.dart';
import '../models/practice_models.dart';
import '../services/practice_service.dart';
import '../state/app_state.dart';

abstract final class PracticeColors {
  static const background = Color(0xFF062E20);
  static const surface = Color(0xFF0B4933);
  static const elevated = Color(0xFF116044);
  static const accent = Color(0xFF20D67A);
  static const text = Colors.white;
  static const textSecondary = Color(0xFFB8D6C9);
  static const line = Color(0xFF287154);
  static const waiting = Color(0xFFFFC857);
  static const specialist = Color(0xFF55A7FF);
  static const discharged = Color(0xFF20D67A);
  static const hospitalized = Color(0xFFFF766E);
  static const prescription = Color(0xFF8FE3B7);
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
  bool _loading = true;
  PracticeStats _guard = const PracticeStats();
  PracticeStats _month = const PracticeStats();
  PracticeStats _year = const PracticeStats();
  PracticeStats _all = const PracticeStats();
  PracticePreferences _prefs = const PracticePreferences();
  PracticeRanks _ranks = const PracticeRanks();
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
    _load();
  }

  @override
  void dispose() {
    _service.revision.removeListener(_onRevision);
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
        if (guard != null) _service.summary(scope: 'guard', guardId: guard.id) else Future.value(const PracticeStats()),
        _service.summary(scope: 'month'),
        _service.summary(scope: 'year'),
        _service.summary(scope: 'all'),
        _service.preferences(),
        _service.ranks(period: 'month'),
        _service.achievements(),
        _service.monthlyCounts(year: DateTime.now().year),
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

  Future<void> _editGoal() async {
    final controller = TextEditingController(text: _prefs.guardGoal?.toString() ?? '');
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
          TextButton(onPressed: () => Navigator.pop(dialogContext, -1), child: const Text('Retirer')),
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Annuler')),
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
                'Transformez vos gardes en progression clinique.',
                style: TextStyle(color: PracticeColors.textSecondary, fontSize: 14, fontWeight: FontWeight.w600),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                _PracticeNotice(icon: Icons.cloud_off_rounded, text: _error!),
              ],
              const SizedBox(height: 22),
              _sectionLabel('MES STATISTIQUES'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _StatCard(value: '${_guard.patients}', label: 'Cette garde', loading: _loading)),
                  const SizedBox(width: 8),
                  Expanded(child: _StatCard(value: '${_month.patients}', label: 'Ce mois', loading: _loading)),
                  const SizedBox(width: 8),
                  Expanded(child: _StatCard(value: '${_year.patients}', label: 'Cette année', loading: _loading)),
                ],
              ),
              const SizedBox(height: 14),
              _LevelCard(level: level, xp: _all.xp, streak: _all.streak),
              const SizedBox(height: 18),
              _sectionLabel('GARDE ACTUELLE'),
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
              const SizedBox(height: 18),
              _PracticeActionTile(
                icon: Icons.emoji_events_rounded,
                title: 'Classement',
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
              const SizedBox(height: 18),
              _EncouragementCard(text: _encouragement(guard)),
              const SizedBox(height: 18),
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
                'Practice valorise votre activité documentée. Le classement ne mesure pas la qualité des soins.',
                textAlign: TextAlign.center,
                style: TextStyle(color: PracticeColors.textSecondary, fontSize: 11, height: 1.4, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _rankSubtitle(PracticeRanks ranks) {
    if (!ranks.leaderboardOptIn) return 'Participation au classement désactivée';
    if (!ranks.hasActivity) return 'Disponible après votre première activité Practice';
    final promo = ranks.promotionRank == null ? '—' : '${ranks.promotionRank}e dans votre promo';
    final global = ranks.globalRank == null ? '—' : '${ranks.globalRank}e toutes promotions';
    return '$promo · $global';
  }

  String _encouragement(PracticeGuard? guard) {
    if (_achievements.any((a) => a.unlockedAt != null && a.unlockedAt!.isAfter(DateTime.now().subtract(const Duration(hours: 24))))) {
      final latest = _achievements.firstWhere((a) => a.unlockedAt != null && a.unlockedAt!.isAfter(DateTime.now().subtract(const Duration(hours: 24))));
      return 'Succès débloqué : ${latest.name}.';
    }
    if (guard != null && _prefs.guardGoal != null && _guard.patients >= _prefs.guardGoal!) {
      return 'Objectif de garde atteint. Belle garde, continuez avec la même rigueur.';
    }
    if (guard != null && _guard.patients >= 10) return '${_guard.patients} observations cette garde. Beau travail.';
    if (_all.streak >= 3) return '🔥 Série de ${_all.streak} gardes documentées. Continuez régulièrement.';
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
              const Text('Progression annuelle', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 16),
              SizedBox(height: 220, child: _MonthlyBars(values: _monthly)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MiniMetric(label: 'Gardes', value: '${_year.guardsCount}'),
                  _MiniMetric(label: 'Moyenne / garde', value: _year.averagePerGuard.toStringAsFixed(1)),
                  _MiniMetric(label: 'Meilleure garde', value: '${_year.bestGuard}'),
                  _MiniMetric(label: 'Observations complètes', value: '${_year.completeObservations}'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
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
        _service.fetchCases(guardId: guardId, scope: scopeForApi, status: _status, limit: _pageSize),
        _service.summary(scope: scopeForApi, guardId: guardId),
      ]);
      if (!mounted) return;
      final rows = (results[0] as List<PracticeCase>).where((item) => !item.isDraft).toList();
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
      MaterialPageRoute(builder: (_) => PracticeCaseFormScreen(appState: widget.appState, guard: guard, suggestedNumber: number)),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PracticeColors.background,
      appBar: AppBar(
        backgroundColor: PracticeColors.background,
        foregroundColor: Colors.white,
        title: Text(widget.guard == null ? 'Practice · Historique' : 'Practice · Ma garde'),
      ),
      floatingActionButton: widget.guard == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _newCase,
              backgroundColor: PracticeColors.accent,
              foregroundColor: PracticeColors.background,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Ajouter un malade', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: PracticeColors.accent,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 100),
          children: [
            if (widget.guard != null) ...[
              Text(widget.guard!.title, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(widget.guard!.timeLabel, style: const TextStyle(color: PracticeColors.textSecondary, fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MiniMetric(label: 'Malades vus', value: '${_stats.patients}'),
                _MiniMetric(label: 'En attente', value: '${_stats.waiting}'),
                _MiniMetric(label: 'Sortants', value: '${_stats.discharged}'),
                _MiniMetric(label: 'Avis spécialisés', value: '${_stats.specialistOpinions}'),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _search,
              style: const TextStyle(color: Colors.white),
              decoration: _practiceInputDecoration('Rechercher un patient, motif, box…', Icons.search_rounded),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
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
            if (_loading)
              const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: PracticeColors.accent)))
            else if (_visible.isEmpty)
              const _PracticeEmpty(text: 'Aucun patient ne correspond à ces critères.')
            else
              ..._visible.map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: _PatientTile(
                      value: item,
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => PracticeCaseFormScreen(appState: widget.appState, guard: widget.guard, existing: item)),
                        );
                        if (mounted) _load(silent: true);
                      },
                    ),
                  )),
            if (_hasMore) ...[
              const SizedBox(height: 6),
              OutlinedButton(
                onPressed: _loadingMore ? null : _more,
                style: OutlinedButton.styleFrom(foregroundColor: PracticeColors.accent, side: const BorderSide(color: PracticeColors.line)),
                child: Text(_loadingMore ? 'Chargement…' : 'Charger plus'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _scopeChip(String key, String label) => Padding(
        padding: const EdgeInsets.only(right: 7),
        child: ChoiceChip(
          selected: _scope == key,
          label: Text(label),
          onSelected: (_) {
            setState(() => _scope = key);
            _load();
          },
          selectedColor: PracticeColors.accent,
          backgroundColor: PracticeColors.surface,
          labelStyle: TextStyle(color: _scope == key ? PracticeColors.background : Colors.white, fontWeight: FontWeight.w800),
          side: BorderSide.none,
        ),
      );

  Widget _filterChip(String key, String label) => Padding(
        padding: const EdgeInsets.only(right: 7),
        child: FilterChip(
          selected: _filter == key,
          label: Text(label),
          onSelected: (_) {
            setState(() => _filter = key);
            _load();
          },
          selectedColor: PracticeColors.elevated,
          backgroundColor: PracticeColors.surface,
          checkmarkColor: PracticeColors.accent,
          labelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          side: const BorderSide(color: PracticeColors.line),
        ),
      );
}

class PracticeCaseFormScreen extends StatefulWidget {
  final AppState appState;
  final PracticeGuard? guard;
  final PracticeCase? existing;
  final int? suggestedNumber;
  const PracticeCaseFormScreen({super.key, required this.appState, this.guard, this.existing, this.suggestedNumber});

  @override
  State<PracticeCaseFormScreen> createState() => _PracticeCaseFormScreenState();
}

class _PracticeCaseFormScreenState extends State<PracticeCaseFormScreen> {
  final _service = PracticeService.instance;
  final _formKey = GlobalKey<FormState>();
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

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _clientId = existing?.clientId ?? '${DateTime.now().microsecondsSinceEpoch}-${_me?.id ?? 'local'}';
    _patientNumber = existing?.patientNumber ?? widget.suggestedNumber ?? 1;
    if (existing != null) _apply(existing);
    for (final controller in _controllers) {
      controller.addListener(_changed);
    }
    _restoreDraft();
  }

  @override
  void dispose() {
    _autosave?.cancel();
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _restoreDraft() async {
    final me = _me;
    final guardId = widget.existing?.guardId ?? widget.guard?.id;
    if (me == null || guardId == null) {
      if (mounted) setState(() => _restoring = false);
      return;
    }
    final draft = await _service.loadLocalDraft(userId: me.id, guardId: guardId);
    if (draft != null) {
      final relevant = widget.existing == null ? draft.id == null : draft.clientId == widget.existing!.clientId;
      if (relevant) {
        _clientId = draft.clientId;
        _patientNumber = draft.patientNumber;
        _apply(draft);
        if (mounted) setState(() => _syncLabel = 'Brouillon restauré');
      }
    }
    if (mounted) setState(() => _restoring = false);
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
    final guardId = widget.existing?.guardId ?? widget.guard?.id;
    final guardDate = widget.existing?.guardDate ?? widget.guard?.dateStr;
    final guardShiftId = widget.existing?.guardShiftId ?? widget.guard?.shiftId;
    if (me == null || guardId == null || guardDate == null || guardShiftId == null) return null;
    return PracticeCase(
      id: widget.existing?.id,
      userId: me.id,
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
        const SnackBar(content: Text('Ajoutez un motif de consultation et au moins une section clinique : interrogatoire, histoire, examen, bilan ou conduite à tenir.')),
      );
      return;
    }
    setState(() {
      _saving = true;
      _syncLabel = 'Synchronisation…';
    });
    try {
      final result = await _service.saveValidated(value);
      await _service.clearLocalDraft(userId: value.userId, guardId: value.guardId);
      if (!mounted) return;
      final completeBonus = value.isComplete ? ' · Observation complète : +2 XP' : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.pendingSync ? 'Observation enregistrée localement · À synchroniser' : 'Observation enregistrée : +10 XP$completeBonus')),
      );
      Navigator.pop(context, addAnother ? 'addAnother' : 'saved');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _syncLabel = 'Brouillon sauvegardé';
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Enregistrement impossible : $e')));
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
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _service.deleteCase(existing);
    if (mounted) Navigator.pop(context, 'deleted');
  }

  Future<void> _pickArrivalTime() async {
    final initial = _arrivalTime ?? DateTime.now();
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (picked == null || !mounted) return;
    final day = DateTime.now();
    setState(() => _arrivalTime = DateTime(day.year, day.month, day.day, picked.hour, picked.minute));
    _changed();
  }

  @override
  Widget build(BuildContext context) {
    final number = _patientNumber.toString().padLeft(3, '0');
    return Scaffold(
      backgroundColor: PracticeColors.background,
      appBar: AppBar(
        backgroundColor: PracticeColors.background,
        foregroundColor: Colors.white,
        title: Text(widget.existing == null ? 'Nouveau malade' : 'Patient #$number'),
        actions: [
          if (widget.existing != null)
            IconButton(onPressed: _delete, tooltip: 'Supprimer', icon: const Icon(Icons.delete_outline_rounded)),
        ],
      ),
      body: _restoring
          ? const Center(child: CircularProgressIndicator(color: PracticeColors.accent))
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(15, 4, 15, 28),
                children: [
                  _FormHeader(patientNumber: number, syncLabel: _syncLabel, pending: widget.existing?.pendingSync == true),
                  const SizedBox(height: 16),
                  _formSection(
                    title: 'IDENTIFICATION PSEUDONYMISÉE',
                    children: [
                      Row(children: [
                        Expanded(child: _field(_age, 'Âge', icon: Icons.cake_outlined, keyboardType: TextInputType.number)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _sex,
                            dropdownColor: PracticeColors.surface,
                            style: const TextStyle(color: Colors.white),
                            decoration: _practiceInputDecoration('Sexe', Icons.person_outline_rounded),
                            items: const ['F', 'M', 'Autre', 'Non précisé'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                            onChanged: (value) { setState(() => _sex = value); _changed(); },
                          ),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(child: _field(_location, 'Box / zone', icon: Icons.place_outlined)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: InkWell(
                            onTap: _pickArrivalTime,
                            borderRadius: BorderRadius.circular(14),
                            child: InputDecorator(
                              decoration: _practiceInputDecoration('Heure d’arrivée', Icons.schedule_rounded),
                              child: Text(_arrivalTime == null ? 'Facultatif' : DateFormat('HH:mm').format(_arrivalTime!), style: const TextStyle(color: Colors.white)),
                            ),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      _field(_chiefComplaint, 'Motif principal (facultatif)', icon: Icons.short_text_rounded),
                    ],
                  ),
                  _clinicalSection('1. INTERROGATOIRE', _interrogatoire, 'Interrogatoire clinique…'),
                  _doubleClinicalSection('2. ANTÉCÉDENTS PERSONNELS', 'Chirurgicaux', _personalSurgical, 'Médicaux', _personalMedical),
                  _doubleClinicalSection('3. ANTÉCÉDENTS FAMILIAUX', 'Chirurgicaux', _familySurgical, 'Médicaux', _familyMedical),
                  _clinicalSection('4. MOTIF DE CONSULTATION *', _consultationReason, 'Motif de consultation…'),
                  _clinicalSection('5. HISTOIRE DE LA MALADIE', _illnessHistory, 'Chronologie, symptômes, contexte…'),
                  _clinicalSection('6. EXAMEN CLINIQUE', _clinicalExam, 'Constantes, examen général et ciblé…'),
                  _clinicalSection('7. EXAMENS COMPLÉMENTAIRES', _complementary, 'Biologie, ECG, autres examens…'),
                  _clinicalSection('8. IMAGERIE — CONCLUSION', _imaging, 'Radiographie :\n\nTDM :\n\nÉchographie :\n\nIRM :'),
                  _clinicalSection('9. BILAN', _assessment, 'Synthèse clinique / diagnostic retenu…'),
                  _clinicalSection('10. CONDUITE À TENIR', _plan, 'Traitement, surveillance, orientation…'),
                  _formSection(
                    title: 'DÉCISIONS ET SUIVI',
                    children: [
                      _yesNo('Avis spécialisé ?', _specialist, (value) { setState(() => _specialist = value); _changed(); }),
                      if (_specialist) ...[
                        const SizedBox(height: 8),
                        _specialtyDropdown('Service', _specialistService, (value) { setState(() => _specialistService = value); _changed(); }),
                        const SizedBox(height: 8),
                        _yesNo('Avis fait ?', _specialistDone, (value) { setState(() => _specialistDone = value); _changed(); }),
                      ],
                      const Divider(color: PracticeColors.line, height: 22),
                      _yesNo('Malade en attente ?', _waiting, (value) { setState(() => _waiting = value); _changed(); }),
                      const SizedBox(height: 8),
                      _yesNo('Ordonnance faite ?', _prescription, (value) { setState(() => _prescription = value); _changed(); }),
                      const SizedBox(height: 8),
                      _yesNo('Malade sortant ?', _discharged, (value) { setState(() => _discharged = value); _changed(); }),
                      const SizedBox(height: 8),
                      _yesNo('Hospitalisé ?', _hospitalized, (value) { setState(() => _hospitalized = value); _changed(); }),
                      if (_hospitalized) ...[
                        const SizedBox(height: 8),
                        _specialtyDropdown('Service d’hospitalisation', _hospitalizationService, (value) { setState(() => _hospitalizationService = value); _changed(); }),
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
                    style: FilledButton.styleFrom(backgroundColor: PracticeColors.accent, foregroundColor: PracticeColors.background, minimumSize: const Size.fromHeight(52)),
                    icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_rounded),
                    label: const Text('Enregistrer le malade', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                  const SizedBox(height: 9),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : () => _save(addAnother: true),
                    style: OutlinedButton.styleFrom(foregroundColor: PracticeColors.accent, side: const BorderSide(color: PracticeColors.accent), minimumSize: const Size.fromHeight(50)),
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    label: const Text('Enregistrer et ajouter un autre', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _formSection({required String title, required List<Widget> children}) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: PracticeColors.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: PracticeColors.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: PracticeColors.accent, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: .7)),
          const SizedBox(height: 12),
          ...children,
        ]),
      );

  Widget _clinicalSection(String title, TextEditingController controller, String hint) => _formSection(
        title: title,
        children: [_field(controller, hint, lines: 4)],
      );

  Widget _doubleClinicalSection(String title, String firstLabel, TextEditingController first, String secondLabel, TextEditingController second) => _formSection(
        title: title,
        children: [
          Text(firstLabel.toUpperCase(), style: const TextStyle(color: PracticeColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          _field(first, '$firstLabel…', lines: 2),
          const SizedBox(height: 10),
          Text(secondLabel.toUpperCase(), style: const TextStyle(color: PracticeColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          _field(second, '$secondLabel…', lines: 2),
        ],
      );

  Widget _field(TextEditingController controller, String hint, {IconData? icon, int lines = 1, TextInputType? keyboardType}) => TextFormField(
        controller: controller,
        maxLines: lines,
        keyboardType: keyboardType ?? (lines > 1 ? TextInputType.multiline : TextInputType.text),
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: _practiceInputDecoration(hint, icon),
      );

  Widget _yesNo(String label, bool value, ValueChanged<bool> onChanged) => Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
          SegmentedButton<bool>(
            segments: const [ButtonSegment(value: true, label: Text('Oui')), ButtonSegment(value: false, label: Text('Non'))],
            selected: <bool>{value},
            onSelectionChanged: (selection) => onChanged(selection.first),
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              foregroundColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? PracticeColors.background : PracticeColors.textSecondary),
              backgroundColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? PracticeColors.accent : PracticeColors.background),
              side: const WidgetStatePropertyAll(BorderSide(color: PracticeColors.line)),
            ),
          ),
        ],
      );

  Widget _specialtyDropdown(String label, String? value, ValueChanged<String?> onChanged) => DropdownButtonFormField<String>(
        value: practiceSpecialties.contains(value) ? value : null,
        dropdownColor: PracticeColors.surface,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: _practiceInputDecoration(label, Icons.medical_services_outlined),
        isExpanded: true,
        items: practiceSpecialties.map((service) => DropdownMenuItem(value: service, child: Text(service, overflow: TextOverflow.ellipsis))).toList(),
        onChanged: onChanged,
      );
}

class PracticeAchievementsScreen extends StatefulWidget {
  final AppState appState;
  const PracticeAchievementsScreen({super.key, required this.appState});

  @override
  State<PracticeAchievementsScreen> createState() => _PracticeAchievementsScreenState();
}

class _PracticeAchievementsScreenState extends State<PracticeAchievementsScreen> {
  bool _loading = true;
  List<PracticeAchievement> _items = const [];
  PracticeStats _all = const PracticeStats();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait<dynamic>([PracticeService.instance.achievements(), PracticeService.instance.summary(scope: 'all')]);
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
    return Scaffold(
      backgroundColor: PracticeColors.background,
      appBar: AppBar(backgroundColor: PracticeColors.background, foregroundColor: Colors.white, title: const Text('Succès')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: PracticeColors.accent))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(15, 8, 15, 30),
                children: [
                  _LevelCard(level: level, xp: _all.xp, streak: _all.streak),
                  const SizedBox(height: 16),
                  ..._items.map((item) => Padding(
                        padding: const EdgeInsets.only(bottom: 9),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: PracticeColors.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: item.unlocked ? PracticeColors.accent : PracticeColors.line)),
                          child: Row(children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(color: (item.unlocked ? PracticeColors.accent : PracticeColors.elevated).withOpacity(.16), borderRadius: BorderRadius.circular(15)),
                              child: Icon(_achievementIcon(item.icon), color: item.unlocked ? PracticeColors.accent : PracticeColors.textSecondary),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(item.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                              const SizedBox(height: 3),
                              Text(item.description, style: const TextStyle(color: PracticeColors.textSecondary, fontSize: 11, height: 1.35)),
                              const SizedBox(height: 8),
                              ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(value: item.ratio, minHeight: 6, backgroundColor: PracticeColors.background, color: PracticeColors.accent)),
                              const SizedBox(height: 5),
                              Text('${item.progress} / ${item.threshold}', style: const TextStyle(color: PracticeColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w800)),
                            ])),
                            if (item.unlocked) const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.check_circle_rounded, color: PracticeColors.accent)),
                          ]),
                        ),
                      )),
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
  State<PracticeLeaderboardScreen> createState() => _PracticeLeaderboardScreenState();
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
      PracticeService.instance.leaderboard(period: _period, promotion: _promotionOnly ? _promotion : null),
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
    return Scaffold(
      backgroundColor: PracticeColors.background,
      appBar: AppBar(backgroundColor: PracticeColors.background, foregroundColor: Colors.white, title: const Text('Classement des internes')),
      body: RefreshIndicator(
        onRefresh: _load,
        color: PracticeColors.accent,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(15, 6, 15, 30),
          children: [
            SegmentedButton<String>(
              segments: const [ButtonSegment(value: 'month', label: Text('Ce mois')), ButtonSegment(value: 'year', label: Text('Cette année'))],
              selected: <String>{_period},
              onSelectionChanged: (selection) { _period = selection.first; _load(); },
              style: _segmentStyle(),
            ),
            const SizedBox(height: 10),
            SegmentedButton<bool>(
              segments: const [ButtonSegment(value: true, label: Text('Ma promo')), ButtonSegment(value: false, label: Text('Toutes les promos'))],
              selected: <bool>{_promotionOnly},
              onSelectionChanged: (selection) { _promotionOnly = selection.first; _load(); },
              style: _segmentStyle(),
            ),
            const SizedBox(height: 14),
            _LeaderboardPreferenceCard(
              value: _prefs.leaderboardOptIn,
              onChanged: (value) async {
                await PracticeService.instance.savePreferences(leaderboardOptIn: value, guardGoal: _prefs.guardGoal);
                await _load();
              },
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Center(child: Padding(padding: EdgeInsets.all(42), child: CircularProgressIndicator(color: PracticeColors.accent)))
            else if (_items.isEmpty)
              const _PracticeEmpty(text: 'Aucune activité Practice classée pour cette période.')
            else ...[
              if (_items.length >= 3) _TopThree(items: _items.take(3).toList(), currentUserId: me?.id),
              const SizedBox(height: 12),
              ..._items.map((entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: _RankRow(entry: entry, highlighted: entry.userId == me?.id),
                  )),
            ],
            const SizedBox(height: 14),
            const Text(
              'Practice valorise l’activité documentée uniquement. Ce classement ne mesure ni la compétence médicale, ni la qualité, ni la rapidité des soins.',
              textAlign: TextAlign.center,
              style: TextStyle(color: PracticeColors.textSecondary, fontSize: 11, height: 1.45, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  ButtonStyle _segmentStyle() => ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? PracticeColors.background : Colors.white),
        backgroundColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? PracticeColors.accent : PracticeColors.surface),
        side: const WidgetStatePropertyAll(BorderSide(color: PracticeColors.line)),
      );
}

class PracticeHomeSummary extends StatefulWidget {
  final AppState appState;
  final AppUser user;
  const PracticeHomeSummary({super.key, required this.appState, required this.user});

  @override
  State<PracticeHomeSummary> createState() => _PracticeHomeSummaryState();
}

class _PracticeHomeSummaryState extends State<PracticeHomeSummary> {
  final _service = PracticeService.instance;
  PracticeStats _stats = const PracticeStats();
  PracticeRanks _ranks = const PracticeRanks();
  bool _loading = true;

  PracticeGuard? get _guard => PracticeGuard.current(entries: widget.appState.planning, user: widget.user);

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
        if (guard != null) _service.summary(scope: 'guard', guardId: guard.id) else Future.value(const PracticeStats()),
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
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (guard != null)
            InkWell(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PracticeGuardScreen(appState: widget.appState, guard: guard))),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  const Icon(Icons.description_rounded, color: Colors.white, size: 17),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      _stats.patients == 0 ? 'Votre garde vient de commencer. Prêt pour cette garde ?' : 'Tu as vu ${_stats.patients} malade${_stats.patients > 1 ? 's' : ''} jusqu’à maintenant.',
                      style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w900),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: Colors.white.withOpacity(.75), size: 19),
                ]),
              ),
            ),
          if (guard != null) ...[
            const SizedBox(height: 5),
            Text('${guard.title} · ${guard.timeLabel}', style: TextStyle(color: Colors.white.withOpacity(.78), fontSize: 11.5, fontWeight: FontWeight.w700)),
          ],
          if (showRank) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PracticeLeaderboardScreen(appState: widget.appState))),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: _ranks.hasActivity
                    ? Row(children: [
                        const Icon(Icons.emoji_events_outlined, color: Colors.white, size: 16),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            'Vous êtes classé : ${_ranks.promotionRank == null ? '—' : '${_ranks.promotionRank}e'} dans votre promo · ${_ranks.globalRank == null ? '—' : '${_ranks.globalRank}e'} toutes promos',
                            style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w800),
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: Colors.white.withOpacity(.75), size: 19),
                      ])
                    : Text('Classement disponible après votre première activité Practice.', style: TextStyle(color: Colors.white.withOpacity(.82), fontSize: 11.5, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CurrentGuardCard extends StatelessWidget {
  final PracticeGuard guard;
  final PracticeStats stats;
  final int? goal;
  final VoidCallback onNewCase;
  final VoidCallback onOpenGuard;
  final VoidCallback onEditGoal;
  const _CurrentGuardCard({required this.guard, required this.stats, required this.goal, required this.onNewCase, required this.onOpenGuard, required this.onEditGoal});

  @override
  Widget build(BuildContext context) {
    final ratio = goal == null ? 0.0 : (stats.patients / goal!).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: PracticeColors.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: PracticeColors.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 10, height: 10, decoration: const BoxDecoration(color: PracticeColors.accent, shape: BoxShape.circle)),
          const SizedBox(width: 7),
          const Text('EN COURS', style: TextStyle(color: PracticeColors.accent, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: .8)),
        ]),
        const SizedBox(height: 8),
        Text(guard.title, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900)),
        const SizedBox(height: 3),
        Text('${DateFormat('d MMMM yyyy', 'fr_FR').format(guard.start)} · ${guard.timeLabel}', style: const TextStyle(color: PracticeColors.textSecondary, fontWeight: FontWeight.w600)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _MiniMetric(label: 'Vus', value: '${stats.patients}')),
          const SizedBox(width: 7),
          Expanded(child: _MiniMetric(label: 'Attente', value: '${stats.waiting}')),
          const SizedBox(width: 7),
          Expanded(child: _MiniMetric(label: 'Sortants', value: '${stats.discharged}')),
        ]),
        if (goal != null) ...[
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: Text('Objectif : ${stats.patients} / $goal', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
            Text('${(ratio * 100).round()} %', style: const TextStyle(color: PracticeColors.accent, fontWeight: FontWeight.w900)),
          ]),
          const SizedBox(height: 6),
          ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(value: ratio, minHeight: 7, color: PracticeColors.accent, backgroundColor: PracticeColors.background)),
          const SizedBox(height: 6),
          Text(stats.patients >= goal! ? 'Objectif atteint.' : 'Encore ${goal! - stats.patients} observation${goal! - stats.patients > 1 ? 's' : ''} pour atteindre votre objectif.', style: const TextStyle(color: PracticeColors.textSecondary, fontSize: 11)),
        ],
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: onOpenGuard, style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: PracticeColors.line)), child: const Text('Ma garde'))),
          const SizedBox(width: 8),
          IconButton(onPressed: onEditGoal, tooltip: 'Objectif', icon: const Icon(Icons.flag_outlined), color: PracticeColors.textSecondary),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onNewCase,
            style: FilledButton.styleFrom(backgroundColor: PracticeColors.accent, foregroundColor: PracticeColors.background, minimumSize: const Size.fromHeight(52)),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Nouveau malade', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          ),
        ),
      ]),
    );
  }
}

class _NoGuardCard extends StatelessWidget {
  final VoidCallback onHistory;
  const _NoGuardCard({required this.onHistory});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: PracticeColors.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: PracticeColors.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.event_available_rounded, color: PracticeColors.textSecondary, size: 30),
          const SizedBox(height: 10),
          const Text('Aucune garde Urgences en cours.', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
          const SizedBox(height: 5),
          const Text('Vous pouvez consulter votre historique, vos statistiques et votre progression.', style: TextStyle(color: PracticeColors.textSecondary, height: 1.4)),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: onHistory, icon: const Icon(Icons.history_rounded), label: const Text('Voir l’historique'), style: OutlinedButton.styleFrom(foregroundColor: PracticeColors.accent, side: const BorderSide(color: PracticeColors.line))),
        ]),
      );
}

class _LevelCard extends StatelessWidget {
  final PracticeLevel level;
  final int xp;
  final int streak;
  const _LevelCard({required this.level, required this.xp, required this.streak});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: PracticeColors.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: PracticeColors.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('NIVEAU ${level.number}', style: const TextStyle(color: PracticeColors.accent, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: .8)),
              const SizedBox(height: 3),
              Text(level.name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
            ])),
            Text('🔥 Série de $streak garde${streak > 1 ? 's' : ''}', style: const TextStyle(color: PracticeColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 12),
          ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(value: level.progressFor(xp), minHeight: 8, color: PracticeColors.accent, backgroundColor: PracticeColors.background)),
          const SizedBox(height: 6),
          Text('${level.xpIntoLevel(xp)} / ${level.xpForLevel} XP · $xp XP au total', style: const TextStyle(color: PracticeColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
      );
}

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final bool loading;
  const _StatCard({required this.value, required this.label, required this.loading});
  @override
  Widget build(BuildContext context) => Container(
        height: 90,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: PracticeColors.surface, borderRadius: BorderRadius.circular(17), border: Border.all(color: PracticeColors.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(loading ? '…' : value, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 3),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: PracticeColors.textSecondary, fontSize: 10.5, fontWeight: FontWeight.w700)),
        ]),
      );
}

class _PracticeActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _PracticeActionTile({required this.icon, required this.title, required this.subtitle, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: PracticeColors.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: PracticeColors.line)),
            child: Row(children: [
              Container(width: 44, height: 44, decoration: BoxDecoration(color: PracticeColors.elevated, borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: PracticeColors.accent)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: PracticeColors.textSecondary, fontSize: 11, height: 1.35)),
              ])),
              const Icon(Icons.chevron_right_rounded, color: PracticeColors.textSecondary),
            ]),
          ),
        ),
      );
}

class _PatientTile extends StatelessWidget {
  final PracticeCase value;
  final VoidCallback onTap;
  const _PatientTile({required this.value, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: PracticeColors.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: PracticeColors.line)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(value.patientLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                  if (value.pendingSync) ...[
                    const SizedBox(width: 7),
                    const Icon(Icons.cloud_upload_outlined, color: PracticeColors.waiting, size: 15),
                  ],
                ]),
                const SizedBox(height: 4),
                Text(value.displayReason, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: PracticeColors.textSecondary, fontWeight: FontWeight.w700)),
                const SizedBox(height: 5),
                Text([
                  if (value.arrivalTime != null) DateFormat('HH:mm').format(value.arrivalTime!),
                  if ((value.location ?? '').trim().isNotEmpty) value.location!.trim(),
                ].join(' · '), style: const TextStyle(color: PracticeColors.textSecondary, fontSize: 10.5)),
                const SizedBox(height: 8),
                Wrap(spacing: 5, runSpacing: 5, children: _caseBadges(value)),
              ])),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded, color: PracticeColors.textSecondary),
            ]),
          ),
        ),
      );
}

class _LeaderboardPreferenceCard extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _LeaderboardPreferenceCard({required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: PracticeColors.surface, borderRadius: BorderRadius.circular(17), border: Border.all(color: PracticeColors.line)),
        child: Row(children: [
          const Icon(Icons.leaderboard_outlined, color: PracticeColors.accent),
          const SizedBox(width: 10),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Participer au classement', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
            SizedBox(height: 2),
            Text('Vos statistiques privées restent inchangées.', style: TextStyle(color: PracticeColors.textSecondary, fontSize: 10.5)),
          ])),
          Switch(value: value, onChanged: onChanged, activeColor: PracticeColors.accent),
        ]),
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
          Expanded(child: _TopPodium(entry: items[1], height: 88, currentUserId: currentUserId)),
          const SizedBox(width: 7),
          Expanded(child: _TopPodium(entry: items[0], height: 108, currentUserId: currentUserId)),
          const SizedBox(width: 7),
          Expanded(child: _TopPodium(entry: items[2], height: 76, currentUserId: currentUserId)),
        ],
      );
}

class _TopPodium extends StatelessWidget {
  final PracticeRankEntry entry;
  final double height;
  final String? currentUserId;
  const _TopPodium({required this.entry, required this.height, required this.currentUserId});
  @override
  Widget build(BuildContext context) => Container(
        height: height,
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(color: entry.userId == currentUserId ? PracticeColors.elevated : PracticeColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: entry.userId == currentUserId ? PracticeColors.accent : PracticeColors.line)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(entry.rank == 1 ? '🥇' : entry.rank == 2 ? '🥈' : '🥉', style: const TextStyle(fontSize: 20)),
          Text(entry.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w900)),
          const SizedBox(height: 3),
          Text('${entry.xp} XP', style: const TextStyle(color: PracticeColors.accent, fontSize: 10, fontWeight: FontWeight.w900)),
        ]),
      );
}

class _RankRow extends StatelessWidget {
  final PracticeRankEntry entry;
  final bool highlighted;
  const _RankRow({required this.entry, required this.highlighted});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(color: highlighted ? PracticeColors.elevated : PracticeColors.surface, borderRadius: BorderRadius.circular(15), border: Border.all(color: highlighted ? PracticeColors.accent : PracticeColors.line)),
        child: Row(children: [
          SizedBox(width: 34, child: Text('${entry.rank}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900))),
          CircleAvatar(radius: 17, backgroundColor: PracticeColors.background, child: Text(_initials(entry.displayName), style: const TextStyle(color: PracticeColors.accent, fontSize: 10, fontWeight: FontWeight.w900))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(entry.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
            Text([
              if (entry.promotionNumber != null) 'Promo ${entry.promotionNumber}',
              if (entry.hospital.trim().isNotEmpty) entry.hospital,
            ].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: PracticeColors.textSecondary, fontSize: 10)),
          ])),
          Text('${entry.xp} XP', style: const TextStyle(color: PracticeColors.accent, fontWeight: FontWeight.w900)),
        ]),
      );
}

class _FormHeader extends StatelessWidget {
  final String patientNumber;
  final String syncLabel;
  final bool pending;
  const _FormHeader({required this.patientNumber, required this.syncLabel, required this.pending});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: PracticeColors.elevated, borderRadius: BorderRadius.circular(19)),
        child: Row(children: [
          Container(width: 46, height: 46, decoration: BoxDecoration(color: PracticeColors.background, borderRadius: BorderRadius.circular(15)), child: const Icon(Icons.person_outline_rounded, color: PracticeColors.accent)),
          const SizedBox(width: 11),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Patient #$patientNumber', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(pending ? 'À synchroniser' : syncLabel, style: TextStyle(color: pending ? PracticeColors.waiting : PracticeColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w700)),
          ])),
          const Icon(Icons.shield_outlined, color: PracticeColors.textSecondary),
        ]),
      );
}

class _EncouragementCard extends StatelessWidget {
  final String text;
  const _EncouragementCard({required this.text});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: PracticeColors.elevated, borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          const Icon(Icons.auto_awesome_rounded, color: PracticeColors.accent),
          const SizedBox(width: 11),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white, height: 1.4, fontWeight: FontWeight.w800))),
        ]),
      );
}

class _PracticeNotice extends StatelessWidget {
  final IconData icon;
  final String text;
  const _PracticeNotice({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: PracticeColors.surface, borderRadius: BorderRadius.circular(15), border: Border.all(color: PracticeColors.line)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: PracticeColors.textSecondary, size: 18),
          const SizedBox(width: 9),
          Expanded(child: Text(text, style: const TextStyle(color: PracticeColors.textSecondary, fontSize: 11.5, height: 1.4))),
        ]),
      );
}

class _PracticeEmpty extends StatelessWidget {
  final String text;
  const _PracticeEmpty({required this.text});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: PracticeColors.surface, borderRadius: BorderRadius.circular(18)),
        child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: PracticeColors.textSecondary, fontWeight: FontWeight.w700)),
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
        decoration: BoxDecoration(color: PracticeColors.background.withOpacity(.65), borderRadius: BorderRadius.circular(13)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
          Text(label, style: const TextStyle(color: PracticeColors.textSecondary, fontSize: 9.5, fontWeight: FontWeight.w700)),
        ]),
      );
}

class _MonthlyBars extends StatelessWidget {
  final List<int> values;
  const _MonthlyBars({required this.values});
  @override
  Widget build(BuildContext context) {
    const labels = ['J','F','M','A','M','J','J','A','S','O','N','D'];
    final maxValue = values.isEmpty ? 1 : values.reduce((a, b) => a > b ? a : b).clamp(1, 1000000);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(12, (i) {
        final value = i < values.length ? values[i] : 0;
        final ratio = value / maxValue;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
              Text('$value', style: const TextStyle(color: PracticeColors.textSecondary, fontSize: 8)),
              const SizedBox(height: 3),
              Container(height: 150 * ratio + 5, decoration: BoxDecoration(color: PracticeColors.accent.withOpacity(.35 + .65 * ratio), borderRadius: BorderRadius.circular(6))),
              const SizedBox(height: 4),
              Text(labels[i], style: const TextStyle(color: PracticeColors.textSecondary, fontSize: 9, fontWeight: FontWeight.w800)),
            ]),
          ),
        );
      }),
    );
  }
}

List<Widget> _caseBadges(PracticeCase value) {
  final items = <Widget>[];
  if (value.waiting) items.add(const _StatusBadge('En attente', PracticeColors.waiting));
  if (value.specialistOpinionRequested) items.add(_StatusBadge(value.specialistService == null ? 'Avis spécialisé' : 'Avis ${value.specialistService}', PracticeColors.specialist));
  if (value.discharged) items.add(const _StatusBadge('Sortant', PracticeColors.discharged));
  if (value.hospitalized) items.add(const _StatusBadge('Hospitalisé', PracticeColors.hospitalized));
  if (value.prescriptionDone) items.add(const _StatusBadge('Ordonnance faite', PracticeColors.prescription));
  if (value.pendingSync) items.add(const _StatusBadge('À synchroniser', PracticeColors.waiting));
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
        decoration: BoxDecoration(color: color.withOpacity(.14), borderRadius: BorderRadius.circular(999), border: Border.all(color: color.withOpacity(.45))),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.w900)),
      );
}

InputDecoration _practiceInputDecoration(String hint, [IconData? icon]) => InputDecoration(
      hintText: hint,
      labelText: null,
      hintStyle: const TextStyle(color: PracticeColors.textSecondary, fontSize: 12),
      prefixIcon: icon == null ? null : Icon(icon, color: PracticeColors.textSecondary, size: 19),
      filled: true,
      fillColor: PracticeColors.background.withOpacity(.72),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: PracticeColors.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: PracticeColors.accent, width: 1.5)),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    );

Widget _sectionLabel(String label) => Text(label, style: const TextStyle(color: PracticeColors.textSecondary, fontSize: 10.5, fontWeight: FontWeight.w900, letterSpacing: .9));

IconData _achievementIcon(String key) {
  switch (key) {
    case 'flag': return Icons.flag_rounded;
    case 'clinical_notes': return Icons.description_rounded;
    case 'verified': return Icons.verified_rounded;
    case 'groups': return Icons.groups_rounded;
    case 'calendar_month': return Icons.calendar_month_rounded;
    case 'local_fire_department': return Icons.local_fire_department_rounded;
    case 'workspace_premium': return Icons.workspace_premium_rounded;
    default: return Icons.military_tech_rounded;
  }
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty && e.toLowerCase() != 'dr').toList();
  if (parts.isEmpty) return 'DR';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
}
