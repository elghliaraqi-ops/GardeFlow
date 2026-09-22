import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/hospitals.dart';
import '../models/app_user.dart';
import '../models/shared_resource.dart';
import '../services/supabase_backend_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';

class OperatingRoomProgramScreen extends StatefulWidget {
  const OperatingRoomProgramScreen({super.key});

  @override
  State<OperatingRoomProgramScreen> createState() =>
      _OperatingRoomProgramScreenState();
}

class _OperatingRoomProgramScreenState
    extends State<OperatingRoomProgramScreen> {
  final _backend = SupabaseBackendService.instance;

  bool _loading = true;
  String? _error;
  String? _busyHospital;
  final Map<String, List<SharedResource>> _programs = {};

  static const _hospitals = <_BlocHospital>[
    _BlocHospital(
      kHospitalBouskoura,
      'HUIM6 de Bouskoura',
      Icons.local_hospital_rounded,
    ),
    _BlocHospital(
      kHospitalRabat,
      'HUIM6 de Rabat',
      Icons.account_balance_rounded,
    ),
    _BlocHospital(
      kHospitalCasa,
      'HUICK de Casablanca',
      Icons.apartment_rounded,
    ),
  ];

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  List<_BlocHospital> _visibleHospitals(AppUser? user) {
    if (user == null) return const [];
    if (user.role == UserRole.admin) return _hospitals;
    return _hospitals
        .where((item) => item.hospital == user.hospital)
        .toList(growable: false);
  }

  Future<void> _load() async {
    final user = context.read<AppState>().currentUser;
    if (user == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final visible = _visibleHospitals(user);
      final result = <String, List<SharedResource>>{};
      for (final item in visible) {
        result[item.hospital] =
            await _backend.fetchBlocPrograms(hospital: item.hospital);
      }
      if (!mounted) return;
      setState(() {
        _programs
          ..clear()
          ..addAll(result);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Impossible de charger les programmes du bloc : ' + e.toString();
      });
    }
  }

  String? _mimeFor(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (lower.endsWith('.xls')) return 'application/vnd.ms-excel';
    return null;
  }

  Future<void> _upload(_BlocHospital target) async {
    if (_busyHospital != null) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'xlsx', 'xls'],
      withData: true,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty || !mounted) return;

    final file = result.files.single;
    final bytes = file.bytes;
    final mimeType = _mimeFor(file.name);

    if (bytes == null || mimeType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fichier non pris en charge. Utilisez PDF, XLSX ou XLS.'),
        ),
      );
      return;
    }

    if (bytes.length > 25 * 1024 * 1024) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Le fichier dépasse la limite de 25 Mo.')),
      );
      return;
    }

    setState(() => _busyHospital = target.hospital);
    try {
      await _backend.uploadBlocProgram(
        bytes: bytes,
        fileName: file.name,
        mimeType: mimeType,
        hospital: target.hospital,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Programme du bloc publié pour ' + target.title + '.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import impossible : ' + e.toString())),
      );
    } finally {
      if (mounted) setState(() => _busyHospital = null);
    }
  }

  Future<void> _open(SharedResource resource) async {
    final lower = resource.displayName.toLowerCase();
    final isPdf =
        resource.mimeType == 'application/pdf' || lower.endsWith('.pdf');

    if (isPdf) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _BlocPdfViewerScreen(resource: resource),
        ),
      );
      return;
    }

    try {
      final url = await _backend.signedSharedResourceUrl(
        resource.storagePath,
        expiresIn: 900,
      );
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        throw StateError('Aucune application ne peut ouvrir ce fichier.');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ouverture impossible : ' + e.toString())),
      );
    }
  }

  Future<void> _delete(
    _BlocHospital hospital,
    SharedResource resource,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ce programme ?'),
        content: Text(
          resource.displayName +
              '\n\nLe fichier ne sera plus disponible dans GardeFlow.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _busyHospital = hospital.hospital);
    try {
      await _backend.deleteSharedResource(resource);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Suppression impossible : ' + e.toString())),
      );
    } finally {
      if (mounted) setState(() => _busyHospital = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppState>().currentUser;
    final visibleHospitals = _visibleHospitals(user);
    final isAdmin = user?.role == UserRole.admin;

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: const GardeFlowTitle('Programme du bloc'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh_rounded),
          ),
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
                        Icon(
                          Icons.cloud_off_rounded,
                          size: 44,
                          color: AppColors.inkSoft,
                        ),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Réessayer'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(
                      AppSpace.lg,
                      AppSpace.lg,
                      AppSpace.lg,
                      100,
                    ),
                    children: [
                      AppCard(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: AppColors.brandSoft,
                                borderRadius: AppRadius.mdR,
                              ),
                              child: Icon(
                                Icons.medical_services_rounded,
                                color: AppColors.brand,
                              ),
                            ),
                            const SizedBox(width: AppSpace.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Programmes opératoires',
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    isAdmin
                                        ? 'Importez le fichier original tel quel. Aucun contenu n’est analysé ni transposé.'
                                        : 'Consultez directement le programme du bloc de votre établissement.',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpace.lg),
                      for (var i = 0; i < visibleHospitals.length; i++) ...[
                        _HospitalProgramCard(
                          hospital: visibleHospitals[i],
                          resources:
                              _programs[visibleHospitals[i].hospital] ?? const [],
                          isAdmin: isAdmin,
                          busy:
                              _busyHospital == visibleHospitals[i].hospital,
                          onUpload: () => _upload(visibleHospitals[i]),
                          onOpen: _open,
                          onDelete: (resource) =>
                              _delete(visibleHospitals[i], resource),
                        ),
                        if (i != visibleHospitals.length - 1)
                          const SizedBox(height: AppSpace.md),
                      ],
                    ],
                  ),
                ),
    );
  }
}

class _HospitalProgramCard extends StatelessWidget {
  final _BlocHospital hospital;
  final List<SharedResource> resources;
  final bool isAdmin;
  final bool busy;
  final VoidCallback onUpload;
  final ValueChanged<SharedResource> onOpen;
  final ValueChanged<SharedResource> onDelete;

  const _HospitalProgramCard({
    required this.hospital,
    required this.resources,
    required this.isAdmin,
    required this.busy,
    required this.onUpload,
    required this.onOpen,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final latest = resources.isEmpty ? null : resources.first;
    final latestLabel = latest == null
        ? 'Aucun programme disponible'
        : 'Dernière mise à jour : ' +
            DateFormat('dd/MM/yyyy à HH:mm', 'fr_FR')
                .format(latest.createdAt.toLocal());

    return AppCard(
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
                  borderRadius: AppRadius.mdR,
                ),
                child: Icon(hospital.icon, color: AppColors.brand),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hospital.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    Text(
                      latestLabel,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (isAdmin)
                FilledButton.icon(
                  onPressed: busy ? null : onUpload,
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_file_rounded),
                  label: const Text('Importer'),
                ),
            ],
          ),
          if (latest != null) ...[
            const SizedBox(height: AppSpace.md),
            _ProgramFileTile(
              resource: latest,
              latest: true,
              isAdmin: isAdmin,
              busy: busy,
              onOpen: () => onOpen(latest),
              onDelete: () => onDelete(latest),
            ),
          ],
          if (resources.length > 1) ...[
            const SizedBox(height: AppSpace.sm),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text(
                'Historique (' + (resources.length - 1).toString() + ')',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              children: [
                for (final resource in resources.skip(1))
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.sm),
                    child: _ProgramFileTile(
                      resource: resource,
                      latest: false,
                      isAdmin: isAdmin,
                      busy: busy,
                      onOpen: () => onOpen(resource),
                      onDelete: () => onDelete(resource),
                    ),
                  ),
              ],
            ),
          ],
          if (latest == null && !isAdmin) ...[
            const SizedBox(height: AppSpace.md),
            Text(
              'Le programme apparaîtra ici dès sa publication.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _ProgramFileTile extends StatelessWidget {
  final SharedResource resource;
  final bool latest;
  final bool isAdmin;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  const _ProgramFileTile({
    required this.resource,
    required this.latest,
    required this.isAdmin,
    required this.busy,
    required this.onOpen,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final lower = resource.displayName.toLowerCase();
    final isPdf =
        resource.mimeType == 'application/pdf' || lower.endsWith('.pdf');
    final icon =
        isPdf ? Icons.picture_as_pdf_rounded : Icons.table_view_rounded;
    final dateLabel = DateFormat('dd/MM/yyyy HH:mm', 'fr_FR')
        .format(resource.createdAt.toLocal());

    return Material(
      color: AppColors.paperAlt,
      borderRadius: AppRadius.mdR,
      child: InkWell(
        onTap: busy ? null : onOpen,
        borderRadius: AppRadius.mdR,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Row(
            children: [
              Icon(icon, color: isPdf ? AppColors.urg24h : AppColors.brand),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            resource.displayName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        if (latest) ...[
                          const SizedBox(width: 8),
                          const Pill(
                            text: 'Actuel',
                            icon: Icons.check_circle_rounded,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      (isPdf ? 'PDF' : 'Excel') + ' • ' + dateLabel,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Ouvrir',
                onPressed: busy ? null : onOpen,
                icon: const Icon(Icons.open_in_new_rounded),
              ),
              if (isAdmin)
                IconButton(
                  tooltip: 'Supprimer',
                  onPressed: busy ? null : onDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BlocPdfViewerScreen extends StatefulWidget {
  final SharedResource resource;

  const _BlocPdfViewerScreen({required this.resource});

  @override
  State<_BlocPdfViewerScreen> createState() => _BlocPdfViewerScreenState();
}

class _BlocPdfViewerScreenState extends State<_BlocPdfViewerScreen> {
  final _backend = SupabaseBackendService.instance;
  final _controller = PdfViewerController();

  Uint8List? _bytes;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes =
          await _backend.downloadSharedResource(widget.resource.storagePath);
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    return Scaffold(
      backgroundColor: const Color(0xFF202226),
      appBar: AppBar(
        title: Text(
          widget.resource.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Zoom arrière',
            onPressed: bytes == null ? null : () => _controller.zoomDown(),
            icon: const Icon(Icons.zoom_out_rounded),
          ),
          IconButton(
            tooltip: 'Zoom avant',
            onPressed: bytes == null ? null : () => _controller.zoomUp(),
            icon: const Icon(Icons.zoom_in_rounded),
          ),
        ],
      ),
      body: bytes == null
          ? _error == null
              ? const Center(child: CircularProgressIndicator())
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.picture_as_pdf_outlined,
                          color: Colors.white70,
                          size: 48,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Impossible d’afficher le document.\n' + _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Réessayer'),
                        ),
                      ],
                    ),
                  ),
                )
          : PdfViewer.data(
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
    );
  }
}

class _BlocHospital {
  final String hospital;
  final String title;
  final IconData icon;

  const _BlocHospital(this.hospital, this.title, this.icon);
}
