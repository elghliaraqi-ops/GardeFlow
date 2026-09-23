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
  final Map<String, int> _myGuardCounts = <String, int>{};
  final Map<String, int> _myDisciplinaryCounts = <String, int>{};
  final Map<String, bool> _myCanResync = <String, bool>{};
  final Set<String> _guardCountLoading = <String>{};

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
      unawaited(_refreshMyGuardCount(rows));
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


  _OfficialSlot? _slotForHospital(String hospital) {
    for (final slot in _slots) {
      if (slot.hospital == hospital) return slot;
    }
    return null;
  }

  Future<void> _refreshMyGuardCount(List<SharedResource> resources) async {
    if (!mounted) return;
    final me = context.read<AppState>().currentUser;
    if (me == null) return;
    final slot = _slotForHospital(me.hospital);
    if (slot == null) return;
    SharedResource? resource;
    for (final item in resources) {
      if (item.slot == slot.id) {
        resource = item;
        break;
      }
    }
    if (resource == null || _guardCountLoading.contains(slot.id)) return;
    setState(() => _guardCountLoading.add(slot.id));
    try {
      final bytes = await _backend.downloadSharedResource(resource.storagePath);
      final profiles = await _backend.fetchVisibleProfiles();
      final parsed = await OfficialRosterImportService.parse(
        bytes: bytes,
        displayName: resource.displayName,
        hospital: slot.hospital,
        profiles: profiles,
        resourceUpdatedAt: resource.updatedAt,
      );
      // Le résumé affiché doit refléter ce qui est réellement retrouvé
      // dans le PDF, pas seulement les lignes déjà transposées en base.
      // Cela évite de sous-compter une garde quand la superposition n'a pas
      // encore été refaite ou qu'une ancienne ligne a été modifiée.
      final myAssignments = parsed.assignments
          .where((a) => a.profileId == me.id)
          .toList(growable: false);
      final count = myAssignments.length;
      final parsedDisciplinaryCount =
          myAssignments.where((a) => a.isDisciplinary).length;

      // Le serveur peut avoir verrouillé une garde via une règle disciplinaire
      // même si le parser local n'a pas encore mis à jour la ligne affichée.
      // On conserve donc le maximum entre la lecture directe du PDF et le
      // registre serveur.
      final summary =
          await _backend.officialRosterMySummary(resource: resource);
      final serverDisciplinaryCount =
          (summary['disciplinary'] as num?)?.toInt() ?? 0;
      final disciplinaryCount =
          parsedDisciplinaryCount > serverDisciplinaryCount
              ? parsedDisciplinaryCount
              : serverDisciplinaryCount;
      final canResync = summary['can_resync'] as bool? ?? false;

      if (mounted) {
        setState(() {
          _myGuardCounts[slot.id] = count;
          _myDisciplinaryCounts[slot.id] = disciplinaryCount;
          _myCanResync[slot.id] = canResync;
        });
      }
    } catch (e) {
      debugPrint('Comptage des gardes ${slot.id} impossible: $e');
    } finally {
      if (mounted) setState(() => _guardCountLoading.remove(slot.id));
    }
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

      await _backend.registerOfficialDisciplinaryMarks(
        resource: resource,
        marks: parsed.disciplinaryMarks
            .map((m) => m.toJson())
            .toList(growable: false),
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

  Future<void> _resyncMyRoster(
    _OfficialSlot slot,
    SharedResource resource,
  ) async {
    if (_busySlot != null || _guardCountLoading.contains(slot.id)) return;

    final appState = context.read<AppState>();
    setState(() => _busySlot = slot.id);
    try {
      final summary =
          await _backend.officialRosterMySummary(resource: resource);
      final canResync = summary['can_resync'] as bool? ?? false;
      if (!canResync) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Calendrier validé définitivement : la superposition ne peut plus être refaite.',
            ),
          ),
        );
        return;
      }

      await appState.forceSyncMyOfficialRoster();
      await _refreshMyGuardCount(_resources);

      if (!mounted) return;
      final count = _myGuardCounts[slot.id] ?? 0;
      final disciplinary = _myDisciplinaryCounts[slot.id] ?? 0;
      final disciplineLabel = disciplinary == 0
          ? ''
          : ' dont ${disciplinary} garde${disciplinary > 1 ? 's' : ''} disciplinaire${disciplinary > 1 ? 's' : ''}';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Superposition refaite : ${count} garde${count > 1 ? 's' : ''} retrouvée${count > 1 ? 's' : ''}${disciplineLabel}.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Resynchronisation impossible : ${e}')),
      );
    } finally {
      if (mounted) setState(() => _busySlot = null);
    }
  }

  Future<void> _open(SharedResource resource) async {
    if (!mounted) return;
    final me = context.read<AppState>().currentUser;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _OfficialPdfViewerScreen(resource: resource, currentUser: me),
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
    final currentUser = context.watch<AppState>().currentUser;
    final isAdmin = currentUser?.role == UserRole.admin;
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: GardeFlowTitle('Planning de Garde Officiel'),
        actions: [
          IconButton(onPressed: _loading ? null : _load, tooltip: 'Actualiser', icon: Icon(Icons.refresh_rounded)),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpace.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_off_rounded, size: 42, color: AppColors.inkSoft),
                        SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        SizedBox(height: 12),
                        FilledButton.icon(onPressed: _load, icon: Icon(Icons.refresh_rounded), label: Text('Réessayer')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.lg, AppSpace.lg, 100),
                    children: [
                      _IntroCard(isAdmin: isAdmin),
                      SizedBox(height: AppSpace.lg),
                      for (var i = 0; i < _slots.length; i++) ...[
                        _OfficialPdfCard(
                          slot: _slots[i],
                          resource: _resourceFor(_slots[i].id),
                          isAdmin: isAdmin,
                          busy: _busySlot == _slots[i].id || _autoImportingSlots.contains(_slots[i].id),
                          importStatus: _importStatus[_slots[i].id],
                          myGuardCount: currentUser?.hospital == _slots[i].hospital ? _myGuardCounts[_slots[i].id] : null,
                          myDisciplinaryCount: currentUser?.hospital == _slots[i].hospital ? _myDisciplinaryCounts[_slots[i].id] : null,
                          canResync: currentUser?.hospital == _slots[i].hospital ? (_myCanResync[_slots[i].id] ?? false) : false,
                          guardCountLoading: currentUser?.hospital == _slots[i].hospital && _guardCountLoading.contains(_slots[i].id),
                          isMyHospital: currentUser?.hospital == _slots[i].hospital,
                          onOpen: (r) => _open(r),
                          onResync: (r) => _resyncMyRoster(_slots[i], r),
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
      padding: EdgeInsets.all(AppSpace.lg),
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
            child: Icon(Icons.picture_as_pdf_rounded, color: AppColors.brand),
          ),
          SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Documents officiels', style: Theme.of(context).textTheme.titleMedium),
                SizedBox(height: 4),
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
  final int? myGuardCount;
  final int? myDisciplinaryCount;
  final bool canResync;
  final bool guardCountLoading;
  final bool isMyHospital;
  final ValueChanged<SharedResource> onOpen;
  final ValueChanged<SharedResource> onResync;
  final VoidCallback onUpload;
  final ValueChanged<SharedResource> onDelete;

  const _OfficialPdfCard({
    required this.slot,
    required this.resource,
    required this.isAdmin,
    required this.busy,
    required this.importStatus,
    required this.myGuardCount,
    required this.myDisciplinaryCount,
    required this.canResync,
    required this.guardCountLoading,
    required this.isMyHospital,
    required this.onOpen,
    required this.onResync,
    required this.onUpload,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final r = resource;
    final dateLabel = r == null ? null : DateFormat('dd/MM/yyyy à HH:mm', 'fr_FR').format(r.updatedAt.toLocal());
    return Container(
      padding: EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppRadius.lgR,
        border: Border.all(color: r == null ? AppColors.line : AppColors.catService.withOpacity(0.35)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.035), blurRadius: 14, offset: Offset(0, 5))],
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
              SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(slot.title, style: Theme.of(context).textTheme.titleMedium),
                    SizedBox(height: 2),
                    Text(slot.subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft)),
                  ],
                ),
              ),
              if (r != null)
                Pill(text: 'PDF', icon: Icons.picture_as_pdf_rounded, background: Color(0xFFF7E4E4), foreground: Color(0xFF9E1B1B), fontSize: 9.5),
            ],
          ),
          SizedBox(height: AppSpace.md),
          if (r == null)
            Text('Aucun fichier publié.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft))
          else ...[
            Row(
              children: [
                Icon(Icons.description_outlined, size: 17, color: AppColors.inkSoft),
                SizedBox(width: 6),
                Expanded(child: Text(r.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700))),
              ],
            ),
            SizedBox(height: 4),
            Text('Mis à jour le $dateLabel', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft)),
            if (isMyHospital) ...[
              SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Color(0xFFFFF59D).withOpacity(0.42),
                  borderRadius: AppRadius.smR,
                  border: Border.all(color: Color(0xFFF9A825).withOpacity(0.35)),
                ),
                child: Row(children: [
                  Icon(Icons.manage_search_rounded, size: 17, color: Color(0xFF8D6E00)),
                  SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      guardCountLoading
                          ? 'Recherche de vos gardes dans ce PDF…'
                          : () {
                              final total = myGuardCount ?? 0;
                              final disciplinary = myDisciplinaryCount ?? 0;
                              final base =
                                  '${total} garde${total > 1 ? 's' : ''} retrouvée${total > 1 ? 's' : ''} pour vous';
                              if (disciplinary <= 0) return base;
                              return '${base} dont ${disciplinary} garde${disciplinary > 1 ? 's' : ''} disciplinaire${disciplinary > 1 ? 's' : ''}';
                            }(),
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF6D5700)),
                    ),
                  ),
                ]),
              ),
            ],
            if (importStatus != null) ...[
              SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.auto_awesome_rounded, size: 15, color: AppColors.brand),
                  SizedBox(width: 5),
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
          SizedBox(height: AppSpace.md),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              if (r != null)
                FilledButton.icon(
                  onPressed: busy ? null : () => onOpen(r),
                  icon: Icon(Icons.visibility_rounded, size: 18),
                  label: Text('Visualiser'),
                ),
              if (r != null && isMyHospital && canResync)
                OutlinedButton.icon(
                  onPressed: busy ? null : () => onResync(r),
                  icon: busy
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.sync_rounded, size: 18),
                  label: Text('Refaire la superposition'),
                ),
              if (isAdmin)
                OutlinedButton.icon(
                  onPressed: busy ? null : onUpload,
                  icon: busy
                      ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(r == null ? Icons.upload_file_rounded : Icons.sync_rounded, size: 18),
                  label: Text(r == null ? 'Publier' : 'Remplacer'),
                ),
              if (isAdmin && r != null)
                TextButton.icon(
                  onPressed: busy ? null : () => onDelete(r),
                  icon: Icon(Icons.delete_outline_rounded, size: 18),
                  label: Text('Retirer'),
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
  final AppUser? currentUser;

  const _OfficialPdfViewerScreen({required this.resource, required this.currentUser});

  @override
  State<_OfficialPdfViewerScreen> createState() => _OfficialPdfViewerScreenState();
}

class _OfficialPdfViewerScreenState extends State<_OfficialPdfViewerScreen> {
  final _backend = SupabaseBackendService.instance;
  final PdfViewerController _controller = PdfViewerController();
  final TextEditingController _searchField = TextEditingController();

  PdfTextSearcher? _doctorSearcher;
  PdfTextSearcher? _manualSearcher;

  Uint8List? _bytes;
  Object? _error;
  bool _loading = true;
  bool _searchMode = false;
  bool _viewerReady = false;

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  void _disposeSearchers() {
    final doctor = _doctorSearcher;
    final manual = _manualSearcher;
    if (doctor != null) {
      doctor.removeListener(_onSearchChanged);
      doctor.dispose();
    }
    if (manual != null) {
      manual.removeListener(_onSearchChanged);
      manual.dispose();
    }
    _doctorSearcher = null;
    _manualSearcher = null;
  }

  @override
  void dispose() {
    _disposeSearchers();
    _searchField.dispose();
    super.dispose();
  }

  Future<void> _loadPdf() async {
    _disposeSearchers();
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _viewerReady = false;
        _searchMode = false;
        _searchField.clear();
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

  Pattern? _doctorPattern() {
    final user = widget.currentUser;
    if (user == null) return null;
    final nom = user.nom.trim();
    final prenom = user.prenom.trim();
    if (nom.isEmpty || prenom.isEmpty) return null;

    final firstPrenom = prenom.split(RegExp(r'\s+')).first;
    final variants = <String>{
      '${RegExp.escape(prenom)}\s+${RegExp.escape(nom)}',
      '${RegExp.escape(nom)}\s+${RegExp.escape(prenom)}',
      '${RegExp.escape(firstPrenom)}\s+${RegExp.escape(nom)}',
      '${RegExp.escape(nom)}\s+${RegExp.escape(firstPrenom)}',
    };
    return RegExp('(?:${variants.join('|')})', caseSensitive: false);
  }

  void _startDoctorHighlight() {
    final searcher = _doctorSearcher;
    final pattern = _doctorPattern();
    if (searcher == null || pattern == null) return;
    searcher.startTextSearch(
      pattern,
      caseInsensitive: true,
      goToFirstMatch: false,
      searchImmediately: true,
    );
  }

  void _search(String raw) {
    final searcher = _manualSearcher;
    if (searcher == null) return;
    final query = raw.trim();
    if (query.isEmpty) {
      searcher.resetTextSearch();
      return;
    }
    searcher.startTextSearch(
      query,
      caseInsensitive: true,
      goToFirstMatch: true,
      searchImmediately: true,
    );
  }

  void _toggleSearch() {
    if (!_viewerReady) return;
    setState(() {
      _searchMode = !_searchMode;
      if (!_searchMode) {
        _searchField.clear();
        _manualSearcher?.resetTextSearch();
      }
    });
  }

  void _paintDoctorMatches(Canvas canvas, Rect pageRect, PdfPage page) {
    _doctorSearcher?.pageTextMatchPaintCallback(canvas, pageRect, page);
  }

  void _paintManualMatches(Canvas canvas, Rect pageRect, PdfPage page) {
    _manualSearcher?.pageTextMatchPaintCallback(canvas, pageRect, page);
  }

  void _viewerDidBecomeReady(PdfViewerController controller) {
    if (_viewerReady) return;

    // Critical V11.6.8 fix: instantiate PdfTextSearcher only now, after the
    // controller owns a loaded document.
    _disposeSearchers();
    _doctorSearcher = PdfTextSearcher(controller)..addListener(_onSearchChanged);
    _manualSearcher = PdfTextSearcher(controller)..addListener(_onSearchChanged);
    _viewerReady = true;

    _startDoctorHighlight();
    Future.microtask(() {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    final manualSearcher = _manualSearcher;
    final currentIndex = manualSearcher?.currentIndex;
    final matchCount = manualSearcher?.matches.length ?? 0;
    final searching = manualSearcher?.isSearching ?? false;
    final searchStatus = searching
        ? 'Recherche…'
        : matchCount == 0
            ? 'Aucun résultat'
            : '${(currentIndex ?? 0) + 1}/$matchCount';

    return Scaffold(
      backgroundColor: const Color(0xFF202226),
      appBar: AppBar(
        titleSpacing: 8,
        title: _searchMode
            ? TextField(
                controller: _searchField,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: (value) {
                  if (value.trim().length >= 2 || value.trim().isEmpty) _search(value);
                },
                onSubmitted: _search,
                decoration: const InputDecoration(
                  hintText: 'Rechercher un nom, mot, service…',
                  border: InputBorder.none,
                ),
              )
            : Column(
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
            tooltip: _searchMode ? 'Fermer la recherche' : 'Rechercher dans le PDF',
            onPressed: _loading || bytes == null || !_viewerReady ? null : _toggleSearch,
            icon: Icon(_searchMode ? Icons.close_rounded : Icons.search_rounded),
          ),
          if (!_searchMode) ...[
            IconButton(
              tooltip: 'Zoom arrière',
              onPressed: _loading || bytes == null || !_viewerReady ? null : () => _controller.zoomDown(),
              icon: const Icon(Icons.zoom_out_rounded),
            ),
            IconButton(
              tooltip: 'Zoom avant',
              onPressed: _loading || bytes == null || !_viewerReady ? null : () => _controller.zoomUp(),
              icon: const Icon(Icons.zoom_in_rounded),
            ),
          ],
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
                        params: PdfViewerParams(
                          backgroundColor: const Color(0xFF202226),
                          margin: 10,
                          minScale: 0.7,
                          maxScale: 8.0,
                          panEnabled: true,
                          scaleEnabled: true,
                          matchTextColor: const Color(0xFFFFF176).withOpacity(0.62),
                          activeMatchTextColor: const Color(0xFFFFB300).withOpacity(0.78),
                          pagePaintCallbacks: [
                            _paintDoctorMatches,
                            _paintManualMatches,
                          ],
                          onDocumentChanged: (document) {
                            if (document == null) {
                              Future.microtask(() {
                                if (!mounted) return;
                                _disposeSearchers();
                                setState(() => _viewerReady = false);
                              });
                            }
                          },
                          onViewerReady: (document, controller) {
                            _viewerDidBecomeReady(controller);
                          },
                        ),
                      ),
                    ),
                    if (_searchMode)
                      Positioned(
                        top: 10,
                        left: 12,
                        right: 12,
                        child: SafeArea(
                          bottom: false,
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.72),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    searchStatus,
                                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(width: 6),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    tooltip: 'Résultat précédent',
                                    onPressed: matchCount == 0 ? null : () => _manualSearcher?.goToPrevMatch(),
                                    icon: const Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white),
                                  ),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    tooltip: 'Résultat suivant',
                                    onPressed: matchCount == 0 ? null : () => _manualSearcher?.goToNextMatch(),
                                    icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white),
                                  ),
                                ],
                              ),
                            ),
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
                            child: Text(
                              !_viewerReady
                                  ? 'Chargement du document…'
                                  : widget.currentUser == null
                                      ? 'Pincez pour zoomer • loupe pour rechercher'
                                      : '${widget.currentUser!.fullName} est surligné en fluo • loupe pour rechercher',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
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
