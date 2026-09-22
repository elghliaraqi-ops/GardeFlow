import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../ui/components.dart';
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

    if (_activeCategory != _kAllCategories && !sections.any((s) => s.id == _activeCategory)) {
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
      if (_activeCategory != _kAllCategories && section.id != _activeCategory) continue;
      for (final contact in section.contacts) {
        if (_activeHospital != _kAllHospitals && contact.hospital != _activeHospital) continue;
        final searchable = _normalized([
          contact.name,
          contact.phone,
          contact.service ?? '',
          contact.gradeLabel ?? '',
          section.label,
          hospitalDisplayName(contact.hospital),
        ].join(' '));
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
          .compareTo(
            hospitalDisplayName(b.contact.hospital).toLowerCase(),
          );
      if (byHospital != 0 && !aMine) return byHospital;

      final byCategory = a.section.label
          .toLowerCase()
          .compareTo(b.section.label.toLowerCase());
      if (byCategory != 0 && _activeCategory == _kAllCategories) {
        return byCategory;
      }

      return a.contact.name
          .toLowerCase()
          .compareTo(b.contact.name.toLowerCase());
    });

    final hospitalItems = <String>[
      if (myHospital != null && kHospitals.contains(myHospital)) myHospital,
      ...kHospitals.where((h) => h != myHospital),
    ];

    final content = NestedScrollView(
      headerSliverBuilder: (context, scrolled) => [SliverToBoxAdapter(child: Column(
      children: [

        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.sm),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: 'Rechercher dans l’annuaire',
              hintText: 'Service, médecin ou extension',
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
        _CategoryBar(
          sections: sections,
          activeId: _activeCategory,
          onSelect: (id) => setState(() => _activeCategory = id),
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
              const DropdownMenuItem(value: _kAllHospitals, child: Text('Tous les établissements')),
              ...hospitalItems.map((h) => DropdownMenuItem(
                    value: h,
                    child: Text(
                      hospitalDisplayName(h),
                      style: const TextStyle(fontSize: 12.5),
                      overflow: TextOverflow.ellipsis,
                    ),
                  )),
            ],
            onChanged: (v) => setState(() => _activeHospital = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, 10, AppSpace.lg, 8),
          child: Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('${items.length} contact${items.length > 1 ? 's' : ''}', style: Theme.of(context).textTheme.labelMedium),
              if (_activeCategory != _kAllCategories || _query.isNotEmpty || _activeHospital != _kAllHospitals)
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
      ],
      ))],
      body: items.isEmpty
              ? SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: AppCard(
                      shadow: [],
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.person_search_rounded, size: 36, color: AppColors.inkFaint),
                        SizedBox(height: AppSpace.sm),
                        Text('Aucun contact', style: Theme.of(context).textTheme.titleMedium),
                        SizedBox(height: 3),
                        Text(
                          'Aucun contact ne correspond aux filtres sélectionnés.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ]),
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
                      onEdit: () => _openContactEditor(context, appState, existing: item.contact),
                      onDelete: () => _confirmDelete(context, appState, item.contact),
                    );
                  },
                ),
    );

    if (widget.embedded) {
      return ColoredBox(
        color: AppColors.paper,
        child: Stack(
          children: [
            Positioned.fill(
              child: SafeArea(
                bottom: false,
                child: content,
              ),
            ),
            if (isAdmin)
              Positioned(
                right: 18,
                bottom: 18,
                child: SafeArea(
                  top: false,
                  child: FloatingActionButton(
                    heroTag: 'directory-add-contact-embedded',
                    tooltip: 'Ajouter un contact',
                    onPressed: () => _openContactEditor(context, appState),
                    backgroundColor: AppColors.brandDark,
                    foregroundColor: Colors.white,
                    elevation: 5,
                    child: Icon(Icons.person_add_alt_1_rounded),
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
          ? FloatingActionButton(
              heroTag: 'directory-add-contact-standalone',
              tooltip: 'Ajouter un contact',
              onPressed: () => _openContactEditor(context, appState),
              backgroundColor: AppColors.brandDark,
              foregroundColor: Colors.white,
              child: Icon(Icons.person_add_alt_1_rounded),
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
    final initialHospital = existing?.hospital ??
        (currentHospital != null && kHospitals.contains(currentHospital) ? currentHospital : kHospitals.first);
    final draft = await showDialog<_DirectoryContactDraft>(
      context: context,
      builder: (_) => _DirectoryContactDialog(existing: existing, initialHospital: initialHospital),
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(error ?? (existing == null ? 'Contact ajouté à l’annuaire.' : 'Contact modifié.')),
    ));
  }

  Future<void> _confirmDelete(BuildContext context, AppState appState, DirectoryContact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('Supprimer ce contact ?'),
        content: Text('${contact.name}\n${contact.phone}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Annuler')),
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error ?? 'Contact supprimé.')));
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
  final VoidCallback onEdit, onDelete;
  const _ContactRow({required this.contact, required this.section, required this.canManage, required this.onEdit, required this.onDelete});
  @override
  Widget build(BuildContext context) {
    final extension = contact.categoryId == kDirectoryCategoryExtensions || RegExp(r'^\d{2,6}$').hasMatch(contact.phone.trim());
    Future<void> action() async {
      if (extension) {
        await Clipboard.setData(ClipboardData(text: contact.phone));
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Extension ${contact.phone} copiée · à composer sur le réseau de ${hospitalDisplayName(contact.hospital)}.')));
      } else {
        final ok = await launchUrl(Uri(scheme: 'tel', path: contact.phone));
        if (!ok && context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impossible d’ouvrir le téléphone.')));
      }
    }
    return Column(children: [
      DoctorTile(name: contact.name,
        subtitle: '${contact.service ?? section.label} · ${hospitalDisplayName(contact.hospital)}',
        onTap: action,
        trailing: PopupMenuButton<String>(
          tooltip: 'Actions pour ${contact.name}',
          onSelected: (value) { if (value == 'contact') action(); if (value == 'edit') onEdit(); if (value == 'delete') onDelete(); },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'contact', child: Text(extension ? 'Copier l’extension' : 'Appeler')),
            if (canManage) const PopupMenuItem(value: 'edit', child: Text('Modifier')),
            if (canManage) const PopupMenuItem(value: 'delete', child: Text('Supprimer')),
          ],
        )),
      Padding(padding: const EdgeInsets.only(left: 68, bottom: 8), child: Align(alignment: Alignment.centerLeft,
        child: TextButton.icon(onPressed: action,
          icon: Icon(extension ? Icons.content_copy_rounded : Icons.phone_outlined),
          label: Text(extension ? 'Extension ${contact.phone}' : contact.phone)))),
      const Divider(indent: 68),
    ]);
  }
}

class _CategoryBar extends StatelessWidget {
  final List<DirectorySection> sections;
  final String activeId;
  final ValueChanged<String> onSelect;
  const _CategoryBar({required this.sections, required this.activeId, required this.onSelect});
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Row(children: [
      Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: const Text('Tous'), selected: activeId == _kAllCategories, onSelected: (_) => onSelect(_kAllCategories))),
      for (final section in sections) Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(
        label: Text(section.label), selected: activeId == section.id, onSelected: (_) => onSelect(section.id))),
    ]),
  );
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
  State<_DirectoryContactDialog> createState() => _DirectoryContactDialogState();
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
    _phoneController = TextEditingController(text: widget.existing?.phone ?? '');
    _serviceController = TextEditingController(text: widget.existing?.service ?? '');
    _categoryId = kManualDirectoryCategoryIds.contains(widget.existing?.categoryId)
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
      scrollable: true,
      title: Text(editing ? 'Modifier le contact' : 'Ajouter un numéro'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 480,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              value: _categoryId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Catégorie'),
              items: kManualDirectoryCategoryIds
                  .map((id) => DropdownMenuItem(value: id, child: Text(directoryCategoryLabel(id))))
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
                labelText: _categoryId == kDirectoryCategoryFleet ? 'Nom / libellé' : 'Nom et prénom',
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
                  .map((h) => DropdownMenuItem(value: h, child: Text(hospitalDisplayName(h), overflow: TextOverflow.ellipsis)))
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
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton.icon(
          onPressed: () {
            Navigator.pop(
              context,
              _DirectoryContactDraft(
                categoryId: _categoryId,
                name: _nameController.text,
                phone: _phoneController.text,
                hospital: _hospital,
                service: _serviceController.text.trim().isEmpty ? null : _serviceController.text.trim(),
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
