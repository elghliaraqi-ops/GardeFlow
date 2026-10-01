import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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
  static const _pageSize = 100;
  final _service = ClinicalCaseService.instance;
  final List<ClinicalCasePost> _items = <ClinicalCasePost>[];
  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  String? _error;
  String? _selectedSpecialtyKey;
  String? _selectedCaseId;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _service.revision.addListener(_onRevision);
    _loadAll();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _service.revision.removeListener(_onRevision);
    super.dispose();
  }

  void _onRevision() {
    if (!mounted) return;
    _loadAll(showLoader: false);
  }

  Future<void> _loadAll({bool showLoader = true}) async {
    if (showLoader && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final loaded = <ClinicalCasePost>[];
      final seenIds = <String>{};
      var offset = 0;
      while (true) {
        final page = await _service.fetchFeed(offset: offset, limit: _pageSize);
        final unseen = page.where((post) => seenIds.add(post.id)).toList();
        loaded.addAll(unseen);
        if (page.length < _pageSize || unseen.isEmpty) break;
        offset += page.length;
      }

      if (!mounted) return;
      final byId = <String, ClinicalCasePost>{};
      for (final post in loaded) {
        byId[post.id] = post;
      }
      setState(() {
        _items
          ..clear()
          ..addAll(byId.values);
        _error = null;

        if (_selectedCaseId != null &&
            !_items.any((post) => post.id == _selectedCaseId)) {
          _selectedCaseId = null;
        }
        if (_selectedSpecialtyKey != null &&
            !_groupedCases().containsKey(_selectedSpecialtyKey)) {
          _selectedSpecialtyKey = null;
          _selectedCaseId = null;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Le fil des cas cliniques est momentanément indisponible.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _specialtyLabel(ClinicalCasePost post) {
    final raw = (post.specialistService ?? '').trim();
    if (raw.isEmpty) return 'Autres cas cliniques';
    final cleaned = raw.replaceAll('_', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) return 'Autres cas cliniques';
    return cleaned
        .split(' ')
        .map((word) => word.isEmpty
            ? word
            : '${word.substring(0, 1).toUpperCase()}${word.substring(1)}')
        .join(' ');
  }

  String _specialtyKey(ClinicalCasePost post) =>
      _specialtyLabel(post).toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  Map<String, _SpecialtyGroup> _groupedCases() {
    final groups = <String, _SpecialtyGroup>{};
    for (final post in _items) {
      final key = _specialtyKey(post);
      final label = _specialtyLabel(post);
      groups.putIfAbsent(key, () => _SpecialtyGroup(key: key, label: label));
      groups[key]!.cases.add(post);
    }
    for (final group in groups.values) {
      group.cases.sort((a, b) {
        final ad = a.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bd = b.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bd.compareTo(ad);
      });
    }
    return groups;
  }

  List<_SpecialtyGroup> _sortedGroups() {
    final groups = _groupedCases().values.toList();
    groups.sort((a, b) {
      final aOther = a.label == 'Autres cas cliniques';
      final bOther = b.label == 'Autres cas cliniques';
      if (aOther != bOther) return aOther ? 1 : -1;
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });
    return groups;
  }

  void _openSpecialty(String key) {
    _searchController.clear();
    setState(() {
      _selectedSpecialtyKey = key;
      _selectedCaseId = null;
      _query = '';
    });
  }

  void _openCase(String id) {
    setState(() => _selectedCaseId = id);
  }

  void _back() {
    if (_selectedCaseId != null) {
      setState(() => _selectedCaseId = null);
      return;
    }
    _searchController.clear();
    setState(() {
      _selectedSpecialtyKey = null;
      _query = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groupedCases();
    final selectedGroup = _selectedSpecialtyKey == null
        ? null
        : groups[_selectedSpecialtyKey];
    ClinicalCasePost? selectedCase;
    if (_selectedCaseId != null) {
      for (final post in _items) {
        if (post.id == _selectedCaseId) {
          selectedCase = post;
          break;
        }
      }
    }

    return Container(
      key: widget.verticalFeedKey,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ClinicalHeader(
            loading: _loading,
            subtitle: selectedCase != null
                ? _specialtyLabel(selectedCase)
                : selectedGroup != null
                    ? '${selectedGroup.cases.length} cas · ${selectedGroup.label}'
                    : '${_items.length} cas · ${groups.length} spécialités',
            onRefresh: () => _loadAll(),
          ),
          const SizedBox(height: 14),
          if (_loading && _items.isEmpty)
            const _LoadingCard()
          else if (_error != null && _items.isEmpty)
            _InfoCard(
              icon: Icons.cloud_off_rounded,
              title: 'Impossible de charger les cas',
              body: _error!,
              actionLabel: 'Réessayer',
              onAction: () => _loadAll(),
            )
          else if (_items.isEmpty)
            const _InfoCard(
              icon: Icons.school_outlined,
              title: 'Aucun cas publié pour le moment',
              body:
                  'Les patients validés dans Practice apparaîtront ici automatiquement dans leur spécialité avec leurs QCM pédagogiques.',
            )
          else if (selectedCase != null)
            _buildCaseView(selectedCase)
          else if (selectedGroup != null)
            _buildSpecialtyView(selectedGroup)
          else
            _buildSpecialtiesView(),
          const SizedBox(height: 14),
          const _PrivacyNote(),
        ],
      ),
    );
  }

  Widget _buildSpecialtiesView() {
    final groups = _sortedGroups();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Cas cliniques par spécialité',
          style: TextStyle(
            color: AppColors.ink,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Choisissez une spécialité pour accéder aux dossiers et aux QCM associés.',
          style: TextStyle(
            color: AppColors.inkSoft,
            fontSize: 11.5,
            height: 1.4,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 760
                ? 3
                : constraints.maxWidth >= 500
                    ? 2
                    : 1;
            if (columns == 1) {
              return Column(
                children: [
                  for (var i = 0; i < groups.length; i++) ...[
                    _SpecialtyCard(
                      group: groups[i],
                      onTap: () => _openSpecialty(groups[i].key),
                    ),
                    if (i != groups.length - 1) const SizedBox(height: 10),
                  ],
                ],
              );
            }
            const spacing = 10.0;
            final width =
                (constraints.maxWidth - (columns - 1) * spacing) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final group in groups)
                  SizedBox(
                    width: width,
                    child: _SpecialtyCard(
                      group: group,
                      onTap: () => _openSpecialty(group.key),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildSpecialtyView(_SpecialtyGroup group) {
    final query = _query.trim().toLowerCase();
    final filtered = group.cases.where((post) {
      if (query.isEmpty) return true;
      final haystack = <String>[
        post.presentation,
        post.assessment,
        post.imagingConclusion,
        post.demographicLabel,
        post.topicLabel,
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BackBar(
          title: group.label,
          subtitle:
              '${group.cases.length} cas clinique${group.cases.length > 1 ? 's' : ''}',
          onBack: _back,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _searchController,
          onChanged: (value) => setState(() => _query = value),
          style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            hintText: 'Rechercher un cas dans cette spécialité…',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Effacer',
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
            filled: true,
            fillColor: AppColors.card,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: AppColors.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: AppColors.line),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (filtered.isEmpty)
          const _InfoCard(
            icon: Icons.search_off_rounded,
            title: 'Aucun cas trouvé',
            body: 'Essayez un autre mot-clé.',
          )
        else
          for (var i = 0; i < filtered.length; i++) ...[
            _CaseListTile(
              post: filtered[i],
              number: group.cases.indexOf(filtered[i]) + 1,
              onTap: () => _openCase(filtered[i].id),
            ),
            if (i != filtered.length - 1) const SizedBox(height: 9),
          ],
      ],
    );
  }

  Widget _buildCaseView(ClinicalCasePost post) {
    final group = _groupedCases()[_specialtyKey(post)];
    final number = group == null
        ? 1
        : group.cases.indexWhere((item) => item.id == post.id) + 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BackBar(
          title: 'Cas ${number.toString().padLeft(2, '0')}',
          subtitle: _specialtyLabel(post),
          onBack: _back,
        ),
        const SizedBox(height: 12),
        _ClinicalCaseCard(post: post, number: number),
      ],
    );
  }
}

class _SpecialtyGroup {
  final String key;
  final String label;
  final List<ClinicalCasePost> cases = <ClinicalCasePost>[];

  _SpecialtyGroup({required this.key, required this.label});
}

class _ClinicalHeader extends StatelessWidget {
  final bool loading;
  final String subtitle;
  final VoidCallback onRefresh;

  const _ClinicalHeader({
    required this.loading,
    required this.subtitle,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 15, 10, 15),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.line),
        boxShadow: AppShadow.low,
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.brandSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.medical_information_rounded,
              color: AppColors.brandBright,
              size: 24,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CAS CLINIQUES · QCM',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 16.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .3,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.inkSoft,
                    fontSize: 10.5,
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
            icon: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    );
  }
}

class _SpecialtyCard extends StatelessWidget {
  final _SpecialtyGroup group;
  final VoidCallback onTap;

  const _SpecialtyCard({required this.group, required this.onTap});

  IconData _iconFor(String label) {
    final value = label.toLowerCase();
    if (value.contains('cardio')) return Icons.favorite_rounded;
    if (value.contains('neuro')) return Icons.psychology_alt_rounded;
    if (value.contains('radio') || value.contains('imagerie')) {
      return Icons.image_search_rounded;
    }
    if (value.contains('chir')) return Icons.medical_services_rounded;
    if (value.contains('gyn')) return Icons.pregnant_woman_rounded;
    if (value.contains('pédi') || value.contains('pedi')) {
      return Icons.child_care_rounded;
    }
    if (value.contains('pneumo')) return Icons.air_rounded;
    if (value.contains('gastro')) return Icons.local_hospital_rounded;
    if (value.contains('uro') ||
        value.contains('néph') ||
        value.contains('neph')) {
      return Icons.water_drop_rounded;
    }
    if (value.contains('urgence') ||
        value.contains('réa') ||
        value.contains('rea')) {
      return Icons.local_hospital_rounded;
    }
    return Icons.folder_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.line),
            boxShadow: AppShadow.low,
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.brandSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  _iconFor(group.label),
                  color: AppColors.brandBright,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 13.5,
                        height: 1.25,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${group.cases.length} cas clinique${group.cases.length > 1 ? 's' : ''}',
                      style: TextStyle(
                        color: AppColors.inkSoft,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AppColors.inkSoft),
            ],
          ),
        ),
      ),
    );
  }
}

class _CaseListTile extends StatelessWidget {
  final ClinicalCasePost post;
  final int number;
  final VoidCallback onTap;

  const _CaseListTile({
    required this.post,
    required this.number,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final answered = post.qcms.where((q) => q.answered).length;
    final total = post.qcms.length;
    final title = post.presentation.trim().isEmpty
        ? 'Cas clinique ${number.toString().padLeft(2, '0')}'
        : post.presentation.trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.brandSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  number.toString().padLeft(2, '0'),
                  style: TextStyle(
                    color: AppColors.brandBright,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 12.5,
                        height: 1.35,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _MetaText(
                          icon: Icons.person_outline_rounded,
                          text: post.demographicLabel,
                        ),
                        _MetaText(
                          icon: Icons.quiz_outlined,
                          text: total == 0
                              ? 'QCM en préparation'
                              : '$answered/$total répondus',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 7),
              Icon(Icons.chevron_right_rounded, color: AppColors.inkSoft),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaText extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MetaText({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.inkSoft),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            color: AppColors.inkSoft,
            fontSize: 9.8,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _BackBar extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onBack;

  const _BackBar({
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Retour',
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.inkSoft,
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
  final Map<String, bool> _explanationExpanded = <String, bool>{};

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
                .map((q) =>
                    '${q.id}:${q.mySelectedIndex}:${q.correction.length}')
                .join('|') !=
            oldWidget.post.qcms
                .map((q) =>
                    '${q.id}:${q.mySelectedIndex}:${q.correction.length}')
                .join('|');
    if (changed) {
      _syncQcms(resetIndex: widget.post.id != oldWidget.post.id);
    }
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

    for (final qcm in _qcms) {
      _explanationExpanded.putIfAbsent(qcm.id, () => false);
    }

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
        _explanationExpanded[qcm.id] = true;
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CaseIdentity(post: post, number: widget.number),
        const SizedBox(height: 10),
        _CaseSection(
          icon: Icons.chat_bubble_outline_rounded,
          label: 'Présentation du cas',
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
              ),
              label: Text(
                _expanded ? 'Réduire le dossier' : 'Voir le dossier complet',
              ),
            ),
          ),
        const SizedBox(height: 8),
        if (current == null)
          const _QcmPreparing()
        else ...[
          _QcmPanel(
            current: current,
            currentIndex: _currentQcm,
            total: _qcms.length,
            submitting: _submitting,
            onAnswer: _answer,
          ),
          if (answered) ...[
            const SizedBox(height: 10),
            _AnswerResult(
              correct: correct,
              expanded: _explanationExpanded[current.id] ?? false,
              correction: current.correction,
              onToggle: () => setState(() {
                _explanationExpanded[current.id] =
                    !(_explanationExpanded[current.id] ?? false);
              }),
            ),
          ],
          const SizedBox(height: 12),
          _QcmNavigation(
            qcms: _qcms,
            currentIndex: _currentQcm,
            answeredCount: answeredCount,
            correctCount: correctCount,
            onPrevious: _currentQcm > 0 ? () => _moveQcm(-1) : null,
            onNext: _currentQcm < _qcms.length - 1
                ? () => _moveQcm(1)
                : null,
            onJump: (index) => setState(() => _currentQcm = index),
          ),
        ],
      ],
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
      ].any((value) => value.trim().isNotEmpty);
}

class _CaseIdentity extends StatelessWidget {
  final ClinicalCasePost post;
  final int number;

  const _CaseIdentity({required this.post, required this.number});

  @override
  Widget build(BuildContext context) {
    final specialty = (post.specialistService ?? '').trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _Pill(
            text: 'CAS ${number.toString().padLeft(2, '0')}',
            icon: Icons.folder_open_rounded,
          ),
          if (specialty.isNotEmpty)
            _Pill(
              text: specialty,
              icon: Icons.local_hospital_outlined,
            ),
          _Pill(
            text: post.demographicLabel,
            icon: Icons.person_outline_rounded,
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final IconData icon;

  const _Pill({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.brandSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.brandBright),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: AppColors.ink,
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _QcmPanel extends StatelessWidget {
  final ClinicalCaseQcm current;
  final int currentIndex;
  final int total;
  final bool submitting;
  final ValueChanged<int> onAnswer;

  const _QcmPanel({
    required this.current,
    required this.currentIndex,
    required this.total,
    required this.submitting,
    required this.onAnswer,
  });

  @override
  Widget build(BuildContext context) {
    final answered = current.answered;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.line),
        boxShadow: AppShadow.low,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'QUESTION ${currentIndex + 1} / $total',
                style: TextStyle(
                  color: AppColors.brandBright,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .6,
                ),
              ),
              const Spacer(),
              if (current.generationSource == 'openai') ...[
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 14,
                  color: AppColors.brandBright,
                ),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  current.topicLabel,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.inkSoft,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              minHeight: 5,
              value: (currentIndex + 1) / total,
              backgroundColor: AppColors.paperAlt,
              color: AppColors.brand,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            current.question,
            style: TextStyle(
              color: AppColors.ink,
              fontSize: 15,
              height: 1.42,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          for (var index = 0; index < current.options.length; index++) ...[
            _QcmOption(
              index: index,
              label: current.options[index],
              selected: current.mySelectedIndex == index,
              showCorrection: answered,
              isCorrect: current.correctIndex == index,
              onTap: answered || submitting ? null : () => onAnswer(index),
            ),
            if (index != current.options.length - 1)
              const SizedBox(height: 8),
          ],
          if (submitting) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              minHeight: 2,
              color: AppColors.brandBright,
              backgroundColor: AppColors.line,
            ),
          ],
        ],
      ),
    );
  }
}

class _AnswerResult extends StatelessWidget {
  final bool correct;
  final bool expanded;
  final String correction;
  final VoidCallback onToggle;

  const _AnswerResult({
    required this.correct,
    required this.expanded,
    required this.correction,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final semantic = correct ? AppColors.success : AppColors.danger;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: semantic.withOpacity(.55)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(
              children: [
                Icon(
                  correct
                      ? Icons.check_circle_rounded
                      : Icons.cancel_rounded,
                  color: semantic,
                  size: 21,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    correct ? 'Bonne réponse' : 'Réponse incorrecte',
                    style: TextStyle(
                      color: semantic,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: onToggle,
                  icon: Icon(
                    Icons.auto_awesome_rounded,
                    size: 15,
                    color: AppColors.brandBright,
                  ),
                  label: Text(
                    'Explication IA',
                    style: TextStyle(
                      color: AppColors.brandBright,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Icon(
                  expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  color: AppColors.inkSoft,
                ),
              ],
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: _GuidelineCorrection(correction: correction),
            ),
          ),
        ],
      ),
    );
  }
}

class _QcmNavigation extends StatelessWidget {
  final List<ClinicalCaseQcm> qcms;
  final int currentIndex;
  final int answeredCount;
  final int correctCount;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final ValueChanged<int> onJump;

  const _QcmNavigation({
    required this.qcms,
    required this.currentIndex,
    required this.answeredCount,
    required this.correctCount,
    required this.onPrevious,
    required this.onNext,
    required this.onJump,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.paperAlt,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onPrevious,
                  icon: const Icon(Icons.chevron_left_rounded),
                  label: const Text('Précédente'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onNext,
                  icon: const Icon(Icons.chevron_right_rounded),
                  label: const Text('Suivante'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(qcms.length, (index) {
              final q = qcms[index];
              final active = index == currentIndex;
              final color = q.myIsCorrect == true
                  ? AppColors.success
                  : q.answered
                      ? AppColors.danger
                      : active
                          ? AppColors.brand
                          : AppColors.line;
              return GestureDetector(
                onTap: () => onJump(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 7),
          Text(
            '$answeredCount / ${qcms.length} répondus · $correctCount justes',
            style: TextStyle(
              color: AppColors.inkSoft,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
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
      return (
        explanation: raw,
        references: const <_GuidelineReference>[],
      );
    }

    final explanation = raw.substring(0, markerIndex).trim();
    final sourcesText = raw.substring(markerIndex + marker.length).trim();
    final references = <_GuidelineReference>[];
    for (final line in sourcesText.split('\n')) {
      final parts = line.split('|||');
      if (parts.length != 5) continue;
      final uri = Uri.tryParse(parts[4].trim());
      if (uri == null ||
          !(uri.scheme == 'https' || uri.scheme == 'http')) {
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
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: AppColors.paperAlt,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    size: 17,
                    color: AppColors.brandBright,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    'EXPLICATION IA',
                    style: TextStyle(
                      color: AppColors.brandBright,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .55,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _StructuredExplanation(text: explanation),
            ],
          ),
        ),
        if (parsed.references.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'SOURCES',
            style: TextStyle(
              color: AppColors.inkSoft,
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
              letterSpacing: .5,
            ),
          ),
          const SizedBox(height: 7),
          for (final ref in parsed.references) ...[
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(13),
                onTap: () => launchUrl(
                  ref.url,
                  mode: LaunchMode.externalApplication,
                ),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.paperAlt,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: AppColors.line),
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
                            const SizedBox(height: 3),
                            Text(
                              ref.title,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.inkSoft,
                                fontSize: 10.5,
                                height: 1.35,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.open_in_new_rounded,
                        size: 15,
                        color: AppColors.inkSoft,
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
    );
  }
}

class _StructuredExplanation extends StatelessWidget {
  final String text;

  const _StructuredExplanation({required this.text});

  bool _looksLikeHeading(String line) {
    final clean = _cleanMarkdown(line);
    final lower = clean.toLowerCase();
    return line.trim().startsWith('#') ||
        (line.trim().startsWith('**') && line.trim().endsWith('**')) ||
        lower.startsWith('pourquoi ') ||
        lower.startsWith('éléments importants') ||
        lower.startsWith('elements importants') ||
        lower.startsWith('à retenir') ||
        lower.startsWith('a retenir') ||
        lower.startsWith('point clé') ||
        lower.startsWith('point cle') ||
        lower.startsWith('réponse correcte') ||
        lower.startsWith('reponse correcte');
  }

  String _cleanMarkdown(String value) {
    var out = value.trim();
    out = out.replaceFirst(RegExp(r'^#{1,6}\s*'), '');
    if (out.startsWith('**') &&
        out.endsWith('**') &&
        out.length > 4) {
      out = out.substring(2, out.length - 2).trim();
    }
    return out.replaceAll('**', '').trim();
  }

  @override
  Widget build(BuildContext context) {
    final normalized = text.replaceAll('\r\n', '\n').trim();
    if (normalized.isEmpty) return const SizedBox.shrink();
    final lines = normalized.split('\n');
    final widgets = <Widget>[];
    final paragraph = <String>[];

    void flushParagraph() {
      if (paragraph.isEmpty) return;
      final value = paragraph.join(' ').trim();
      if (value.isNotEmpty) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Text(
              _cleanMarkdown(value),
              style: TextStyle(
                color: AppColors.ink,
                fontSize: 11.8,
                height: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      }
      paragraph.clear();
    }

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        flushParagraph();
        continue;
      }
      if (_looksLikeHeading(line)) {
        flushParagraph();
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 6),
            child: Text(
              _cleanMarkdown(line),
              style: TextStyle(
                color: AppColors.brandBright,
                fontSize: 11,
                height: 1.3,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        );
        continue;
      }
      final bullet =
          RegExp(r'^(?:[-*•]|\d+[.)])\s+(.+)$').firstMatch(line);
      if (bullet != null) {
        flushParagraph();
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppColors.brandBright,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _cleanMarkdown(bullet.group(1) ?? ''),
                    style: TextStyle(
                      color: AppColors.ink,
                      fontSize: 11.6,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        continue;
      }
      paragraph.add(line);
    }
    flushParagraph();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
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
        color: AppColors.card,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: AppColors.line),
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
                    letterSpacing: .65,
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
    Color background = AppColors.paperAlt;
    Color foreground = AppColors.ink;
    IconData? statusIcon;

    if (showCorrection && isCorrect) {
      border = AppColors.success;
      background = AppColors.success.withOpacity(.10);
      foreground = AppColors.success;
      statusIcon = Icons.check_circle_rounded;
    } else if (showCorrection && selected && !isCorrect) {
      border = AppColors.danger;
      background = AppColors.danger.withOpacity(.09);
      foreground = AppColors.danger;
      statusIcon = Icons.cancel_rounded;
    } else if (selected) {
      border = AppColors.brand;
      background = AppColors.brandSoft;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: border,
              width: selected || (showCorrection && isCorrect) ? 1.4 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: foreground.withOpacity(.10),
                  borderRadius: BorderRadius.circular(10),
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
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 12.3,
                    height: 1.42,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (statusIcon != null) ...[
                const SizedBox(width: 8),
                Icon(statusIcon, color: foreground, size: 19),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _QcmPreparing extends StatelessWidget {
  const _QcmPreparing();

  @override
  Widget build(BuildContext context) {
    return Container(
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
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

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

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    return Container(
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
          const Icon(
            Icons.shield_outlined,
            size: 17,
            color: AppColors.success,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Les cas sont automatiquement dé-identifiés avant publication. Les QCM ont un objectif pédagogique et ne constituent pas une recommandation clinique individuelle.',
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
    );
  }
}
