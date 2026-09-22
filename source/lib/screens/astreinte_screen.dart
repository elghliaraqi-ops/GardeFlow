import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

import '../data/hospitals.dart';
import '../data/services.dart';
import '../models/app_user.dart';
import '../models/shared_resource.dart';
import '../services/supabase_backend_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';

class AstreinteScreen extends StatefulWidget {
  final bool embedded;

  const AstreinteScreen({
    super.key,
    this.embedded = false,
  });

  @override
  State<AstreinteScreen> createState() => _AstreinteScreenState();
}

class _AstreinteScreenState extends State<AstreinteScreen> {
  final _backend = SupabaseBackendService.instance;
  final Map<String, Uint8List> _imageCache = <String, Uint8List>{};
  final TextEditingController _serviceSearchController = TextEditingController();
  List<SharedResource> _photos = const [];
  String _serviceQuery = '';
  bool _loading = true;
  bool _uploading = false;
  bool _hospitalInitialized = false;
  String? _selectedHospital;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hospitalInitialized) return;
    _hospitalInitialized = true;
    final user = context.read<AppState>().currentUser;
    final hospital = user != null && kHospitals.contains(user.hospital)
        ? user.hospital
        : kHospitals.first;
    _selectedHospital = hospital;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _serviceSearchController.dispose();
    super.dispose();
  }

  String _serviceFor(SharedResource resource) {
    final value = resource.service?.trim();
    return value == null || value.isEmpty ? 'À classer' : value;
  }

  List<SharedResource> _visiblePhotos() {
    final query = _searchKey(_serviceQuery);
    if (query.isEmpty) return List<SharedResource>.unmodifiable(_photos);
    return _photos
        .where((photo) => _searchKey(_serviceFor(photo)).contains(query))
        .toList(growable: false);
  }

  Map<String, List<SharedResource>> _groupedPhotos(List<SharedResource> photos) {
    final result = <String, List<SharedResource>>{};
    for (final photo in photos) {
      result.putIfAbsent(_serviceFor(photo), () => <SharedResource>[]).add(photo);
    }
    final keys = result.keys.toList()
      ..sort((a, b) {
        if (a == 'À classer') return -1;
        if (b == 'À classer') return 1;
        return _searchKey(a).compareTo(_searchKey(b));
      });
    return {for (final key in keys) key: result[key]!};
  }

  Future<String?> _selectService({String? currentService}) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ServicePickerSheet(currentService: currentService),
    );
  }

  String _activeHospital() {
    final selected = _selectedHospital;
    if (selected != null && kHospitals.contains(selected)) return selected;
    final user = context.read<AppState>().currentUser;
    if (user != null && kHospitals.contains(user.hospital)) return user.hospital;
    return kHospitals.first;
  }

  Future<void> _selectHospital(String hospital) async {
    if (!kHospitals.contains(hospital) || hospital == _selectedHospital) return;
    setState(() {
      _selectedHospital = hospital;
      _loading = true;
      _error = null;
      _photos = const [];
      _imageCache.clear();
    });
    await _load();
  }

  Future<void> _load() async {
    if (!_backend.enabled || _backend.client.auth.currentUser == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Connexion Supabase requise pour afficher les astreintes partagées.';
        });
      }
      return;
    }
    final hospital = _activeHospital();
    try {
      final rows = await _backend.fetchAstreintePhotos(hospital: hospital);
      if (!mounted) return;
      setState(() {
        _photos = rows;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Impossible de charger les astreintes de ${hospitalDisplayName(hospital)} : $e';
      });
    }
  }

  Future<void> _pickImage() async {
    if (_uploading) return;
    final hospital = _activeHospital();
    final service = await _selectService();
    if (service == null || !mounted) return;
    final picker = ImagePicker();
    final action = await showModalBottomSheet<_AstreintePickAction>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Row(
                children: [
                  const Icon(Icons.local_hospital_outlined, size: 19),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Publication pour ${hospitalDisplayName(hospital)}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          service,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.inkSoft,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (!kIsWeb)
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Prendre une photo'),
                onTap: () => Navigator.pop(ctx, _AstreintePickAction.camera),
              ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(kIsWeb ? 'Choisir plusieurs images' : 'Choisir plusieurs photos'),
              subtitle: const Text('Sélection multiple, sans limite imposée par GardeFlow'),
              onTap: () => Navigator.pop(ctx, _AstreintePickAction.gallery),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    final files = <XFile>[];
    if (action == _AstreintePickAction.camera) {
      final file = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
        maxWidth: 1600,
      );
      if (file != null) files.add(file);
    } else {
      final selected = await picker.pickMultiImage(
        imageQuality: 70,
        maxWidth: 1600,
      );
      files.addAll(selected);
    }

    if (files.isEmpty || !mounted) return;

    setState(() => _uploading = true);
    var uploaded = 0;
    var failed = 0;
    try {
      for (final file in files) {
        try {
          final bytes = await file.readAsBytes();
          final mime = file.mimeType ?? _mimeForName(file.name);
          await _backend.uploadAstreintePhoto(
            bytes: bytes,
            fileName: file.name,
            mimeType: mime,
            hospital: hospital,
            service: service,
          );
          uploaded++;
        } catch (_) {
          failed++;
        }
      }

      _imageCache.clear();
      await _load();
      if (mounted) {
        final target = hospitalDisplayName(hospital);
        final message = failed == 0
            ? (uploaded == 1
                ? 'Photo d’astreinte publiée dans $service • $target.'
                : '$uploaded photos d’astreinte publiées dans $service • $target.')
            : '$uploaded photo${uploaded > 1 ? 's' : ''} publiée${uploaded > 1 ? 's' : ''} dans $service • $target, $failed échec${failed > 1 ? 's' : ''}.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<Uint8List> _bytesFor(SharedResource resource) async {
    final cached = _imageCache[resource.id];
    if (cached != null) return cached;
    final bytes = await _backend.downloadSharedResource(resource.storagePath);
    _imageCache[resource.id] = bytes;
    return bytes;
  }

  Future<void> _editService(SharedResource resource) async {
    final current = _serviceFor(resource);
    final service = await _selectService(
      currentService: current == 'À classer' ? null : current,
    );
    if (service == null || service == current || !mounted) return;
    try {
      await _backend.updateAstreintePhotoService(
        resource: resource,
        service: service,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Photo classée dans $service.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Classement impossible : $e')),
        );
      }
    }
  }

  Future<void> _delete(SharedResource resource) async {
    final hospital = _activeHospital();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cette photo ?'),
        content: Text(
          'Elle disparaîtra de la galerie des Séniors d’astreinte de ${hospitalDisplayName(hospital)}.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _backend.deleteSharedResource(resource);
      _imageCache.remove(resource.id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Suppression impossible : $e')));
      }
    }
  }

  void _openPhoto(SharedResource resource) {
    final service = _serviceFor(resource);
    final servicePhotos = _photos
        .where((photo) => _serviceFor(photo) == service)
        .toList(growable: false);
    final initialIndex = servicePhotos.indexWhere((p) => p.id == resource.id);
    showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: _AstreinteGalleryViewer(
          photos: List<SharedResource>.unmodifiable(servicePhotos),
          service: service,
          initialIndex: initialIndex < 0 ? 0 : initialIndex,
          backend: _backend,
          onClose: () => Navigator.pop(ctx),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppState>().currentUser;
    final isAdmin = user?.role == UserRole.admin;
    final hospital = _selectedHospital ??
        (user != null && kHospitals.contains(user.hospital)
            ? user.hospital
            : kHospitals.first);

    Widget content;
    if (_loading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      content = _ErrorState(message: _error!, onRetry: _load);
    } else if (_photos.isEmpty && !isAdmin) {
      content = _EmptyHospitalGallery(hospital: hospital);
    } else {
      content = RefreshIndicator(
        onRefresh: _load,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 900
                ? 4
                : constraints.maxWidth >= 600
                    ? 3
                    : 2;
            return GridView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                AppSpace.lg,
                AppSpace.md,
                AppSpace.lg,
                widget.embedded ? 28 : 100,
              ),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: AppSpace.md,
                crossAxisSpacing: AppSpace.md,
                childAspectRatio: 0.78,
              ),
              itemCount: _photos.length + (isAdmin ? 1 : 0),
              itemBuilder: (context, i) {
                if (isAdmin && i == 0) {
                  return _AdminAddTile(
                    uploading: _uploading,
                    hospital: hospital,
                    onTap: _pickImage,
                  );
                }
                final photo = _photos[i - (isAdmin ? 1 : 0)];
                return _AstreintePhotoCard(
                  resource: photo,
                  imageFuture: _bytesFor(photo),
                  canDelete: isAdmin,
                  onTap: () => _openPhoto(photo),
                  onDelete: () => _delete(photo),
                );
              },
            );
          },
        ),
      );
    }

    final body = Column(
      children: [
        if (widget.embedded)
          Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Photos par établissement',
                    style: TextStyle(
                      color: AppColors.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Actualiser',
                  onPressed: _loading ? null : _load,
                  icon: Icon(Icons.refresh_rounded),
                  color: AppColors.brand,
                ),
                if (isAdmin)
                  IconButton(
                    tooltip:
                        'Ajouter une photo pour ${hospitalDisplayName(hospital)}',
                    onPressed: _uploading ? null : _pickImage,
                    icon: _uploading
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(Icons.add_photo_alternate_rounded),
                    color: AppColors.brand,
                  ),
              ],
            ),
          ),
        _HospitalAstreinteHeader(
          hospital: hospital,
          isAdmin: isAdmin,
          onSelectHospital: _selectHospital,
        ),
        Expanded(child: content),
      ],
    );

    if (widget.embedded) {
      return ColoredBox(
        color: AppColors.paper,
        child: body,
      );
    }

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: GardeFlowTitle('Médecins Séniors de Garde / Astreinte'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _loading ? null : _load,
            icon: Icon(Icons.refresh_rounded),
          ),
          if (isAdmin)
            IconButton(
              tooltip:
                  'Ajouter une photo pour ${hospitalDisplayName(hospital)}',
              onPressed: _uploading ? null : _pickImage,
              icon: _uploading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.add_photo_alternate_rounded),
            ),
        ],
      ),
      body: body,
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpace.lg,
            AppSpace.sm,
            AppSpace.lg,
            AppSpace.md,
          ),
          child: Text(
            isAdmin
                ? 'Vous gérez actuellement les photos de ${hospitalDisplayName(hospital)}. Changez d’établissement en haut pour publier dans une autre galerie.'
                : 'Tous les médecins peuvent consulter les photos des trois hôpitaux. Sélectionnez l’établissement en haut.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.inkSoft,
                  height: 1.4,
                ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _HospitalAstreinteHeader extends StatelessWidget {
  final String hospital;
  final bool isAdmin;
  final ValueChanged<String> onSelectHospital;

  const _HospitalAstreinteHeader({
    required this.hospital,
    required this.isAdmin,
    required this.onSelectHospital,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.sm),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_hospital_rounded, size: 18, color: AppColors.brand),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  hospitalDisplayName(hospital),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                isAdmin ? 'Galerie à gérer' : 'Toutes les galeries',
                style: TextStyle(fontSize: 11, color: AppColors.inkSoft),
              ),
            ],
          ),
          SizedBox(height: 9),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final item in kHospitals) ...[
                  ChoiceChip(
                    label: Text(hospitalDisplayName(item)),
                    selected: item == hospital,
                    onSelected: (_) => onSelectHospital(item),
                  ),
                  if (item != kHospitals.last) SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHospitalGallery extends StatelessWidget {
  final String hospital;
  const _EmptyHospitalGallery({required this.hospital});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.all(AppSpace.xl),
      children: [
        SizedBox(height: 60),
        Icon(Icons.photo_library_outlined, size: 46, color: AppColors.inkSoft),
        SizedBox(height: 12),
        Text(
          'Aucune photo d’astreinte publiée pour ${hospitalDisplayName(hospital)}.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.inkSoft),
        ),
      ],
    );
  }
}

class _AstreinteGalleryViewer extends StatefulWidget {
  final List<SharedResource> photos;
  final int initialIndex;
  final SupabaseBackendService backend;
  final VoidCallback onClose;

  const _AstreinteGalleryViewer({
    required this.photos,
    required this.initialIndex,
    required this.backend,
    required this.onClose,
  });

  @override
  State<_AstreinteGalleryViewer> createState() => _AstreinteGalleryViewerState();
}

class _AstreinteGalleryViewerState extends State<_AstreinteGalleryViewer> {
  late final PageController _pageController;
  late final Future<List<String>> _urlsFuture;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _urlsFuture = Future.wait(
      widget.photos.map(
        (photo) => widget.backend.signedSharedResourceUrl(photo.storagePath, expiresIn: 3600),
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<List<String>>(
        future: _urlsFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Stack(
              children: [
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Impossible de charger la galerie.',
                      style: TextStyle(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                Positioned(top: 10, right: 10, child: _GalleryCloseButton(onClose: widget.onClose)),
              ],
            );
          }

          final urls = snapshot.data;
          if (urls == null) {
            return Stack(
              children: [
                const Center(child: CircularProgressIndicator()),
                Positioned(top: 10, right: 10, child: _GalleryCloseButton(onClose: widget.onClose)),
              ],
            );
          }

          return Stack(
            children: [
              Positioned.fill(
                child: PhotoViewGallery.builder(
                  pageController: _pageController,
                  itemCount: widget.photos.length,
                  scrollPhysics: const BouncingScrollPhysics(),
                  backgroundDecoration: const BoxDecoration(color: Colors.black),
                  loadingBuilder: (context, event) => const Center(child: CircularProgressIndicator()),
                  onPageChanged: (index) => setState(() => _currentIndex = index),
                  builder: (context, index) => PhotoViewGalleryPageOptions(
                    imageProvider: NetworkImage(urls[index]),
                    initialScale: PhotoViewComputedScale.contained,
                    minScale: PhotoViewComputedScale.contained,
                    maxScale: PhotoViewComputedScale.covered * 4.0,
                    heroAttributes: PhotoViewHeroAttributes(tag: 'astreinte-photo-${widget.photos[index].id}'),
                    errorBuilder: (context, error, stackTrace) => const Center(
                      child: Text('Image indisponible', style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 10,
                left: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.58),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '${_currentIndex + 1} / ${widget.photos.length}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              Positioned(top: 10, right: 10, child: _GalleryCloseButton(onClose: widget.onClose)),
              if (widget.photos.length > 1)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 14,
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.58),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: const Text(
                          'Glissez à gauche ou à droite • pincez pour zoomer',
                          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _GalleryCloseButton extends StatelessWidget {
  final VoidCallback onClose;
  const _GalleryCloseButton({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      onPressed: onClose,
      icon: const Icon(Icons.close_rounded),
    );
  }
}

class _AstreintePhotoCard extends StatelessWidget {
  final SharedResource resource;
  final Future<Uint8List> imageFuture;
  final bool canDelete;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _AstreintePhotoCard({
    required this.resource,
    required this.imageFuture,
    required this.canDelete,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: AppRadius.lgR,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Positioned.fill(
              child: FutureBuilder<Uint8List>(
                future: imageFuture,
                builder: (context, snap) {
                  if (snap.hasData) return Image.memory(snap.data!, fit: BoxFit.cover);
                  if (snap.hasError) {
                    return Center(child: Icon(Icons.broken_image_outlined, color: AppColors.inkSoft));
                  }
                  return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                },
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 28, 10, 9),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xC8000000)],
                  ),
                ),
                child: Text(
                  resource.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            if (canDelete)
              Positioned(
                top: 7,
                right: 7,
                child: IconButton.filled(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Supprimer',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AdminAddTile extends StatelessWidget {
  final bool uploading;
  final String hospital;
  final VoidCallback onTap;
  const _AdminAddTile({required this.uploading, required this.hospital, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.paperAlt,
      borderRadius: AppRadius.lgR,
      child: InkWell(
        borderRadius: AppRadius.lgR,
        onTap: uploading ? null : onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: AppRadius.lgR,
            border: Border.all(color: AppColors.line, width: 1.4),
          ),
          alignment: Alignment.center,
          padding: EdgeInsets.all(AppSpace.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (uploading)
                CircularProgressIndicator(strokeWidth: 2)
              else
                Icon(Icons.cloud_upload_outlined, size: 34, color: AppColors.catService),
              SizedBox(height: 8),
              Text(uploading ? 'Envoi…' : 'Publier des photos', textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink)),
              SizedBox(height: 4),
              Text('Pour ${hospitalDisplayName(hospital)}', textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10.5, color: AppColors.inkSoft)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 40, color: AppColors.inkSoft),
            SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            SizedBox(height: 12),
            FilledButton.icon(onPressed: onRetry, icon: Icon(Icons.refresh_rounded), label: Text('Réessayer')),
          ],
        ),
      ),
    );
  }
}

String _mimeForName(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  return 'image/jpeg';
}

enum _AstreintePickAction { camera, gallery }
