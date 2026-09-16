import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:pdfrx/pdfrx.dart';

import '../data/hospitals.dart';
import '../models/app_user.dart';
import '../models/shared_resource.dart';
import '../services/official_roster_import_service.dart';
import '../services/supabase_backend_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';

class OfficialPlanningScreen extends StatefulWidget {
  const OfficialPlanningScreen({super.key});

  @override
  State<OfficialPlanningScreen> createState() => _OfficialPlanningScreenState();
}

class _OfficialPlanningScreenState extends State<OfficialPlanningScreen> {
  final _backend = SupabaseBackendService.instance;
  List<SharedResource> _resources = const [];
  bool _loading = true;
  String? _busySlot;
  String? _error;
  final Set<String> _autoImportingSlots = <String>{};
  final Map<String, String> _importStatus = <String, String>{};

  static const _slots = <_OfficialSlot>[
    _OfficialSlot('hm6_bouskoura', 'HUIM6 de Bouskoura', 'HUIM6 de Bouskoura', kHospitalBouskoura, Icons.local_hospital_rounded),
    _OfficialSlot('hm6_rabat', 'HUIM6 de Rabat', 'HUIM6 de Rabat', kHospitalRabat, Icons.account_balance_rounded),
    _OfficialSlot('hck_casa', 'HUICK de Casa', 'HUICK de Casa', kHospitalCasa, Icons.apartment_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!_backend.enabled || _backend.client.auth.currentUser == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Connexion Supabase requise pour consulter les plannings officiels.';
        });
      }
      return;
    }
    try {
      final rows = await _backend.fetchOfficialPlanningPdfs();
      if (!mounted) return;
      setState(() {
        _resources = rows;
        _loading = false;
        _error = null;
      });
      final isAdmin = context.read<AppState>().currentUser?.role == UserRole.admin;
      if (isAdmin) unawaited(_autoImportExisting(rows));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Impossible de charger les plannings officiels : $e';
      });
    }
  }

  SharedResource? _resourceFor(String slot) {
    for (final r in _resources) {
      if (r.slot == slot) return r;
    }
    return null;
  }

  _OfficialSlot? _slotForId(String? id) {
    if (id == null) return null;
    for (final slot in _slots) {
      if (slot.id == id) return slot;
    }
    return null;
  }

  Future<void> _autoImportExisting(List<SharedResource> resources) async {
    for (final resource in resources) {
      if (!mounted) return;
      if (resource.slot == null) continue;
      final slot = _slotForId(resource.slot);
      if (slot == null || _autoImportingSlots.contains(slot.id) || _busySlot == slot.id) continue;
      try {
        final current = await _backend.officialRosterImportIsCurrent(resource);
        if (current) {
          if (mounted) setState(() => _importStatus[slot.id] = 'Gardes Urgences synchronisées');
          continue;
        }
        await _processOfficialRoster(slot, resource);
      } catch (e) {
        if (mounted) {
          setState(() => _importStatus[slot.id] = 'Transposition à réessayer');
          debugPrint('Import automatique ${slot.id} impossible: $e');
        }
      }
    }
  }

  Future<Map<String, dynamic>> _processOfficialRoster(
    _OfficialSlot slot,
    SharedResource resource, {
    Uint8List? bytes,
  }) async {
    if (_autoImportingSlots.contains(slot.id)) return const <String, dynamic>{};
    if (mounted) {
      setState(() {
        _autoImportingSlots.add(slot.id);
        _importStatus[slot.id] = 'Lecture du planning Urgences…';
      });
    }
    try {
      final sourceBytes = bytes ?? await _backend.downloadSharedResource(resource.storagePath);
      final profiles = await _backend.fetchVisibleProfiles();
      final parsed = await OfficialRosterImportService.parse(
        bytes: sourceBytes,
        displayName: resource.displayName,
        hospital: slot.hospital,
        profiles: profiles,
        resourceUpdatedAt: resource.updatedAt,
      );
      if (parsed.detectedRows == 0) {
        throw StateError('Aucune ligne de garde 08h-20h / 20h-08h reconnue dans ce PDF.');
      }
      if (parsed.assignments.isEmpty) {
        throw StateError('Le tableau est lisible mais aucun nom ne correspond aux médecins inscrits de ${slot.title}.');
      }
      final result = await _backend.importOfficialEmergencyRoster(
        resource: resource,
        assignments: parsed.assignments.map((a) => a.toJson()).toList(growable: false),
        unmatchedCells: parsed.unmatchedCells,
      );
      if (mounted) {
        final inserted = (result['inserted'] as num?)?.toInt() ?? 0;
        final updated = (result['updated'] as num?)?.toInt() ?? 0;
        final skippedManual = (result['skipped_manual'] as num?)?.toInt() ?? 0;
        final skippedApproved = (result['skipped_approved'] as num?)?.toInt() ?? 0;
        final imported = inserted + updated;
        final suffix = <String>[
          if (parsed.unmatchedCells.isNotEmpty) '${parsed.unmatchedCells.length} cellule(s) sans médecin reconnu',
          if (skippedManual > 0) '$skippedManual garde(s) déjà modifiée(s) par le médecin',
          if (skippedApproved > 0) '$skippedApproved garde(s) sur mois validé',
        ].join(' • ');
        setState(() {
          _importStatus[slot.id] = imported > 0
              ? '$imported garde(s) Urgences transposée(s)${suffix.isEmpty ? '' : ' • $suffix'}'
              : 'Planning déjà synchronisé${suffix.isEmpty ? '' : ' • $suffix'}';
        });
      }
      if (mounted) {
        unawaited(context.read<AppState>().refreshBackend().catchError((Object e) {
          debugPrint('Actualisation après import impossible: $e');
        }));
      }
      return result;
    } finally {
      if (mounted) setState(() => _autoImportingSlots.remove(slot.id));
    }
  }

  Future<void> _upload(_OfficialSlot slot) async {
    if (_busySlot != null) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de lire ce fichier PDF.')),
      );
      return;
    }
    if (bytes.length > 25 * 1024 * 1024) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Le PDF dépasse la limite de 25 Mo.')),
      );
      return;
    }

    setState(() => _busySlot = slot.id);
    try {
      final resource = await _backend.uploadOfficialPlanningPdf(slot: slot.id, bytes: bytes, fileName: file.name);
      Map<String, dynamic>? importResult;
      Object? importError;
      try {
        importResult = await _processOfficialRoster(slot, resource, bytes: bytes);
      } catch (e) {
        importError = e;
      }
      await _load();
      if (mounted) {
        final imported = ((importResult?['inserted'] as num?)?.toInt() ?? 0) +
            ((importResult?['updated'] as num?)?.toInt() ?? 0);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              importError == null
                  ? '${slot.title} publié • $imported garde(s) Urgences transposée(s) automatiquement.'
                  : '${slot.title} publié. Transposition automatique à réessayer : $importError',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload impossible : $e')));
      }
    } finally {
      if (mounted) setState(() => _busySlot = null);
    }
  }

  Future<void> _open(SharedResource resource) async {
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _OfficialPdfViewerScreen(resource: resource),
      ),
    );
  }

  Future<void> _delete(_OfficialSlot slot, SharedResource resource) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Retirer ${slot.title} ?'),
        content: const Text('Le PDF ne sera plus visible par les utilisateurs.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Retirer')),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _busySlot = slot.id);
    try {
      await _backend.deleteSharedResource(resource);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Suppression impossible : $e')));
      }
    } finally {
      if (mounted) setState(() => _busySlot = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.watch<AppState>().currentUser?.role == UserRole.admin;
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: const GardeFlowTitle('Planning de Garde Officiel'),
        actions: [
          IconButton(onPressed: _loading ? null : _load, tooltip: 'Actualiser', icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_off_rounded, size: 42, color: AppColors.inkSoft),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh_rounded), label: const Text('Réessayer')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.lg, AppSpace.lg, 100),
                    children: [
                      _IntroCard(isAdmin: isAdmin),
                      const SizedBox(height: AppSpace.lg),
                      for (var i = 0; i < _slots.length; i++) ...[
                        _OfficialPdfCard(
                          slot: _slots[i],
                          resource: _resourceFor(_slots[i].id),
                          isAdmin: isAdmin,
                          busy: _busySlot == _slots[i].id || _autoImportingSlots.contains(_slots[i].id),
                          importStatus: _importStatus[_slots[i].id],
                          onOpen: (r) => _open(r),
                          onUpload: () => _upload(_slots[i]),
                          onDelete: (r) => _delete(_slots[i], r),
                        ),
                        if (i != _slots.length - 1) const SizedBox(height: AppSpace.md),
                      ],
                    ],
                  ),
                ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  final bool isAdmin;
  const _IntroCard({required this.isAdmin});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppRadius.lgR,
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: AppColors.brandSoft, borderRadius: AppRadius.mdR),
            child: const Icon(Icons.picture_as_pdf_rounded, color: AppColors.brand),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Documents officiels', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  isAdmin
                      ? 'Vous pouvez publier ou remplacer les trois PDF officiels. Les gardes Urgences reconnues sont automatiquement transposées dans les calendriers modifiables des médecins.'
                      : 'Consultez ici les derniers plannings officiels publiés par l’administration.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.45, color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OfficialPdfCard extends StatelessWidget {
  final _OfficialSlot slot;
  final SharedResource? resource;
  final bool isAdmin;
  final bool busy;
  final String? importStatus;
  final ValueChanged<SharedResource> onOpen;
  final VoidCallback onUpload;
  final ValueChanged<SharedResource> onDelete;

  const _OfficialPdfCard({
    required this.slot,
    required this.resource,
    required this.isAdmin,
    required this.busy,
    required this.importStatus,
    required this.onOpen,
    required this.onUpload,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final r = resource;
    final dateLabel = r == null ? null : DateFormat('dd/MM/yyyy à HH:mm', 'fr_FR').format(r.updatedAt.toLocal());
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppRadius.lgR,
        border: Border.all(color: r == null ? AppColors.line : AppColors.catService.withOpacity(0.35)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.035), blurRadius: 14, offset: const Offset(0, 5))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: r == null ? AppColors.paperAlt : AppColors.brandSoft,
                  borderRadius: AppRadius.mdR,
                ),
                child: Icon(slot.icon, color: r == null ? AppColors.inkSoft : AppColors.brand),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(slot.title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(slot.subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft)),
                  ],
                ),
              ),
              if (r != null)
                const Pill(text: 'PDF', icon: Icons.picture_as_pdf_rounded, background: Color(0xFFF7E4E4), foreground: Color(0xFF9E1B1B), fontSize: 9.5),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          if (r == null)
            Text('Aucun fichier publié.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft))
          else ...[
            Row(
              children: [
                const Icon(Icons.description_outlined, size: 17, color: AppColors.inkSoft),
                const SizedBox(width: 6),
                Expanded(child: Text(r.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
              ],
            ),
            const SizedBox(height: 4),
            Text('Mis à jour le $dateLabel', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft)),
            if (importStatus != null) ...[
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.auto_awesome_rounded, size: 15, color: AppColors.brand),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      importStatus!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.brand,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ),
            ],
          ],
          const SizedBox(height: AppSpace.md),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              if (r != null)
                FilledButton.icon(
                  onPressed: busy ? null : () => onOpen(r),
                  icon: const Icon(Icons.visibility_rounded, size: 18),
                  label: const Text('Visualiser'),
                ),
              if (isAdmin)
                OutlinedButton.icon(
                  onPressed: busy ? null : onUpload,
                  icon: busy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(r == null ? Icons.upload_file_rounded : Icons.sync_rounded, size: 18),
                  label: Text(r == null ? 'Publier' : 'Remplacer'),
                ),
              if (isAdmin && r != null)
                TextButton.icon(
                  onPressed: busy ? null : () => onDelete(r),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Retirer'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OfficialSlot {
  final String id;
  final String title;
  final String subtitle;
  final String hospital;
  final IconData icon;
  const _OfficialSlot(this.id, this.title, this.subtitle, this.hospital, this.icon);
}

class _OfficialPdfViewerScreen extends StatefulWidget {
  final SharedResource resource;

  const _OfficialPdfViewerScreen({required this.resource});

  @override
  State<_OfficialPdfViewerScreen> createState() => _OfficialPdfViewerScreenState();
}

class _OfficialPdfViewerScreenState extends State<_OfficialPdfViewerScreen> {
  final _backend = SupabaseBackendService.instance;
  final PdfViewerController _controller = PdfViewerController();

  Uint8List? _bytes;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  Future<void> _loadPdf() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final bytes = await _backend.downloadSharedResource(widget.resource.storagePath);
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    return Scaffold(
      backgroundColor: const Color(0xFF202226),
      appBar: AppBar(
        titleSpacing: 8,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Planning officiel', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            Text(
              widget.resource.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Zoom arrière',
            onPressed: _loading || bytes == null ? null : () => _controller.zoomDown(),
            icon: const Icon(Icons.zoom_out_rounded),
          ),
          IconButton(
            tooltip: 'Zoom avant',
            onPressed: _loading || bytes == null ? null : () => _controller.zoomUp(),
            icon: const Icon(Icons.zoom_in_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null || bytes == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.picture_as_pdf_outlined, size: 48, color: Colors.white70),
                        const SizedBox(height: 12),
                        const Text(
                          'Impossible d’afficher ce PDF.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '$_error',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _loadPdf,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Réessayer'),
                        ),
                      ],
                    ),
                  ),
                )
              : Stack(
                  children: [
                    Positioned.fill(
                      child: PdfViewer.data(
                        bytes,
                        sourceName: widget.resource.displayName,
                        controller: _controller,
                        params: const PdfViewerParams(
                          backgroundColor: Color(0xFF202226),
                          margin: 10,
                          minScale: 0.7,
                          maxScale: 8.0,
                          panEnabled: true,
                          scaleEnabled: true,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 14,
                      child: IgnorePointer(
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.62),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: const Text(
                              'Pincez pour zoomer • boutons + / −',
                              style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
