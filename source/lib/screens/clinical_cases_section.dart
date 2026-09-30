import 'package:flutter/material.dart';

import '../models/clinical_case_post.dart';
import '../services/clinical_case_service.dart';
import '../theme/app_theme.dart';

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
      setState(() => _error = 'Le fil des cas cliniques est momentanément indisponible.');
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
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.brandSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.medical_information_outlined, color: AppColors.brandBright),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Fil des cas cliniques',
                      style: TextStyle(
                        color: AppColors.ink,
                        fontFamily: 'SpaceGrotesk',
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.35,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Cas anonymisés · QCM pédagogique · correction après réponse',
                      style: TextStyle(
                        color: AppColors.inkSoft,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Actualiser',
                onPressed: _loading ? null : () => _load(reset: true),
                icon: Icon(Icons.refresh_rounded, color: AppColors.inkSoft),
              ),
            ],
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
              body: 'Les patients validés dans Practice apparaîtront ici automatiquement sous forme anonymisée avec un QCM.',
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
                  label: Text(_loadingMore ? 'Chargement…' : 'Afficher plus de cas'),
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
  int? _selected;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final answered = _selected != null;
    final correct = answered && _selected == post.correctIndex;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.line),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withOpacity(0.08),
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
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.brandSoft,
                  borderRadius: BorderRadius.circular(999),
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
                      post.generationSource == 'openai'
                          ? Icons.auto_awesome_rounded
                          : Icons.quiz_outlined,
                      size: 12,
                      color: AppColors.brandBright,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      post.topicLabel,
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
            _CaseSection(icon: Icons.history_edu_rounded, label: 'Histoire / antécédents', value: post.history),
            _CaseSection(icon: Icons.health_and_safety_outlined, label: 'Examen clinique', value: post.clinicalExam),
            _CaseSection(icon: Icons.biotech_outlined, label: 'Examens complémentaires', value: post.complementaryExams),
            _CaseSection(icon: Icons.image_search_outlined, label: 'Imagerie', value: post.imagingConclusion),
            _CaseSection(icon: Icons.psychology_alt_outlined, label: 'Synthèse', value: post.assessment),
            _CaseSection(icon: Icons.medical_services_outlined, label: 'Prise en charge documentée', value: post.plan),
            if (post.disposition.trim().isNotEmpty)
              _CaseSection(icon: Icons.alt_route_rounded, label: 'Orientation', value: post.disposition),
            if ((post.specialistService ?? '').trim().isNotEmpty)
              _CaseSection(icon: Icons.groups_2_outlined, label: 'Avis spécialisé', value: post.specialistService!),
          ],
          if (_hasExtraDetails(post))
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(_expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18),
                label: Text(_expanded ? 'Réduire le cas' : 'Voir le cas complet'),
              ),
            ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: AppColors.paperAlt,
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.quiz_rounded, color: AppColors.brandBright, size: 19),
                    const SizedBox(width: 7),
                    Text(
                      'QUESTION QCM',
                      style: TextStyle(
                        color: AppColors.brandBright,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.7,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  post.question,
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 13.5,
                    height: 1.35,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 11),
                for (var index = 0; index < post.options.length; index++) ...[
                  _QcmOption(
                    index: index,
                    label: post.options[index],
                    selected: _selected == index,
                    showCorrection: answered,
                    isCorrect: index == post.correctIndex,
                    onTap: answered ? null : () => setState(() => _selected = index),
                  ),
                  if (index != post.options.length - 1) const SizedBox(height: 7),
                ],
              ],
            ),
          ),
          if (answered) ...[
            const SizedBox(height: 11),
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: double.infinity,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: (correct ? AppColors.success : AppColors.danger).withOpacity(0.11),
                borderRadius: BorderRadius.circular(17),
                border: Border.all(
                  color: (correct ? AppColors.success : AppColors.danger).withOpacity(0.45),
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
                        correct ? 'Bonne réponse' : 'À revoir',
                        style: TextStyle(
                          color: correct ? AppColors.success : AppColors.danger,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Correction du cas',
                    style: TextStyle(
                      color: AppColors.ink,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    post.correction,
                    style: TextStyle(
                      color: AppColors.inkSoft,
                      fontSize: 11.5,
                      height: 1.42,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.paperAlt,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 15, color: AppColors.inkSoft),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    color: AppColors.inkFaint,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.65,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value.trim().isEmpty ? 'Non renseigné' : value.trim(),
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 11.5,
                    height: 1.38,
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
      background = AppColors.success.withOpacity(0.11);
      foreground = AppColors.success;
    } else if (showCorrection && selected && !isCorrect) {
      border = AppColors.danger;
      background = AppColors.danger.withOpacity(0.10);
      foreground = AppColors.danger;
    } else if (selected) {
      border = AppColors.brand;
      background = AppColors.brandSoft;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 25,
                height: 25,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: foreground.withOpacity(0.10),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  String.fromCharCode(65 + index),
                  style: TextStyle(
                    color: foreground,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 11,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (showCorrection && isCorrect)
                Padding(
                  padding: const EdgeInsets.only(left: 6, top: 2),
                  child: Icon(Icons.check_circle_rounded, color: AppColors.success, size: 18),
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
            style: TextStyle(color: AppColors.ink, fontSize: 13, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.inkSoft, fontSize: 11, height: 1.35, fontWeight: FontWeight.w600),
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
