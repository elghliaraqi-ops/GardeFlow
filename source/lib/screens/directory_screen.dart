import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/hospitals.dart';
import '../models/app_user.dart';
import '../models/directory_contact.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';

const String _kAllHospitals = 'all';
const String _kAllCategories = 'all';

class DirectoryScreen extends StatefulWidget {
  final bool embedded;

  const DirectoryScreen({super.key, this.embedded = false});

  @override
  State<DirectoryScreen> createState() => _DirectoryScreenState();
}

class _DirectoryScreenState extends State<DirectoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String _activeCategory = _kAllCategories;
  String? _activeHospital;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _normalized(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[àáâäãå]'), 'a')
      .replaceAll(RegExp(r'[ç]'), 'c')
      .replaceAll(RegExp(r'[èéêë]'), 'e')
      .replaceAll(RegExp(r'[ìíîï]'), 'i')
      .replaceAll(RegExp(r'[òóôöõ]'), 'o')
      .replaceAll(RegExp(r'[ùúûü]'), 'u')
      .replaceAll(RegExp(r'[ÿ]'), 'y')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final sections = appState.directory;
    final isAdmin = appState.currentUser?.role == UserRole.admin;

    if (_activeCategory != _kAllCategories &&
        !sections.any((s) => s.id == _activeCategory)) {
      _activeCategory = _kAllCategories;
    }
    if (_activeHospital == null) {
      // Toujours afficher l'annuaire complet à l'ouverture.
      _activeHospital = _kAllHospitals;
    }

    final query = _normalized(_query);
    final myHospital = appState.currentUser?.hospital;
    final items = <_DirectoryItem>[];
    for (final section in sections) {
      if (_activeCategory != _kAllCategories && section.id != _activeCategory)
        continue;
      for (final contact in section.contacts) {
        if (_activeHospital != _kAllHospitals &&
            contact.hospital != _activeHospital)
          continue;
        final searchable = _normalized(
          [
            contact.name,
            contact.phone,
            contact.service ?? '',
            contact.gradeLabel ?? '',
            section.label,
            hospitalDisplayName(contact.hospital),
          ].join(' '),
        );
        if (query.isNotEmpty && !searchable.contains(query)) continue;
        items.add(_DirectoryItem(section: section, contact: contact));
      }
    }
    items.sort((a, b) {
      // L'établissement du médecin connecté est toujours prioritaire.
      final aMine = myHospital != null && a.contact.hospital == myHospital;
      final bMine = myHospital != null && b.contact.hospital == myHospital;
      if (aMine != bMine) return aMine ? -1 : 1;

      final byHospital = hospitalDisplayName(a.contact.hospital)
          .toLowerCase()
          .compareTo(hospitalDisplayName(b.contact.hospital).toLowerCase());
      if (byHospital != 0 && !aMine) return byHospital;

      final byCategory = a.section.label.toLowerCase().compareTo(
        b.section.label.toLowerCase(),
      );
      if (byCategory != 0 && _activeCategory == _kAllCategories) {
        return byCategory;
      }

      return a.contact.name.toLowerCase().compareTo(
        b.contact.name.toLowerCase(),
      );
    });

    final hospitalItems = <String>[
      if (myHospital != null && kHospitals.contains(myHospital)) myHospital,
      ...kHospitals.where((h) => h != myHospital),
    ];

    final content = Column(
      children: [
        _CategoryBar(
          sections: sections,
          activeId: _activeCategory,
          onSelect: (id) => setState(() => _activeCategory = id),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.lg,
            AppSpace.md,
            AppSpace.lg,
            AppSpace.sm,
          ),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Nom, numéro, service…',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Effacer la recherche',
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.close_rounded, size: 19),
                    ),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
          child: DropdownButtonFormField<String>(
            value: _activeHospital,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Établissement',
              prefixIcon: Icon(Icons.local_hospital_outlined, size: 19),
            ),
            items: [
              const DropdownMenuItem(
                value: _kAllHospitals,
                child: Text('Tous les établissements'),
              ),
              ...hospitalItems.map(
                (h) => DropdownMenuItem(
                  value: h,
                  child: Text(
                    hospitalDisplayName(h),
                    style: const TextStyle(fontSize: 12.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            onChanged: (v) => setState(() => _activeHospital = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, 10, AppSpace.lg, 8),
          child: Row(
            children: [
              Text(
                '${items.length} contact${items.length > 1 ? 's' : ''}',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const Spacer(),
              if (_activeCategory != _kAllCategories ||
                  _query.isNotEmpty ||
                  _activeHospital != _kAllHospitals)
                TextButton.icon(
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _query = '';
                      _activeCategory = _kAllCategories;
                      _activeHospital = _kAllHospitals;
                    });
                  },
                  icon: Icon(Icons.filter_alt_off_outlined, size: 17),
                  label: Text('Réinitialiser'),
                ),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: AppCard(
                      shadow: [],
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.person_search_rounded,
                            size: 36,
                            color: AppColors.inkFaint,
                          ),
                          SizedBox(height: AppSpace.sm),
                          Text(
                            'Aucun contact',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Aucun contact ne correspond aux filtres sélectionnés.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                    AppSpace.lg,
                    0,
                    AppSpace.lg,
                    widget.embedded ? 110 : (isAdmin ? 96 : AppSpace.lg),
                  ),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => SizedBox(height: AppSpace.sm),
                  itemBuilder: (context, i) {
                    final item = items[i];
                    return _ContactRow(
                      contact: item.contact,
                      section: item.section,
                      canManage: isAdmin && item.contact.isManual,
                      onEdit: () => _openContactEditor(
                        context,
                        appState,
                        existing: item.contact,
                      ),
                      onDelete: () =>
                          _confirmDelete(context, appState, item.contact),
                    );
                  },
                ),
        ),
      ],
    );

    if (widget.embedded) {
      return ColoredBox(
        color: AppColors.paper,
        child: Stack(
          children: [
            Positioned.fill(child: SafeArea(bottom: false, child: content)),
            if (isAdmin)
              Positioned(
                right: 18,
                bottom: 18,
                child: SafeArea(
                  top: false,
                  child: FloatingActionButton.extended(
                    heroTag: 'directory-add-contact-embedded',
                    tooltip: 'Ajouter un contact',
                    onPressed: () => _openContactEditor(context, appState),
                    backgroundColor: AppColors.brandBright,
                    foregroundColor: Colors.white,
                    elevation: 7,
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
                    label: const Text(
                      'Ajouter',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(title: GardeFlowTitle('Annuaire')),
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              heroTag: 'directory-add-contact-standalone',
              tooltip: 'Ajouter un contact',
              onPressed: () => _openContactEditor(context, appState),
              backgroundColor: AppColors.brandBright,
              foregroundColor: Colors.white,
              elevation: 7,
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
              label: const Text(
                'Ajouter',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            )
          : null,
      body: content,
    );
  }

  Future<void> _openContactEditor(
    BuildContext context,
    AppState appState, {
    DirectoryContact? existing,
  }) async {
    final currentHospital = appState.currentUser?.hospital;
    final initialHospital =
        existing?.hospital ??
        (currentHospital != null && kHospitals.contains(currentHospital)
            ? currentHospital
            : kHospitals.first);
    final draft = await showDialog<_DirectoryContactDraft>(
      context: context,
      builder: (_) => _DirectoryContactDialog(
        existing: existing,
        initialHospital: initialHospital,
      ),
    );
    if (draft == null || !context.mounted) return;

    final error = existing == null
        ? await appState.addDirectoryContact(
            categoryId: draft.categoryId,
            name: draft.name,
            phone: draft.phone,
            hospital: draft.hospital,
            service: draft.service,
          )
        : await appState.updateDirectoryContact(
            id: existing.id,
            categoryId: draft.categoryId,
            name: draft.name,
            phone: draft.phone,
            hospital: draft.hospital,
            service: draft.service,
          );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error ??
              (existing == null
                  ? 'Contact ajouté à l’annuaire.'
                  : 'Contact modifié.'),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    AppState appState,
    DirectoryContact contact,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer ce contact ?'),
        content: Text('${contact.name}\n${contact.phone}'),
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
    final error = await appState.deleteDirectoryContact(contact.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(error ?? 'Contact supprimé.')));
  }
}

class _DirectoryItem {
  final DirectorySection section;
  final DirectoryContact contact;
  const _DirectoryItem({required this.section, required this.contact});
}

class _ContactRow extends StatelessWidget {
  final DirectoryContact contact;
  final DirectorySection section;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ContactRow({
    required this.contact,
    required this.section,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final details = <String>[
      section.label,
      if ((contact.service ?? '').trim().isNotEmpty) contact.service!.trim(),
      hospitalDisplayName(contact.hospital),
    ];
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: AppRadius.mdR,
        onTap: () => launchUrl(Uri.parse('tel:${contact.phone}')),
        child: AppCard(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpace.md,
            vertical: AppSpace.sm,
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: section.color,
                child: Text(
                  contact.initials,
                  style: TextStyle(
                    color: section.textColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
              ),
              SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      contact.name,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    SizedBox(height: 2),
                    Text(
                      contact.phone,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    SizedBox(height: 2),
                    Text(
                      details.join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: AppColors.inkSoft, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.conge,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.call_rounded,
                  size: 16,
                  color: AppColors.congeText,
                ),
              ),
              if (canManage) ...[
                SizedBox(width: 2),
                PopupMenuButton<String>(
                  tooltip: 'Gérer le contact',
                  onSelected: (value) {
                    if (value == 'edit') onEdit();
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'edit',
                      child: ListTile(
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Modifier'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        leading: Icon(Icons.delete_outline),
                        title: Text('Supprimer'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryBar extends StatefulWidget {
  final List<DirectorySection> sections;
  final String activeId;
  final ValueChanged<String> onSelect;
  const _CategoryBar({
    required this.sections,
    required this.activeId,
    required this.onSelect,
  });

  @override
  State<_CategoryBar> createState() => _CategoryBarState();
}

class _CategoryBarState extends State<_CategoryBar> {
  final ScrollController _controller = ScrollController();
  bool _canScrollLeft = false;
  bool _canScrollRight = true;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncScrollState);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncScrollState());
  }

  @override
  void didUpdateWidget(covariant _CategoryBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncScrollState());
  }

  @override
  void dispose() {
    _controller.removeListener(_syncScrollState);
    _controller.dispose();
    super.dispose();
  }

  void _syncScrollState() {
    if (!mounted || !_controller.hasClients) return;
    final position = _controller.position;
    final left = position.pixels > 4;
    final right = position.pixels < position.maxScrollExtent - 4;
    if (left != _canScrollLeft || right != _canScrollRight) {
      setState(() {
        _canScrollLeft = left;
        _canScrollRight = right;
      });
    }
  }

  Future<void> _scrollBy(double delta) async {
    if (!_controller.hasClients) return;
    final target = (_controller.offset + delta).clamp(
      _controller.position.minScrollExtent,
      _controller.position.maxScrollExtent,
    );
    await _controller.animateTo(
      target.toDouble(),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.sm,
        AppSpace.lg,
        AppSpace.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Catégories',
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              Spacer(),
              Icon(Icons.swipe_rounded, size: 15, color: AppColors.inkSoft),
              SizedBox(width: 4),
              Text(
                'Faites défiler',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: AppColors.inkSoft),
              ),
            ],
          ),
          SizedBox(height: 6),
          SizedBox(
            height: 42,
            child: Row(
              children: [
                _CategoryScrollButton(
                  icon: Icons.chevron_left_rounded,
                  enabled: _canScrollLeft,
                  onTap: () => _scrollBy(-210),
                ),
                Expanded(
                  child: ListView.separated(
                    controller: _controller,
                    scrollDirection: Axis.horizontal,
                    physics: BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    itemCount: widget.sections.length + 1,
                    separatorBuilder: (_, __) => SizedBox(width: AppSpace.sm),
                    itemBuilder: (context, i) {
                      if (i == 0) {
                        final active = widget.activeId == _kAllCategories;
                        return _CategoryChip(
                          label: 'Tous',
                          active: active,
                          color: AppColors.brandDark,
                          textColor: Colors.white,
                          onTap: () => widget.onSelect(_kAllCategories),
                        );
                      }
                      final section = widget.sections[i - 1];
                      return _CategoryChip(
                        label: section.label,
                        active: section.id == widget.activeId,
                        color: section.color,
                        textColor: section.textColor,
                        onTap: () => widget.onSelect(section.id),
                      );
                    },
                  ),
                ),
                _CategoryScrollButton(
                  icon: Icons.chevron_right_rounded,
                  enabled: _canScrollRight,
                  onTap: () => _scrollBy(210),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryScrollButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  const _CategoryScrollButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: Duration(milliseconds: 160),
      opacity: enabled ? 1 : 0.18,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: AppRadius.pillR,
        child: SizedBox(
          width: 32,
          height: 42,
          child: Icon(
            icon,
            size: 22,
            color: enabled ? AppColors.ink : AppColors.inkFaint,
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;
  final Color textColor;
  final VoidCallback onTap;
  const _CategoryChip({
    required this.label,
    required this.active,
    required this.color,
    required this.textColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.pillR,
        child: AnimatedContainer(
          duration: Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? color : AppColors.paperAlt,
            borderRadius: AppRadius.pillR,
            border: Border.all(color: active ? color : AppColors.line),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: Color(0x10000000),
                      blurRadius: 5,
                      offset: Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: active ? textColor : AppColors.inkSoft,
            ),
          ),
        ),
      ),
    );
  }
}

class _DirectoryContactDraft {
  final String categoryId;
  final String name;
  final String phone;
  final String hospital;
  final String? service;

  const _DirectoryContactDraft({
    required this.categoryId,
    required this.name,
    required this.phone,
    required this.hospital,
    this.service,
  });
}

class _DirectoryContactDialog extends StatefulWidget {
  final DirectoryContact? existing;
  final String initialHospital;
  const _DirectoryContactDialog({this.existing, required this.initialHospital});

  @override
  State<_DirectoryContactDialog> createState() =>
      _DirectoryContactDialogState();
}

class _DirectoryContactDialogState extends State<_DirectoryContactDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _serviceController;
  late String _categoryId;
  late String _hospital;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _phoneController = TextEditingController(
      text: widget.existing?.phone ?? '',
    );
    _serviceController = TextEditingController(
      text: widget.existing?.service ?? '',
    );
    _categoryId =
        kManualDirectoryCategoryIds.contains(widget.existing?.categoryId)
        ? widget.existing!.categoryId
        : kDirectoryCategorySeniors;
    _hospital = widget.initialHospital;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _serviceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return AlertDialog(
      title: Text(editing ? 'Modifier le contact' : 'Ajouter un numéro'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: _categoryId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Catégorie'),
                items: kManualDirectoryCategoryIds
                    .map(
                      (id) => DropdownMenuItem(
                        value: id,
                        child: Text(directoryCategoryLabel(id)),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _categoryId = value);
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: _categoryId == kDirectoryCategoryFleet
                      ? 'Nom / libellé'
                      : 'Nom et prénom',
                  prefixIcon: const Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Numéro de téléphone',
                  hintText: 'Ex. 0612345678 ou +212…',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _hospital,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Établissement'),
                items: kHospitals
                    .map(
                      (h) => DropdownMenuItem(
                        value: h,
                        child: Text(
                          hospitalDisplayName(h),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _hospital = value);
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _serviceController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Service / précision (facultatif)',
                  prefixIcon: Icon(Icons.medical_services_outlined),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.pop(
              context,
              _DirectoryContactDraft(
                categoryId: _categoryId,
                name: _nameController.text,
                phone: _phoneController.text,
                hospital: _hospital,
                service: _serviceController.text.trim().isEmpty
                    ? null
                    : _serviceController.text.trim(),
              ),
            );
          },
          icon: Icon(editing ? Icons.save_outlined : Icons.add_call),
          label: Text(editing ? 'Enregistrer' : 'Ajouter'),
        ),
      ],
    );
  }
}
