import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/clinical_case_post.dart';
import '../services/clinical_case_service.dart';
import '../theme/app_theme.dart';
import '../theme/screen_decor.dart';

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

  @override
  Widget build(BuildContext context) {
    return Container(
      key: widget.verticalFeedKey,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecorSectionBanner(
            scene: ScreenDecorScene.practice,
            title: 'CAS CLINIQUES',
            subtitle: 'Dossiers anonymisés · raisonnement clinique · 5 QCM par cas',
            icon: Icons.medical_information_rounded,
            trailing: DecorIconAction(
              icon: Icons.refresh_rounded,
              tooltip: 'Actualiser',
              onTap: _loading ? null : () => _load(reset: true),
            ),
          ),
          const SizedBox(height: 12),
          if (_loading && _items.isEmpty)
            _LoadingCard()
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
              body: 'Les patients validés dans Practice apparaîtront ici automatiquement sous forme anonymisée avec 5 QCM pédagogiques.',
            )
          else ...[
            for (var i = 0; i < _items.length; i++) ...[
              _ClinicalCaseCard(post: _items[i], number: i + 1),
              if (i != _items.length - 1) const SizedBox(height: 12),
            ],
            if (_hasMore) ...[
              const SizedBox(height: 14),
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
          ],
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.paperAlt,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.shield_outlined, size: 17, color: AppColors.inkSoft),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Les cas sont automatiquement dé-identifiés avant publication. Les QCM reflètent le cas documenté et ont un objectif pédagogique ; ils ne constituent pas une recommandation clinique.',
                    style: TextStyle(
                      color: AppColors.inkSoft,
                      fontSize: 10.5,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
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

class _ClinicalCaseCard extends StatefulWidget {
  final ClinicalCasePost post;
  final int number;

  const _ClinicalCaseCard({required this.post, required this.number});

  @override
  State<_ClinicalCaseCard> createState() => _ClinicalCaseCardState();
}

class _ClinicalCaseCardState extends State<_ClinicalCaseCard> {
  bool _expanded = false;
  bool _submitting = false;
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
                .map(
                  (q) => '${q.id}:${q.mySelectedIndex}:${q.correction.length}',
                )
                .join('|') !=
            oldWidget.post.qcms
                .map(
                  (q) => '${q.id}:${q.mySelectedIndex}:${q.correction.length}',
                )
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
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossible d’enregistrer cette réponse QCM.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _moveQcm(int delta) {
    if (_qcms.isEmpty) return;
    final next = (_currentQcm + delta).clamp(0, _qcms.length - 1);
    if (next != _currentQcm) setState(() => _currentQcm = next);
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.card, AppColors.brandSoft.withOpacity(.38)],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.brand.withOpacity(.30)),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withOpacity(0.13),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: AppColors.brandSoft,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.brand.withOpacity(.16)),
                ),
                child: Text(
                  'CAS #${widget.number.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    color: AppColors.brandBright,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.7,
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  post.demographicLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.inkSoft,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.paperAlt,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.line),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _qcms.any((q) => q.generationSource == 'openai')
                          ? Icons.auto_awesome_rounded
                          : Icons.quiz_outlined,
                      size: 12,
                      color: AppColors.brandBright,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _qcms.length >= 5 ? '5 QCM' : 'QCM',
                      style: TextStyle(
                        color: AppColors.inkSoft,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _CaseSection(
            icon: Icons.chat_bubble_outline_rounded,
            label: 'Présentation',
            value: post.presentation,
            alwaysShow: true,
          ),
          if (_expanded) ...[
            _CaseSection(
              icon: Icons.history_edu_rounded,
              label: 'Histoire / antécédents',
              value: post.history,
            ),
            _CaseSection(
              icon: Icons.health_and_safety_outlined,
              label: 'Examen clinique',
              value: post.clinicalExam,
            ),
            _CaseSection(
              icon: Icons.biotech_outlined,
              label: 'Examens complémentaires',
              value: post.complementaryExams,
            ),
            _CaseSection(
              icon: Icons.image_search_outlined,
              label: 'Imagerie',
              value: post.imagingConclusion,
            ),
            _CaseSection(
              icon: Icons.psychology_alt_outlined,
              label: 'Synthèse',
              value: post.assessment,
            ),
            _CaseSection(
              icon: Icons.medical_services_outlined,
              label: 'Prise en charge documentée',
              value: post.plan,
            ),
            if (post.disposition.trim().isNotEmpty)
              _CaseSection(
                icon: Icons.alt_route_rounded,
                label: 'Orientation',
                value: post.disposition,
              ),
            if ((post.specialistService ?? '').trim().isNotEmpty)
              _CaseSection(
                icon: Icons.groups_2_outlined,
                label: 'Avis spécialisé',
                value: post.specialistService!,
              ),
          ],
          if (_hasExtraDetails(post))
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(
                  _expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 18,
                ),
                label: Text(
                  _expanded ? 'Réduire le cas' : 'Voir le cas complet',
                ),
              ),
            ),
          const SizedBox(height: 8),
          if (current == null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.paperAlt,
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: AppColors.line),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.brandBright,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Les QCM de ce cas sont en cours de préparation…',
                      style: TextStyle(
                        color: AppColors.inkSoft,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.brandSoft.withOpacity(.72),
                    AppColors.card,
                  ],
                ),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppColors.brand.withOpacity(.34)),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.brand.withOpacity(.09),
                    blurRadius: 16,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.quiz_rounded,
                        color: AppColors.brandBright,
                        size: 19,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        'QCM ${_currentQcm + 1} / ${_qcms.length}',
                        style: TextStyle(
                          color: AppColors.brandBright,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.7,
                        ),
                      ),
                      const Spacer(),
                      if (current.generationSource == 'openai') ...[
                        Icon(
                          Icons.auto_awesome_rounded,
                          color: AppColors.brandBright,
                          size: 13,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        current.topicLabel,
                        style: TextStyle(
                          color: AppColors.inkSoft,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    current.question,
                    style: TextStyle(
                      color: AppColors.ink,
                      fontSize: 14.5,
                      height: 1.42,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.08,
                    ),
                  ),
                  const SizedBox(height: 11),
                  for (
                    var index = 0;
                    index < current.options.length;
                    index++
                  ) ...[
                    _QcmOption(
                      index: index,
                      label: current.options[index],
                      selected: current.mySelectedIndex == index,
                      showCorrection: answered,
                      isCorrect: current.correctIndex == index,
                      onTap: answered || _submitting
                          ? null
                          : () => _answer(index),
                    ),
                    if (index != current.options.length - 1)
                      const SizedBox(height: 7),
                  ],
                  if (_submitting) ...[
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      minHeight: 2,
                      color: AppColors.brandBright,
                      backgroundColor: AppColors.line,
                    ),
                  ],
                ],
              ),
            ),
            if (answered) ...[
              const SizedBox(height: 11),
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: double.infinity,
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: (correct ? AppColors.success : AppColors.danger)
                      .withOpacity(0.09),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: (correct ? AppColors.success : AppColors.danger)
                        .withOpacity(0.45),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          correct
                              ? Icons.check_circle_rounded
                              : Icons.cancel_rounded,
                          color: correct ? AppColors.success : AppColors.danger,
                          size: 20,
                        ),
                        const SizedBox(width: 7),
                        Text(
                          correct ? 'Bonne réponse' : 'À revoir',
                          style: TextStyle(
                            color: correct
                                ? AppColors.success
                                : AppColors.danger,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          Icons.auto_awesome_rounded,
                          color: AppColors.brandBright,
                          size: 15,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'EXPLICATION + SOURCES',
                          style: TextStyle(
                            color: AppColors.brandBright,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _GuidelineCorrection(correction: current.correction),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                IconButton(
                  tooltip: 'QCM précédent',
                  onPressed: _currentQcm > 0 ? () => _moveQcm(-1) : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_qcms.length, (index) {
                      final q = _qcms[index];
                      final active = index == _currentQcm;
                      return GestureDetector(
                        onTap: () => setState(() => _currentQcm = index),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: active ? 22 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: q.myIsCorrect == true
                                ? AppColors.success
                                : q.answered
                                ? AppColors.danger
                                : active
                                ? AppColors.brandBright
                                : AppColors.line,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                IconButton(
                  tooltip: 'QCM suivant',
                  onPressed: _currentQcm < _qcms.length - 1
                      ? () => _moveQcm(1)
                      : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            Center(
              child: Text(
                '$answeredCount / ${_qcms.length} répondus · $correctCount justes',
                style: TextStyle(
                  color: AppColors.inkSoft,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ],
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
        : parsed.explanation;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          explanation,
          style: TextStyle(
            color: AppColors.inkSoft,
            fontSize: 11.5,
            height: 1.46,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (parsed.references.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Icons.menu_book_rounded,
                size: 15,
                color: AppColors.brandBright,
              ),
              const SizedBox(width: 6),
              Text(
                'SOURCES DU COURS',
                style: TextStyle(
                  color: AppColors.brandBright,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .55,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          for (final ref in parsed.references) ...[
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () =>
                    launchUrl(ref.url, mode: LaunchMode.externalApplication),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.paperAlt,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.line.withOpacity(.75)),
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
                              style: TextStyle(
                                color: AppColors.brandBright,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              ref.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.inkSoft,
                                fontSize: 10.5,
                                height: 1.3,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 7),
                      Icon(
                        Icons.open_in_new_rounded,
                        size: 15,
                        color: AppColors.inkFaint,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],
        ],
      ],
    );
  }
}

class _CaseSection extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool alwaysShow;

  const _CaseSection({
    required this.icon,
    required this.label,
    required this.value,
    this.alwaysShow = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!alwaysShow && value.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.fromLTRB(12, 11, 13, 12),
      decoration: BoxDecoration(
        color: AppColors.card.withOpacity(.90),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: AppColors.brand.withOpacity(.14)),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withOpacity(.035),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.brandSoft,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 17, color: AppColors.brandBright),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    color: AppColors.brandBright,
                    fontSize: 8.8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.68,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value.trim().isEmpty ? 'Non renseigné' : value.trim(),
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 12.2,
                    height: 1.45,
                    fontWeight: FontWeight.w700,
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
    Color border = AppColors.line;
    Color background = AppColors.card;
    Color foreground = AppColors.ink;
    if (showCorrection && isCorrect) {
      border = AppColors.success;
      background = AppColors.success.withOpacity(0.10);
      foreground = AppColors.success;
    } else if (showCorrection && selected && !isCorrect) {
      border = AppColors.danger;
      background = AppColors.danger.withOpacity(0.09);
      foreground = AppColors.danger;
    } else if (selected) {
      border = AppColors.brand;
      background = AppColors.brandSoft;
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
              width: selected || (showCorrection && isCorrect) ? 1.35 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: border.withOpacity(.08),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: foreground.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: foreground.withOpacity(.18)),
                ),
                child: Text(
                  String.fromCharCode(65 + index),
                  style: TextStyle(
                    color: foreground,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 11.8,
                      height: 1.42,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              if (showCorrection && isCorrect)
                Padding(
                  padding: const EdgeInsets.only(left: 7, top: 4),
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

class _LoadingCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 150,
      width: double.infinity,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.line),
      ),
      child: CircularProgressIndicator(color: AppColors.brand),
    );
  }
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
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.brandBright, size: 30),
          const SizedBox(height: 9),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.ink,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.inkSoft,
              fontSize: 11,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 9),
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
