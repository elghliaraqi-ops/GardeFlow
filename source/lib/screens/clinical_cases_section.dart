import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/clinical_case_post.dart';
import '../services/clinical_case_service.dart';
import '../theme/app_theme.dart';
import 'clinical_case_specialty.dart';

abstract final class _CaseGameColors {
  static const bg = Color(0xFF071526);
  static const surface = Color(0xFF10243A);
  static const elevated = Color(0xFF17314E);
  static const purple = Color(0xFF8B6CFF);
  static const blue = Color(0xFF3295FF);
  static const gold = Color(0xFFFFD166);
  static const mint = Color(0xFF5BE7B0);
  static const text = Color(0xFFF5F8FF);
  static const secondary = Color(0xFFB9CBE0);
  static const line = Color(0xFF244B68);
}

class ClinicalCasesSection extends StatefulWidget {
  final GlobalKey? verticalFeedKey;

  const ClinicalCasesSection({super.key, this.verticalFeedKey});

  @override
  State<ClinicalCasesSection> createState() => _ClinicalCasesSectionState();
}

class _ClinicalCasesSectionState extends State<ClinicalCasesSection> {
  static const _pageSize = 10;
  final _service = ClinicalCaseService.instance;
  final List<ClinicalCasePost> _items = <ClinicalCasePost>[];

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  String? _selectedSpecialty;

  @override
  void initState() {
    super.initState();
    _service.revision.addListener(_onRevision);
    _load(reset: true);
  }

  @override
  void dispose() {
    _service.revision.removeListener(_onRevision);
    super.dispose();
  }

  void _onRevision() {
    if (!mounted) return;
    _load(reset: true);
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      if (mounted) {
        setState(() {
          _loading = true;
          _error = null;
        });
      }
    } else {
      if (_loadingMore || !_hasMore) return;
      setState(() => _loadingMore = true);
    }

    try {
      final page = await _service.fetchFeed(
        offset: reset ? 0 : _items.length,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        final known = _items.map((item) => item.id).toSet();
        _items.addAll(page.where((item) => !known.contains(item.id)));
        _hasMore = page.length == _pageSize;
        _error = null;
        if (_selectedSpecialty != null &&
            !_items.any((item) => item.specialtyLabel == _selectedSpecialty)) {
          _selectedSpecialty = null;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(
        () =>
            _error = 'Le fil des cas cliniques est momentanément indisponible.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Map<String, List<ClinicalCasePost>> _groupedItems() {
    final groups = <String, List<ClinicalCasePost>>{};
    for (final item in _items) {
      groups.putIfAbsent(item.specialtyLabel, () => <ClinicalCasePost>[]).add(item);
    }
    final keys = groups.keys.toList()
      ..sort((a, b) {
        final rank = _specialtyRank(a).compareTo(_specialtyRank(b));
        return rank != 0 ? rank : a.compareTo(b);
      });
    return <String, List<ClinicalCasePost>>{
      for (final key in keys) key: groups[key]!,
    };
  }

  static int _specialtyRank(String value) {
    const order = <String>[
      'Cardiologie',
      'Pneumologie',
      'Neurologie',
      'Gastro-entérologie',
      'Chirurgie viscérale',
      'Urologie-Néphrologie',
      'Traumatologie-Orthopédie',
      'Gynécologie-Obstétrique',
      'Pédiatrie',
      'Endocrinologie',
      'Infectiologie',
      'Hématologie-Oncologie',
      'Médecine interne',
      'Anesthésie-Réanimation',
      'ORL',
      'Ophtalmologie',
      'Dermatologie',
      'Psychiatrie',
      'Médecine générale',
    ];
    final index = order.indexOf(value);
    return index < 0 ? order.length : index;
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groupedItems();
    final visibleGroups = _selectedSpecialty == null
        ? groups
        : <String, List<ClinicalCasePost>>{
            if (groups[_selectedSpecialty!] != null)
              _selectedSpecialty!: groups[_selectedSpecialty!]!,
          };

    return Container(
      key: widget.verticalFeedKey,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ArenaHeader(
            loading: _loading,
            onRefresh: () => _load(reset: true),
          ),
          const SizedBox(height: 16),
          if (_loading && _items.isEmpty)
            const _LoadingCard()
          else if (_error != null && _items.isEmpty)
            _InfoCard(
              icon: Icons.cloud_off_rounded,
              title: 'Impossible de charger les cas',
              body: _error!,
              actionLabel: 'Réessayer',
              onAction: () => _load(reset: true),
            )
          else if (_items.isEmpty)
            const _InfoCard(
              icon: Icons.school_outlined,
              title: 'Aucun cas publié pour le moment',
              body:
                  'Les patients validés dans Practice apparaîtront ici automatiquement et seront rangés par spécialité.',
            )
          else ...[
            _SpecialtyFilter(
              groups: groups,
              selected: _selectedSpecialty,
              onSelected: (value) => setState(() => _selectedSpecialty = value),
            ),
            const SizedBox(height: 20),
            for (final entry in visibleGroups.entries) ...[
              _SpecialtyHeader(
                specialty: entry.key,
                count: entry.value.length,
              ),
              const SizedBox(height: 10),
              for (var i = 0; i < entry.value.length; i++) ...[
                _ClinicalCaseCard(
                  post: entry.value[i],
                  number: _items.indexOf(entry.value[i]) + 1,
                ),
                if (i != entry.value.length - 1) const SizedBox(height: 12),
              ],
              const SizedBox(height: 22),
            ],
            if (_hasMore)
              Center(
                child: OutlinedButton.icon(
                  onPressed: _loadingMore ? null : () => _load(reset: false),
                  icon: _loadingMore
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.expand_more_rounded),
                  label: Text(
                    _loadingMore ? 'Chargement…' : 'Afficher plus de cas',
                  ),
                ),
              ),
          ],
          const SizedBox(height: 12),
          const _PrivacyNote(),
        ],
      ),
    );
  }
}

class _ArenaHeader extends StatelessWidget {
  final bool loading;
  final VoidCallback onRefresh;

  const _ArenaHeader({required this.loading, required this.onRefresh});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF6B50E8), Color(0xFF226FC6), Color(0xFF0B8F76)],
            stops: [0, .55, 1],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white24),
          boxShadow: [
            BoxShadow(
              color: _CaseGameColors.purple.withOpacity(.22),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(.13),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _CaseGameColors.gold.withOpacity(.34)),
              ),
              child: const Icon(
                Icons.medical_information_rounded,
                color: _CaseGameColors.gold,
                size: 26,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CLINICAL ARENA',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .5,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Cas rangés par spécialité · 5 défis QCM par cas',
                    style: TextStyle(
                      color: Color(0xFFE9F2FF),
                      fontSize: 10.8,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Actualiser',
              onPressed: loading ? null : onRefresh,
              icon: const Icon(Icons.refresh_rounded),
              color: Colors.white,
            ),
          ],
        ),
      );
}

class _SpecialtyFilter extends StatelessWidget {
  final Map<String, List<ClinicalCasePost>> groups;
  final String? selected;
  final ValueChanged<String?> onSelected;

  const _SpecialtyFilter({
    required this.groups,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.category_rounded, color: _CaseGameColors.gold, size: 18),
              SizedBox(width: 7),
              Text(
                'SPÉCIALITÉS',
                style: TextStyle(
                  color: _CaseGameColors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .45,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                _SpecialtyChip(
                  label: 'Toutes',
                  count: groups.values.fold<int>(0, (sum, values) => sum + values.length),
                  selected: selected == null,
                  onTap: () => onSelected(null),
                ),
                for (final entry in groups.entries) ...[
                  const SizedBox(width: 8),
                  _SpecialtyChip(
                    label: entry.key,
                    count: entry.value.length,
                    selected: selected == entry.key,
                    onTap: () => onSelected(entry.key),
                  ),
                ],
              ],
            ),
          ),
        ],
      );
}

class _SpecialtyChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _SpecialtyChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: selected
                  ? _CaseGameColors.purple.withOpacity(.28)
                  : _CaseGameColors.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected ? _CaseGameColors.purple : _CaseGameColors.line,
              ),
            ),
            child: Row(
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: selected
                        ? _CaseGameColors.text
                        : _CaseGameColors.secondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(.08),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: _CaseGameColors.gold,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _SpecialtyHeader extends StatelessWidget {
  final String specialty;
  final int count;

  const _SpecialtyHeader({required this.specialty, required this.count});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _CaseGameColors.purple.withOpacity(.18),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: _CaseGameColors.purple.withOpacity(.32)),
            ),
            child: Icon(
              _specialtyIcon(specialty),
              color: _CaseGameColors.gold,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  specialty,
                  style: const TextStyle(
                    color: _CaseGameColors.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '$count cas clinique${count > 1 ? 's' : ''}',
                  style: const TextStyle(
                    color: _CaseGameColors.secondary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}

IconData _specialtyIcon(String specialty) {
  switch (specialty) {
    case 'Cardiologie':
      return Icons.favorite_rounded;
    case 'Pneumologie':
      return Icons.air_rounded;
    case 'Neurologie':
      return Icons.psychology_rounded;
    case 'Gastro-entérologie':
    case 'Chirurgie viscérale':
      return Icons.medical_services_rounded;
    case 'Urologie-Néphrologie':
      return Icons.water_drop_rounded;
    case 'Traumatologie-Orthopédie':
      return Icons.accessibility_new_rounded;
    case 'Gynécologie-Obstétrique':
      return Icons.pregnant_woman_rounded;
    case 'Pédiatrie':
      return Icons.child_care_rounded;
    case 'Endocrinologie':
      return Icons.bloodtype_rounded;
    case 'Infectiologie':
      return Icons.coronavirus_rounded;
    case 'Hématologie-Oncologie':
      return Icons.biotech_rounded;
    case 'ORL':
      return Icons.hearing_rounded;
    case 'Ophtalmologie':
      return Icons.visibility_rounded;
    case 'Dermatologie':
      return Icons.spa_rounded;
    case 'Psychiatrie':
      return Icons.self_improvement_rounded;
    case 'Anesthésie-Réanimation':
      return Icons.monitor_heart_rounded;
    default:
      return Icons.local_hospital_rounded;
  }
}

class _ClinicalCaseCard extends StatefulWidget {
  final ClinicalCasePost post;
  final int number;

  const _ClinicalCaseCard({required this.post, required this.number});

  @override
  State<_ClinicalCaseCard> createState() => _ClinicalCaseCardState();
}

class _ClinicalCaseCardState extends State<_ClinicalCaseCard> {
  bool _detailsExpanded = false;
  bool _qcmExpanded = false;
  bool _submitting = false;
  bool _explanationExpanded = false;
  int _currentQcm = 0;
  List<ClinicalCaseQcm> _qcms = <ClinicalCaseQcm>[];

  @override
  void initState() {
    super.initState();
    _syncQcms(resetIndex: true);
  }

  @override
  void didUpdateWidget(covariant _ClinicalCaseCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed =
        widget.post.id != oldWidget.post.id ||
        widget.post.qcms.length != oldWidget.post.qcms.length ||
        widget.post.qcms
                .map((q) => '${q.id}:${q.mySelectedIndex}:${q.correction.length}')
                .join('|') !=
            oldWidget.post.qcms
                .map((q) => '${q.id}:${q.mySelectedIndex}:${q.correction.length}')
                .join('|');
    if (changed) _syncQcms(resetIndex: widget.post.id != oldWidget.post.id);
  }

  void _syncQcms({required bool resetIndex}) {
    final available = List<ClinicalCaseQcm>.from(widget.post.qcms)
      ..sort((a, b) => a.position.compareTo(b.position));
    final valid = available
        .where(
          (qcm) =>
              qcm.id.trim().isNotEmpty &&
              qcm.question.trim().isNotEmpty &&
              qcm.options.length >= 2,
        )
        .toList(growable: false);
    _qcms = valid.length >= 5
        ? valid.take(5).toList(growable: false)
        : <ClinicalCaseQcm>[];
    if (_qcms.isEmpty) {
      _currentQcm = 0;
      return;
    }
    if (resetIndex || _currentQcm >= _qcms.length) {
      final firstUnanswered = _qcms.indexWhere((q) => !q.answered);
      _currentQcm = firstUnanswered >= 0 ? firstUnanswered : 0;
      _explanationExpanded = false;
    }
  }

  Future<void> _answer(int index) async {
    if (_qcms.isEmpty || _submitting) return;
    final qcm = _qcms[_currentQcm];
    if (qcm.answered) return;
    setState(() => _submitting = true);
    try {
      final result = await ClinicalCaseService.instance.submitQcmAnswer(
        qcmId: qcm.id,
        selectedIndex: index,
      );
      if (!mounted) return;
      setState(() {
        _qcms[_currentQcm] = qcm.copyWith(
          correctIndex: result.correctIndex,
          correction: result.correction,
          mySelectedIndex: result.selectedIndex,
          myIsCorrect: result.isCorrect,
          answeredAt: result.answeredAt,
        );
        _explanationExpanded = true;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d’enregistrer cette réponse QCM.')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _selectQcm(int index) {
    if (index == _currentQcm) return;
    setState(() {
      _currentQcm = index;
      _explanationExpanded = false;
    });
  }

  void _moveQcm(int delta) {
    if (_qcms.isEmpty) return;
    final next = (_currentQcm + delta).clamp(0, _qcms.length - 1);
    if (next != _currentQcm) _selectQcm(next);
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final answeredCount = _qcms.where((q) => q.answered).length;
    final correctCount = _qcms.where((q) => q.myIsCorrect == true).length;
    final current = _qcms.isEmpty ? null : _qcms[_currentQcm];
    final answered = current?.answered == true;
    final correct = current?.myIsCorrect == true;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _CaseGameColors.surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: _CaseGameColors.line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.16),
            blurRadius: 20,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CaseHeader(
              number: widget.number,
              specialty: post.specialtyLabel,
              demographic: post.demographicLabel,
              answered: answeredCount,
              total: _qcms.length,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'RÉSUMÉ DU CAS',
                    style: TextStyle(
                      color: _CaseGameColors.gold,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .65,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    post.presentation.trim().isEmpty
                        ? 'Présentation non renseignée.'
                        : post.presentation.trim(),
                    style: const TextStyle(
                      color: _CaseGameColors.text,
                      fontSize: 13.1,
                      height: 1.48,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (_detailsExpanded) ...[
                    const SizedBox(height: 14),
                    _CaseDetails(post: post),
                  ],
                  const SizedBox(height: 13),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (_hasExtraDetails(post))
                        OutlinedButton.icon(
                          onPressed: () => setState(
                            () => _detailsExpanded = !_detailsExpanded,
                          ),
                          icon: Icon(
                            _detailsExpanded
                                ? Icons.expand_less_rounded
                                : Icons.description_outlined,
                            size: 18,
                          ),
                          label: Text(
                            _detailsExpanded
                                ? 'Réduire le dossier'
                                : 'Voir le dossier complet',
                          ),
                        ),
                      FilledButton.icon(
                        onPressed: current == null
                            ? null
                            : () => setState(() => _qcmExpanded = !_qcmExpanded),
                        icon: Icon(
                          _qcmExpanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.sports_esports_rounded,
                          size: 19,
                        ),
                        label: Text(
                          current == null
                              ? 'QCM en préparation'
                              : _qcmExpanded
                                  ? 'Fermer les QCM'
                                  : answeredCount == 0
                                      ? 'Commencer les QCM'
                                      : 'Continuer les QCM',
                        ),
                      ),
                    ],
                  ),
                  if (_qcms.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _CompactProgress(
                      answered: answeredCount,
                      correct: correctCount,
                      total: _qcms.length,
                    ),
                  ],
                  if (_qcmExpanded && current != null) ...[
                    const SizedBox(height: 18),
                    Container(height: 1, color: _CaseGameColors.line),
                    const SizedBox(height: 18),
                    _QcmStepper(
                      qcms: _qcms,
                      currentIndex: _currentQcm,
                      onSelected: _selectQcm,
                    ),
                    const SizedBox(height: 14),
                    _QuestionPanel(
                      current: current,
                      index: _currentQcm,
                      total: _qcms.length,
                    ),
                    const SizedBox(height: 12),
                    for (var index = 0; index < current.options.length; index++) ...[
                      _QcmOption(
                        index: index,
                        label: current.options[index],
                        selected: current.mySelectedIndex == index,
                        showCorrection: answered,
                        isCorrect: current.correctIndex == index,
                        onTap: answered || _submitting ? null : () => _answer(index),
                      ),
                      if (index != current.options.length - 1)
                        const SizedBox(height: 8),
                    ],
                    if (_submitting) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(
                        minHeight: 3,
                        color: _CaseGameColors.gold,
                        backgroundColor: _CaseGameColors.line,
                      ),
                    ],
                    if (answered) ...[
                      const SizedBox(height: 14),
                      _AnswerResult(
                        correct: correct,
                        expanded: _explanationExpanded,
                        onToggleExplanation: () => setState(
                          () => _explanationExpanded = !_explanationExpanded,
                        ),
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        child: _explanationExpanded
                            ? Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: _GuidelineCorrection(
                                  correction: current.correction,
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                    const SizedBox(height: 14),
                    _QcmNavigation(
                      canGoBack: _currentQcm > 0,
                      canGoNext: _currentQcm < _qcms.length - 1,
                      onBack: () => _moveQcm(-1),
                      onNext: () => _moveQcm(1),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static bool _hasExtraDetails(ClinicalCasePost post) => <String>[
        post.history,
        post.clinicalExam,
        post.complementaryExams,
        post.imagingConclusion,
        post.assessment,
        post.plan,
        post.disposition,
        post.specialistService ?? '',
      ].any((value) => value.trim().isNotEmpty);
}

class _CaseHeader extends StatelessWidget {
  final int number;
  final String specialty;
  final String demographic;
  final int answered;
  final int total;

  const _CaseHeader({
    required this.number,
    required this.specialty,
    required this.demographic,
    required this.answered,
    required this.total,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(15, 13, 14, 13),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              _CaseGameColors.purple.withOpacity(.25),
              _CaseGameColors.elevated,
              _CaseGameColors.blue.withOpacity(.11),
            ],
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _CaseGameColors.purple.withOpacity(.18),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _CaseGameColors.purple.withOpacity(.34)),
              ),
              child: Text(
                '#${number.toString().padLeft(2, '0')}',
                style: const TextStyle(
                  color: _CaseGameColors.gold,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    specialty,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _CaseGameColors.text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    demographic,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _CaseGameColors.secondary,
                      fontSize: 10.3,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            if (total > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(.07),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$answered/$total QCM',
                  style: const TextStyle(
                    color: _CaseGameColors.mint,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
          ],
        ),
      );
}

class _CaseDetails extends StatelessWidget {
  final ClinicalCasePost post;

  const _CaseDetails({required this.post});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          _CaseDetailBlock(
            icon: Icons.history_edu_rounded,
            label: 'Histoire / antécédents',
            value: post.history,
          ),
          _CaseDetailBlock(
            icon: Icons.health_and_safety_outlined,
            label: 'Examen clinique',
            value: post.clinicalExam,
          ),
          _CaseDetailBlock(
            icon: Icons.biotech_outlined,
            label: 'Examens complémentaires',
            value: post.complementaryExams,
          ),
          _CaseDetailBlock(
            icon: Icons.image_search_outlined,
            label: 'Imagerie',
            value: post.imagingConclusion,
          ),
          _CaseDetailBlock(
            icon: Icons.psychology_alt_outlined,
            label: 'Synthèse',
            value: post.assessment,
          ),
          _CaseDetailBlock(
            icon: Icons.medical_services_outlined,
            label: 'Prise en charge documentée',
            value: post.plan,
          ),
          _CaseDetailBlock(
            icon: Icons.alt_route_rounded,
            label: 'Orientation',
            value: post.disposition,
          ),
          _CaseDetailBlock(
            icon: Icons.groups_2_outlined,
            label: 'Avis spécialisé',
            value: post.specialistService ?? '',
          ),
        ],
      );
}

class _CaseDetailBlock extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _CaseDetailBlock({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _CaseGameColors.elevated.withOpacity(.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _CaseGameColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _CaseGameColors.mint, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    color: _CaseGameColors.gold,
                    fontSize: 8.8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .55,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value.trim(),
                  style: const TextStyle(
                    color: _CaseGameColors.text,
                    fontSize: 11.8,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactProgress extends StatelessWidget {
  final int answered;
  final int correct;
  final int total;

  const _CompactProgress({
    required this.answered,
    required this.correct,
    required this.total,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : answered / total,
                minHeight: 6,
                color: _CaseGameColors.mint,
                backgroundColor: _CaseGameColors.line,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '$answered répondu${answered > 1 ? 's' : ''} · $correct juste${correct > 1 ? 's' : ''}',
            style: const TextStyle(
              color: _CaseGameColors.secondary,
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      );
}

class _QcmStepper extends StatelessWidget {
  final List<ClinicalCaseQcm> qcms;
  final int currentIndex;
  final ValueChanged<int> onSelected;

  const _QcmStepper({
    required this.qcms,
    required this.currentIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          for (var i = 0; i < qcms.length; i++) ...[
            Expanded(
              child: InkWell(
                onTap: () => onSelected(i),
                borderRadius: BorderRadius.circular(14),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 170),
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == currentIndex
                        ? _CaseGameColors.purple.withOpacity(.26)
                        : _CaseGameColors.elevated,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: qcms[i].myIsCorrect == true
                          ? AppColors.success
                          : qcms[i].answered
                              ? AppColors.danger
                              : i == currentIndex
                                  ? _CaseGameColors.purple
                                  : _CaseGameColors.line,
                    ),
                  ),
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                      color: qcms[i].myIsCorrect == true
                          ? AppColors.success
                          : qcms[i].answered
                              ? AppColors.danger
                              : _CaseGameColors.text,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
            if (i != qcms.length - 1) const SizedBox(width: 6),
          ],
        ],
      );
}

class _QuestionPanel extends StatelessWidget {
  final ClinicalCaseQcm current;
  final int index;
  final int total;

  const _QuestionPanel({
    required this.current,
    required this.index,
    required this.total,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _CaseGameColors.purple.withOpacity(.24),
              _CaseGameColors.elevated,
              _CaseGameColors.blue.withOpacity(.12),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _CaseGameColors.purple.withOpacity(.42)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.bolt_rounded,
                  color: _CaseGameColors.gold,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  'QUESTION ${index + 1} / $total',
                  style: const TextStyle(
                    color: _CaseGameColors.gold,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .7,
                  ),
                ),
                const Spacer(),
                if (current.generationSource == 'openai') ...[
                  const Icon(
                    Icons.auto_awesome_rounded,
                    color: _CaseGameColors.mint,
                    size: 13,
                  ),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    current.topicLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _CaseGameColors.secondary,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 11),
            Text(
              current.question,
              style: const TextStyle(
                color: _CaseGameColors.text,
                fontSize: 16,
                height: 1.45,
                fontWeight: FontWeight.w900,
                letterSpacing: -.1,
              ),
            ),
          ],
        ),
      );
}

class _QcmOption extends StatelessWidget {
  final int index;
  final String label;
  final bool selected;
  final bool showCorrection;
  final bool isCorrect;
  final VoidCallback? onTap;

  const _QcmOption({
    required this.index,
    required this.label,
    required this.selected,
    required this.showCorrection,
    required this.isCorrect,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color border = _CaseGameColors.line;
    Color background = _CaseGameColors.elevated.withOpacity(.72);
    Color foreground = _CaseGameColors.text;
    if (showCorrection && isCorrect) {
      border = AppColors.success;
      background = AppColors.success.withOpacity(.10);
      foreground = AppColors.success;
    } else if (showCorrection && selected && !isCorrect) {
      border = AppColors.danger;
      background = AppColors.danger.withOpacity(.10);
      foreground = AppColors.danger;
    } else if (selected) {
      border = _CaseGameColors.purple;
      background = _CaseGameColors.purple.withOpacity(.18);
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: border,
              width: selected || (showCorrection && isCorrect) ? 1.4 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: foreground.withOpacity(.10),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: foreground.withOpacity(.18)),
                ),
                child: Text(
                  String.fromCharCode(65 + index),
                  style: TextStyle(
                    color: foreground,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 12.8,
                      height: 1.45,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              if (showCorrection && isCorrect)
                const Padding(
                  padding: EdgeInsets.only(left: 7, top: 5),
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.success,
                    size: 19,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnswerResult extends StatelessWidget {
  final bool correct;
  final bool expanded;
  final VoidCallback onToggleExplanation;

  const _AnswerResult({
    required this.correct,
    required this.expanded,
    required this.onToggleExplanation,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: (correct ? AppColors.success : AppColors.danger).withOpacity(.09),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: (correct ? AppColors.success : AppColors.danger).withOpacity(.40),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  correct ? Icons.check_circle_rounded : Icons.cancel_rounded,
                  color: correct ? AppColors.success : AppColors.danger,
                  size: 20,
                ),
                const SizedBox(width: 7),
                Text(
                  correct ? 'Bonne réponse' : 'Réponse à revoir',
                  style: TextStyle(
                    color: correct ? AppColors.success : AppColors.danger,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: onToggleExplanation,
                icon: Icon(
                  expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.auto_awesome_rounded,
                ),
                label: Text(
                  expanded
                      ? 'Masquer l’explication IA'
                      : 'Voir l’explication IA',
                ),
              ),
            ),
          ],
        ),
      );
}

class _QcmNavigation extends StatelessWidget {
  final bool canGoBack;
  final bool canGoNext;
  final VoidCallback onBack;
  final VoidCallback onNext;

  const _QcmNavigation({
    required this.canGoBack,
    required this.canGoNext,
    required this.onBack,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: canGoBack ? onBack : null,
              icon: const Icon(Icons.chevron_left_rounded),
              label: const Text('Précédent'),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: FilledButton.icon(
              onPressed: canGoNext ? onNext : null,
              icon: const Icon(Icons.chevron_right_rounded),
              label: const Text('Suivant'),
            ),
          ),
        ],
      );
}

class _GuidelineReference {
  final String kind;
  final String title;
  final String organization;
  final String year;
  final Uri url;

  const _GuidelineReference({
    required this.kind,
    required this.title,
    required this.organization,
    required this.year,
    required this.url,
  });
}

class _GuidelineCorrection extends StatelessWidget {
  final String correction;

  const _GuidelineCorrection({required this.correction});

  ({String explanation, List<_GuidelineReference> references}) _parse() {
    const marker = '\n\n§SOURCES§\n';
    final raw = correction.trim();
    final markerIndex = raw.indexOf(marker);
    if (markerIndex < 0) {
      return (explanation: raw, references: const <_GuidelineReference>[]);
    }

    final explanation = raw.substring(0, markerIndex).trim();
    final sourcesText = raw.substring(markerIndex + marker.length).trim();
    final references = <_GuidelineReference>[];
    for (final line in sourcesText.split('\n')) {
      final parts = line.split('|||');
      if (parts.length != 5) continue;
      final uri = Uri.tryParse(parts[4].trim());
      if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) {
        continue;
      }
      references.add(
        _GuidelineReference(
          kind: parts[0].trim(),
          title: parts[1].trim(),
          organization: parts[2].trim(),
          year: parts[3].trim(),
          url: uri,
        ),
      );
    }
    return (explanation: explanation, references: references);
  }

  String _kindLabel(String value) {
    switch (value) {
      case 'recommandation':
        return 'Recommandation';
      case 'consensus':
        return 'Consensus';
      case 'revue':
        return 'Revue';
      case 'cours':
        return 'Cours';
      default:
        return 'Source';
    }
  }

  @override
  Widget build(BuildContext context) {
    final parsed = _parse();
    final explanation = parsed.explanation.trim().isEmpty
        ? 'Explication pédagogique en préparation.'
        : parsed.explanation.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _CaseGameColors.purple.withOpacity(.20),
            _CaseGameColors.surface,
            _CaseGameColors.blue.withOpacity(.09),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _CaseGameColors.purple.withOpacity(.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                color: _CaseGameColors.gold,
                size: 18,
              ),
              SizedBox(width: 7),
              Expanded(
                child: Text(
                  'EXPLICATION IA',
                  style: TextStyle(
                    color: _CaseGameColors.gold,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .65,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Pourquoi cette réponse ?',
            style: TextStyle(
              color: _CaseGameColors.text,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 11),
          _ExplanationBody(text: explanation),
          if (parsed.references.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(height: 1, color: _CaseGameColors.line),
            const SizedBox(height: 12),
            const Row(
              children: [
                Icon(
                  Icons.menu_book_rounded,
                  size: 16,
                  color: _CaseGameColors.mint,
                ),
                SizedBox(width: 6),
                Text(
                  'SOURCES',
                  style: TextStyle(
                    color: _CaseGameColors.mint,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .55,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final ref in parsed.references) ...[
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(13),
                  onTap: () =>
                      launchUrl(ref.url, mode: LaunchMode.externalApplication),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(.045),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: _CaseGameColors.line),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_kindLabel(ref.kind)} · ${ref.organization} · ${ref.year}',
                                style: const TextStyle(
                                  color: _CaseGameColors.gold,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                ref.title,
                                style: const TextStyle(
                                  color: _CaseGameColors.secondary,
                                  fontSize: 11,
                                  height: 1.35,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.open_in_new_rounded,
                          size: 15,
                          color: _CaseGameColors.secondary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 7),
            ],
          ],
        ],
      ),
    );
  }
}

class _ExplanationBody extends StatelessWidget {
  final String text;

  const _ExplanationBody({required this.text});

  @override
  Widget build(BuildContext context) {
    final blocks = text
        .split(RegExp(r'\n+'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    final visible = blocks.isEmpty ? <String>[text.trim()] : blocks;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < visible.length; i++) ...[
          _ExplanationParagraph(text: visible[i]),
          if (i != visible.length - 1) const SizedBox(height: 9),
        ],
      ],
    );
  }
}

class _ExplanationParagraph extends StatelessWidget {
  final String text;

  const _ExplanationParagraph({required this.text});

  @override
  Widget build(BuildContext context) {
    final isBullet = text.startsWith('- ') ||
        text.startsWith('• ') ||
        RegExp(r'^\d+[\.)]\s').hasMatch(text);
    final cleaned = text.replaceFirst(RegExp(r'^(?:[-•]\s|\d+[\.)]\s)'), '');

    if (!isBullet) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(.045),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _CaseGameColors.line.withOpacity(.70)),
        ),
        child: Text(
          cleaned,
          style: const TextStyle(
            color: _CaseGameColors.text,
            fontSize: 13,
            height: 1.55,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 7,
          height: 7,
          margin: const EdgeInsets.only(top: 7),
          decoration: const BoxDecoration(
            color: _CaseGameColors.gold,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            cleaned,
            style: const TextStyle(
              color: _CaseGameColors.text,
              fontSize: 12.8,
              height: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) => Container(
        height: 150,
        width: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _CaseGameColors.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _CaseGameColors.line),
        ),
        child: const CircularProgressIndicator(color: _CaseGameColors.mint),
      );
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _CaseGameColors.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _CaseGameColors.line),
        ),
        child: Column(
          children: [
            Icon(icon, color: _CaseGameColors.gold, size: 30),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _CaseGameColors.text,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _CaseGameColors.secondary,
                fontSize: 11.5,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 12),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      );
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _CaseGameColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _CaseGameColors.line),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.shield_outlined, size: 17, color: _CaseGameColors.mint),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Les cas sont automatiquement dé-identifiés avant publication. Les QCM ont un objectif pédagogique et ne constituent pas une recommandation clinique.',
                style: TextStyle(
                  color: _CaseGameColors.secondary,
                  fontSize: 10.5,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
}
