import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/clinical_case_post.dart';
import '../services/clinical_case_service.dart';
import '../theme/app_theme.dart';

abstract final class _PracticeGame {
  static const bg = Color(0xFF071526);
  static const surface = Color(0xFF10243A);
  static const elevated = Color(0xFF17314E);
  static const purple = Color(0xFF8B6CFF);
  static const blue = Color(0xFF3295FF);
  static const gold = Color(0xFFFFD166);
  static const pink = Color(0xFFFF6FAE);
  static const mint = Color(0xFF5BE7B0);
  static const text = Color(0xFFF5F8FF);
  static const secondary = Color(0xFFB9CBE0);
  static const line = Color(0xFF244B68);
}

class ClinicalCasesSection extends StatefulWidget {
  final GlobalKey? verticalFeedKey;
  final Future<void> Function(String practiceCaseId)? onEditCase;

  const ClinicalCasesSection({
    super.key,
    this.verticalFeedKey,
    this.onEditCase,
  });

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
  bool _browseByDate = false;
  bool _newestFirst = true;
  String? _editingCaseId;

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

  String _canonicalService(String raw) {
    final value = raw
        .trim()
        .toLowerCase()
        .replaceAll('_', ' ')
        .replaceAll(RegExp(r'\s+'), ' ');

    if (value.contains('trauma') ||
        value.contains('orthop') ||
        value.contains('ostéo-artic') ||
        value.contains('osteo-artic')) {
      return 'Traumatologie / Orthopédie';
    }
    if (value.contains('chirurgie visc') ||
        value.contains('viscéral') ||
        value.contains('visceral')) {
      return 'Chirurgie Viscérale';
    }
    if (value.contains('gyn')) return 'Gynécologie';
    if (value.contains('radio') || value.contains('imagerie')) {
      return 'Imagerie Médicale';
    }
    if (value.contains('cardio')) return 'Cardiologie';
    if (value.contains('neuro')) return 'Neurologie';
    if (value.contains('pédi') || value.contains('pedi')) return 'Pédiatrie';
    if (value.contains('pneumo')) return 'Pneumologie';
    if (value.contains('gastro')) return 'Gastro-entérologie';
    if (value.contains('uro')) return 'Urologie';
    if (value.contains('néph') || value.contains('neph')) return 'Néphrologie';
    if (value.contains('réa') || value.contains('rea')) return 'Réanimation';
    if (value.contains('urgence')) return 'Urgences';

    return value
        .split(' ')
        .map((word) => word.isEmpty
            ? word
            : '${word.substring(0, 1).toUpperCase()}${word.substring(1)}')
        .join(' ');
  }

  bool _looksLikeTraumaOrtho(ClinicalCasePost post) {
    final haystack = <String>[
      post.presentation,
      post.history,
      post.clinicalExam,
      post.complementaryExams,
      post.imagingConclusion,
      post.assessment,
      post.plan,
      post.disposition,
      for (final qcm in post.qcms) qcm.question,
    ].join(' ').toLowerCase();

    const strongTerms = <String>[
      'entorse',
      'fracture',
      'luxation',
      'traumatologie',
      'orthopédie',
      'orthopedie',
      'ostéo-articulaire',
      'osteo-articulaire',
    ];
    if (strongTerms.any(haystack.contains)) return true;

    const anatomyTerms = <String>[
      'cheville',
      'malléole',
      'malleole',
      'ligament talo-fibulaire',
      'ligament tibio-fibulaire',
      'tendon d’achille',
      "tendon d'achille",
    ];
    return anatomyTerms.any(haystack.contains);
  }

  String _specialtyLabel(ClinicalCasePost post) {
    final raw = (post.specialistService ?? '').trim();
    if (raw.isNotEmpty) return _canonicalService(raw);
    if (_looksLikeTraumaOrtho(post)) return 'Traumatologie / Orthopédie';
    return 'Autres cas cliniques';
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

  void _openCase(String id) => setState(() => _selectedCaseId = id);

  Future<void> _editCase(ClinicalCasePost post) async {
    final edit = widget.onEditCase;
    final practiceCaseId = post.practiceCaseId?.trim() ?? '';
    if (edit == null || !post.canEdit || practiceCaseId.isEmpty) return;
    setState(() => _editingCaseId = post.id);
    try {
      await edit(practiceCaseId);
      await _loadAll(showLoader: false);
    } finally {
      if (mounted) setState(() => _editingCaseId = null);
    }
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
    final selectedGroup =
        _selectedSpecialtyKey == null ? null : groups[_selectedSpecialtyKey];
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
    final dated = List<ClinicalCasePost>.from(_items)
      ..sort((a, b) {
        final ad = a.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bd = b.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return _newestFirst ? bd.compareTo(ad) : ad.compareTo(bd);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _browseByDate
              ? 'Cas cliniques par date de publication'
              : 'Cas cliniques par spécialité',
          style: const TextStyle(
            color: _PracticeGame.text,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _browseByDate
              ? 'Parcourez tous les cas selon leur date de publication.'
              : 'Choisissez une spécialité pour accéder aux dossiers et aux QCM associés.',
          style: const TextStyle(
            color: _PracticeGame.secondary,
            fontSize: 11.5,
            height: 1.4,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _BrowseToggle(
                icon: Icons.folder_copy_outlined,
                label: 'Spécialités',
                selected: !_browseByDate,
                onTap: () => setState(() => _browseByDate = false),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _BrowseToggle(
                icon: Icons.calendar_month_rounded,
                label: 'Publication',
                selected: _browseByDate,
                onTap: () => setState(() => _browseByDate = true),
              ),
            ),
          ],
        ),
        if (_browseByDate) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: _BrowseToggle(
              icon: _newestFirst
                  ? Icons.arrow_downward_rounded
                  : Icons.arrow_upward_rounded,
              label: _newestFirst ? 'Plus récents' : 'Plus anciens',
              selected: true,
              compact: true,
              onTap: () => setState(() => _newestFirst = !_newestFirst),
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (_browseByDate)
          for (var i = 0; i < dated.length; i++) ...[
            _CaseListTile(
              post: dated[i],
              number: i + 1,
              onTap: () => _openCase(dated[i].id),
            ),
            if (i != dated.length - 1) const SizedBox(height: 9),
          ]
        else
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
          style: const TextStyle(
            color: _PracticeGame.text,
            fontWeight: FontWeight.w700,
          ),
          cursorColor: _PracticeGame.gold,
          decoration: InputDecoration(
            hintText: 'Rechercher un cas dans cette spécialité…',
            hintStyle: const TextStyle(color: _PracticeGame.secondary),
            prefixIcon:
                const Icon(Icons.search_rounded, color: _PracticeGame.purple),
            suffixIcon: _query.isEmpty
                ? null
                : Padding(
                    padding: const EdgeInsets.all(6),
                    child: _GamingIconButton(
                      tooltip: 'Effacer',
                      icon: Icons.close_rounded,
                      compact: true,
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    ),
                  ),
            filled: true,
            fillColor: _PracticeGame.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: _PracticeGame.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: _PracticeGame.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide:
                  const BorderSide(color: _PracticeGame.purple, width: 1.4),
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
        if (post.canEdit &&
            widget.onEditCase != null &&
            (post.practiceCaseId?.trim().isNotEmpty ?? false)) ...[
          Align(
            alignment: Alignment.centerRight,
            child: _GamingTextButton(
              icon: Icons.edit_note_rounded,
              label: _editingCaseId == post.id
                  ? 'Ouverture…'
                  : 'Modifier ce cas clinique',
              onPressed:
                  _editingCaseId == null ? () => _editCase(post) : null,
            ),
          ),
          const SizedBox(height: 8),
        ],
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
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _PracticeGame.purple.withOpacity(.26),
            _PracticeGame.surface,
            _PracticeGame.blue.withOpacity(.18),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _PracticeGame.purple.withOpacity(.42)),
        boxShadow: [
          BoxShadow(
            color: _PracticeGame.purple.withOpacity(.16),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _PracticeGame.purple.withOpacity(.30),
                  _PracticeGame.blue.withOpacity(.20),
                ],
              ),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: _PracticeGame.gold.withOpacity(.35)),
            ),
            child: const Icon(
              Icons.medical_information_rounded,
              color: _PracticeGame.gold,
              size: 25,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'CAS CLINIQUES · QCM',
                  style: TextStyle(
                    color: _PracticeGame.text,
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
                  style: const TextStyle(
                    color: _PracticeGame.secondary,
                    fontSize: 10.5,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          _GamingIconButton(
            tooltip: 'Actualiser',
            icon: Icons.refresh_rounded,
            loading: loading,
            onPressed: loading ? null : onRefresh,
          ),
        ],
      ),
    );
  }
}

class _GamingIconButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool loading;
  final bool compact;

  const _GamingIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.loading = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final size = compact ? 34.0 : 42.0;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(compact ? 11 : 14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: onPressed == null
                  ? _PracticeGame.surface.withOpacity(.55)
                  : _PracticeGame.elevated,
              borderRadius: BorderRadius.circular(compact ? 11 : 14),
              border: Border.all(
                color: onPressed == null
                    ? _PracticeGame.line.withOpacity(.55)
                    : _PracticeGame.purple.withOpacity(.55),
              ),
              boxShadow: onPressed == null
                  ? null
                  : [
                      BoxShadow(
                        color: _PracticeGame.purple.withOpacity(.10),
                        blurRadius: 12,
                        offset: const Offset(0, 5),
                      ),
                    ],
            ),
            child: loading
                ? const SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _PracticeGame.gold,
                    ),
                  )
                : Icon(
                    icon,
                    size: compact ? 18 : 21,
                    color: onPressed == null
                        ? _PracticeGame.secondary.withOpacity(.45)
                        : _PracticeGame.gold,
                  ),
          ),
        ),
      ),
    );
  }
}

class _BrowseToggle extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  const _BrowseToggle({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 12,
              vertical: compact ? 8 : 10,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? _PracticeGame.purple.withOpacity(.22)
                  : _PracticeGame.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? _PracticeGame.purple : _PracticeGame.line,
              ),
            ),
            child: Row(
              mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 16,
                    color: selected
                        ? _PracticeGame.gold
                        : _PracticeGame.secondary),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: selected
                        ? _PracticeGame.text
                        : _PracticeGame.secondary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _SpecialtyCard extends StatelessWidget {
  final _SpecialtyGroup group;
  final VoidCallback onTap;

  const _SpecialtyCard({required this.group, required this.onTap});

  IconData _iconFor(String label) {
    final value = label.toLowerCase();
    if (value.contains('trauma') || value.contains('orthop')) {
      return Icons.healing_rounded;
    }
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
    if (value.contains('uro') || value.contains('néph') || value.contains('neph')) {
      return Icons.water_drop_rounded;
    }
    if (value.contains('urgence') || value.contains('réa') || value.contains('rea')) {
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
        borderRadius: BorderRadius.circular(22),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _PracticeGame.purple.withOpacity(.22),
                _PracticeGame.surface,
                _PracticeGame.blue.withOpacity(.12),
              ],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _PracticeGame.purple.withOpacity(.36)),
            boxShadow: [
              BoxShadow(
                color: _PracticeGame.purple.withOpacity(.11),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: _PracticeGame.elevated,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _PracticeGame.gold.withOpacity(.28)),
                ),
                child: Icon(
                  _iconFor(group.label),
                  color: _PracticeGame.gold,
                  size: 22,
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
                      style: const TextStyle(
                        color: _PracticeGame.text,
                        fontSize: 13.5,
                        height: 1.25,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${group.cases.length} cas clinique${group.cases.length > 1 ? 's' : ''}',
                      style: const TextStyle(
                        color: _PracticeGame.secondary,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _PracticeGame.purple.withOpacity(.17),
                  shape: BoxShape.circle,
                  border: Border.all(color: _PracticeGame.purple.withOpacity(.30)),
                ),
                child: const Icon(
                  Icons.chevron_right_rounded,
                  color: _PracticeGame.gold,
                ),
              ),
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
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _PracticeGame.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _PracticeGame.line),
            boxShadow: [
              BoxShadow(
                color: _PracticeGame.blue.withOpacity(.07),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _PracticeGame.purple.withOpacity(.18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _PracticeGame.purple.withOpacity(.30)),
                ),
                child: Text(
                  number.toString().padLeft(2, '0'),
                  style: const TextStyle(
                    color: _PracticeGame.gold,
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
                      style: const TextStyle(
                        color: _PracticeGame.text,
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
                        if (post.publishedAt != null)
                          _MetaText(
                            icon: Icons.calendar_today_rounded,
                            text: DateFormat('dd/MM/yyyy')
                                .format(post.publishedAt!.toLocal()),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 7),
              const Icon(
                Icons.chevron_right_rounded,
                color: _PracticeGame.gold,
              ),
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
        Icon(icon, size: 13, color: _PracticeGame.secondary),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            color: _PracticeGame.secondary,
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
        _GamingIconButton(
          tooltip: 'Retour',
          icon: Icons.arrow_back_rounded,
          onPressed: onBack,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _PracticeGame.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _PracticeGame.secondary,
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
  bool _resetting = false;
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
                .map((q) => '${q.id}:${q.mySelectedIndex}:${q.correction.length}')
                .join('|') !=
            oldWidget.post.qcms
                .map((q) => '${q.id}:${q.mySelectedIndex}:${q.correction.length}')
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

  Future<void> _redoQcm() async {
    if (_qcms.isEmpty || _submitting || _resetting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Refaire le QCM ?'),
        content: const Text(
          'Vos réponses affichées seront réinitialisées pour ce cas. '
          'Votre historique et le classement officiel restent basés sur '
          'votre première tentative.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.replay_rounded),
            label: const Text('Refaire'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _resetting = true);
    try {
      await ClinicalCaseService.instance.resetMyQcmAnswers(
        postId: widget.post.id,
      );
      if (!mounted) return;
      setState(() {
        _qcms = _qcms.map((qcm) => qcm.copyWith(clearAnswer: true)).toList();
        _currentQcm = 0;
        _explanationExpanded.updateAll((_, __) => false);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'QCM réinitialisé. Le classement conserve la première tentative.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de réinitialiser ce QCM.')),
      );
    } finally {
      if (mounted) setState(() => _resetting = false);
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
            child: _GamingTextButton(
              icon: _expanded
                  ? Icons.expand_less_rounded
                  : Icons.expand_more_rounded,
              label: _expanded ? 'Réduire le dossier' : 'Voir le dossier complet',
              onPressed: () => setState(() => _expanded = !_expanded),
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
            submitting: _submitting || _resetting,
            onAnswer: _answer,
          ),
          if (answered) ...[
            const SizedBox(height: 10),
            _AnswerFeedback(
              correct: correct,
              expanded: _explanationExpanded[current.id] ?? false,
              correction: current.correction,
              onToggle: () => setState(() {
                _explanationExpanded[current.id] =
                    !(_explanationExpanded[current.id] ?? false);
              }),
            ),
          ],
          const SizedBox(height: 10),
          _QcmNavigation(
            qcms: _qcms,
            currentIndex: _currentQcm,
            onPrevious: _currentQcm > 0 ? () => _moveQcm(-1) : null,
            onNext: _currentQcm < _qcms.length - 1 ? () => _moveQcm(1) : null,
            onSelect: (index) => setState(() => _currentQcm = index),
          ),
          const SizedBox(height: 7),
          Center(
            child: Text(
              '$answeredCount / ${_qcms.length} répondus · $correctCount justes',
              style: const TextStyle(
                color: _PracticeGame.secondary,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (answeredCount > 0) ...[
            const SizedBox(height: 5),
            Center(
              child: _GamingTextButton(
                icon: Icons.replay_rounded,
                label: _resetting ? 'Réinitialisation…' : 'Refaire le QCM',
                onPressed: _resetting ? null : _redoQcm,
              ),
            ),
          ],
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

class _GamingTextButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const _GamingTextButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: _PracticeGame.purple.withOpacity(.13),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _PracticeGame.purple.withOpacity(.32)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: _PracticeGame.gold),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: const TextStyle(
                    color: _PracticeGame.text,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CaseIdentity extends StatelessWidget {
  final ClinicalCasePost post;
  final int number;

  const _CaseIdentity({required this.post, required this.number});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _PracticeGame.purple.withOpacity(.20),
            _PracticeGame.surface,
            _PracticeGame.blue.withOpacity(.12),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _PracticeGame.purple.withOpacity(.34)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: _PracticeGame.purple.withOpacity(.16),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: _PracticeGame.purple.withOpacity(.30)),
            ),
            child: Text(
              'CAS #${number.toString().padLeft(2, '0')}',
              style: const TextStyle(
                color: _PracticeGame.gold,
                fontSize: 9.5,
                fontWeight: FontWeight.w900,
                letterSpacing: .7,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              post.demographicLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _PracticeGame.secondary,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: _PracticeGame.elevated,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: _PracticeGame.line),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.quiz_rounded, size: 12, color: _PracticeGame.mint),
                SizedBox(width: 4),
                Text(
                  '5 QCM',
                  style: TextStyle(
                    color: _PracticeGame.text,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
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
        color: _PracticeGame.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _PracticeGame.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _PracticeGame.purple.withOpacity(.15),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 17, color: _PracticeGame.mint),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    color: _PracticeGame.gold,
                    fontSize: 8.8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .68,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value.trim().isEmpty ? 'Non renseigné' : value.trim(),
                  style: const TextStyle(
                    color: _PracticeGame.text,
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

class _QcmPreparing extends StatelessWidget {
  const _QcmPreparing();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _PracticeGame.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _PracticeGame.line),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: _PracticeGame.gold,
            ),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Les QCM de ce cas sont en cours de préparation…',
              style: TextStyle(
                color: _PracticeGame.secondary,
                fontWeight: FontWeight.w700,
              ),
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
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _PracticeGame.purple.withOpacity(.32),
            _PracticeGame.elevated,
            _PracticeGame.blue.withOpacity(.18),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _PracticeGame.purple.withOpacity(.50)),
        boxShadow: [
          BoxShadow(
            color: _PracticeGame.purple.withOpacity(.14),
            blurRadius: 22,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sports_esports_rounded,
                  color: _PracticeGame.gold, size: 19),
              const SizedBox(width: 7),
              Text(
                'DÉFI ${currentIndex + 1} / $total',
                style: const TextStyle(
                  color: _PracticeGame.gold,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .7,
                ),
              ),
              const Spacer(),
              if (current.generationSource == 'openai') ...[
                const Icon(Icons.auto_awesome_rounded,
                    color: _PracticeGame.purple, size: 13),
                const SizedBox(width: 4),
              ],
              Text(
                current.topicLabel,
                style: const TextStyle(
                  color: _PracticeGame.secondary,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : (currentIndex + 1) / total,
              minHeight: 5,
              backgroundColor: _PracticeGame.line,
              color: _PracticeGame.gold,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(.13),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withOpacity(.10)),
            ),
            child: Text(
              current.question,
              style: const TextStyle(
                color: _PracticeGame.text,
                fontSize: 15.2,
                height: 1.43,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < current.options.length; index++) ...[
            _QcmOption(
              index: index,
              label: current.options[index],
              selected: current.mySelectedIndex == index,
              showCorrection: answered,
              isCorrect: current.correctIndex == index,
              onTap: answered || submitting ? null : () => onAnswer(index),
            ),
            if (index != current.options.length - 1) const SizedBox(height: 7),
          ],
          if (submitting) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(
              minHeight: 2,
              color: _PracticeGame.gold,
              backgroundColor: _PracticeGame.line,
            ),
          ],
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
    Color border = _PracticeGame.line;
    Color background = _PracticeGame.surface;
    Color foreground = _PracticeGame.text;
    if (showCorrection && isCorrect) {
      border = AppColors.success;
      background = AppColors.success.withOpacity(.10);
      foreground = AppColors.success;
    } else if (showCorrection && selected && !isCorrect) {
      border = AppColors.danger;
      background = AppColors.danger.withOpacity(.10);
      foreground = AppColors.danger;
    } else if (selected) {
      border = _PracticeGame.purple;
      background = _PracticeGame.purple.withOpacity(.20);
      foreground = _PracticeGame.gold;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: border,
              width: selected || (showCorrection && isCorrect) ? 1.35 : 1,
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
                child: Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 12.3,
                      height: 1.43,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              if (showCorrection && isCorrect)
                const Padding(
                  padding: EdgeInsets.only(left: 7, top: 4),
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

class _AnswerFeedback extends StatelessWidget {
  final bool correct;
  final bool expanded;
  final String correction;
  final VoidCallback onToggle;

  const _AnswerFeedback({
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
        gradient: LinearGradient(
          colors: [
            semantic.withOpacity(.14),
            _PracticeGame.surface,
            _PracticeGame.purple.withOpacity(.12),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: semantic.withOpacity(.48)),
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(
                      correct ? Icons.check_circle_rounded : Icons.cancel_rounded,
                      color: semantic,
                      size: 20,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      correct ? 'Bonne réponse' : 'À revoir',
                      style: TextStyle(
                        color: semantic,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    const Icon(Icons.auto_awesome_rounded,
                        color: _PracticeGame.gold, size: 15),
                    const SizedBox(width: 5),
                    const Text(
                      'EXPLICATION IA',
                      style: TextStyle(
                        color: _PracticeGame.gold,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .5,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Icon(
                      expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: _PracticeGame.gold,
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
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
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final ValueChanged<int> onSelect;

  const _QcmNavigation({
    required this.qcms,
    required this.currentIndex,
    required this.onPrevious,
    required this.onNext,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _GamingIconButton(
          tooltip: 'QCM précédent',
          icon: Icons.chevron_left_rounded,
          onPressed: onPrevious,
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(qcms.length, (index) {
              final q = qcms[index];
              final active = index == currentIndex;
              final Color color = q.myIsCorrect == true
                  ? AppColors.success
                  : q.answered
                      ? AppColors.danger
                      : active
                          ? _PracticeGame.gold
                          : _PracticeGame.purple;
              return GestureDetector(
                onTap: () => onSelect(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 22 : 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(99),
                    boxShadow: active
                        ? [
                            BoxShadow(
                              color: color.withOpacity(.24),
                              blurRadius: 8,
                            ),
                          ]
                        : null,
                  ),
                ),
              );
            }),
          ),
        ),
        _GamingIconButton(
          tooltip: 'QCM suivant',
          icon: Icons.chevron_right_rounded,
          onPressed: onNext,
        ),
      ],
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

  List<Widget> _explanationWidgets(String explanation) {
    final lines = explanation
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      return const [
        Text(
          'Explication pédagogique en préparation.',
          style: TextStyle(
            color: _PracticeGame.secondary,
            fontSize: 11.8,
            height: 1.48,
            fontWeight: FontWeight.w600,
          ),
        ),
      ];
    }

    return [
      for (var i = 0; i < lines.length; i++) ...[
        if (RegExp(r'^(#{1,3}\s+|[A-ZÀ-Ü][A-ZÀ-Ü0-9 /-]{4,}:?$)')
            .hasMatch(lines[i]))
          Text(
            lines[i].replaceFirst(RegExp(r'^#{1,3}\s+'), ''),
            style: const TextStyle(
              color: _PracticeGame.gold,
              fontSize: 11.5,
              height: 1.35,
              fontWeight: FontWeight.w900,
            ),
          )
        else if (RegExp(r'^[-•]\s+').hasMatch(lines[i]))
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Icon(Icons.circle, size: 5, color: _PracticeGame.mint),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  lines[i].replaceFirst(RegExp(r'^[-•]\s+'), ''),
                  style: const TextStyle(
                    color: _PracticeGame.text,
                    fontSize: 11.8,
                    height: 1.48,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          )
        else
          Text(
            lines[i],
            style: const TextStyle(
              color: _PracticeGame.text,
              fontSize: 11.8,
              height: 1.48,
              fontWeight: FontWeight.w600,
            ),
          ),
        if (i != lines.length - 1) const SizedBox(height: 7),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final parsed = _parse();
    final explanation = parsed.explanation.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _PracticeGame.elevated.withOpacity(.78),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: _PracticeGame.purple.withOpacity(.24)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _explanationWidgets(explanation),
          ),
        ),
        if (parsed.references.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Row(
            children: [
              Icon(Icons.menu_book_rounded,
                  size: 15, color: _PracticeGame.mint),
              SizedBox(width: 6),
              Text(
                'SOURCES DU COURS',
                style: TextStyle(
                  color: _PracticeGame.gold,
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
                borderRadius: BorderRadius.circular(13),
                onTap: () =>
                    launchUrl(ref.url, mode: LaunchMode.externalApplication),
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  decoration: BoxDecoration(
                    color: _PracticeGame.surface,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                        color: _PracticeGame.purple.withOpacity(.28)),
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
                                color: _PracticeGame.gold,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              ref.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _PracticeGame.secondary,
                                fontSize: 10.5,
                                height: 1.3,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 7),
                      const Icon(Icons.open_in_new_rounded,
                          size: 15, color: _PracticeGame.gold),
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

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _PracticeGame.surface.withOpacity(.88),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _PracticeGame.line),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, size: 17, color: _PracticeGame.mint),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Les cas sont automatiquement dé-identifiés avant publication. Les QCM ont un objectif pédagogique et ne constituent pas une recommandation clinique individuelle.',
              style: TextStyle(
                color: _PracticeGame.secondary,
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

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 150,
      width: double.infinity,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _PracticeGame.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _PracticeGame.line),
      ),
      child: const CircularProgressIndicator(color: _PracticeGame.gold),
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
        color: _PracticeGame.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _PracticeGame.line),
      ),
      child: Column(
        children: [
          Icon(icon, color: _PracticeGame.gold, size: 30),
          const SizedBox(height: 9),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _PracticeGame.text,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _PracticeGame.secondary,
              fontSize: 11,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 9),
            _GamingTextButton(
              icon: Icons.refresh_rounded,
              label: actionLabel!,
              onPressed: onAction,
            ),
          ],
        ],
      ),
    );
  }
}
