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
import '../services/official_roster_verified_read_service.dart';
import '../services/supabase_backend_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';
import '../theme/screen_decor.dart';

// Le choix de la seconde lecture appartient exclusivement à l'admin.
enum _OfficialRosterReadChoice { pdfrx, groq }

/// Navigation hint only; selecting a reader never starts Groq automatically.
enum OfficialPlanningReader { pdfrx, groq }

class OfficialPlanningScreen extends StatefulWidget {
  const OfficialPlanningScreen({super.key, this.preferredReader});

  final OfficialPlanningReader? preferredReader;

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
    final currentResource = resource;
    setState(() => _guardCountLoading.add(slot.id));
    try {
      final profiles = await _backend.fetchVisibleProfiles();
      final parsed = await _readVerifiedRoster(
        slot,
        currentResource,
        profiles,
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
          await _backend.officialRosterMySummary(resource: currentResource);
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

  Future<OfficialRosterParseResult> _readVerifiedRoster(
    _OfficialSlot slot,
    SharedResource resource,
    List<AppUser> profiles, {
    Uint8List? currentBytes,
  }) async {
    final versions = await _backend.fetchOfficialRosterVersions(slot.id);
    final hasCurrentVersion = versions.any(
      (version) =>
          version.storagePath == resource.storagePath &&
          version.updatedAt.toUtc() == resource.updatedAt.toUtc(),
    );
    if (!hasCurrentVersion) versions.insert(0, resource);

    final suppliedBytes = <String, Uint8List>{
      if (currentBytes != null) resource.storagePath: currentBytes,
    };
    final identityLinks =
        await _backend.fetchOfficialRosterIdentityLinks(hospital: slot.hospital);

    final parsed =
        await OfficialRosterVerifiedReadService.readVersionHistory(
      versionsNewestFirst: versions,
      loadBytes: _backend.downloadSharedResource,
      // Cache déjà validé consultable, mais aucun Groq déclenché ici.
      loadVerified: (version) => _backend.fetchOfficialRosterVerifiedRead(
        resource: version,
        parserRevision: OfficialRosterImportService.parserRevision,
      ),
      hospital: slot.hospital,
      profiles: profiles,
      suppliedBytes: suppliedBytes,
      identityLinks: identityLinks,
    );

    if (parsed.detectedRows == 0 || !parsed.isComplete) {
      final details = parsed.validationErrors.take(5).join(' • ');
      throw StateError(
        details.isEmpty
            ? 'Aucune lecture fiable du planning officiel.'
            : 'Lecture du planning incomplète : ' + details,
      );
    }
    return parsed;
  }

  Future<void> _autoImportExisting(List<SharedResource> resources) async {
    for (final resource in resources) {
      if (!mounted) return;
      if (resource.slot == null) continue;
      final slot = _slotForId(resource.slot);
      if (slot == null || _autoImportingSlots.contains(slot.id) || _busySlot == slot.id) continue;
      try {
        final current = await _backend.officialRosterImportIsCurrent(
          resource,
          parserRevision: OfficialRosterImportService.parserRevision,
        );
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
      final profiles = await _backend.fetchVisibleProfiles();
      final parsed = await _readVerifiedRoster(
        slot,
        resource,
        profiles,
        currentBytes: bytes,
      );
      if (parsed.detectedRows == 0) {
        throw StateError('Aucune ligne de garde 08h-20h / 20h-08h reconnue dans ce PDF.');
      }
      if (!parsed.isComplete) {
        throw StateError(
          'Lecture refusée : planning incomplet. ' +
              parsed.validationErrors.take(5).join(' • '),
        );
      }
      if (parsed.assignments.isEmpty) {
        throw StateError('Le tableau est lisible mais aucun nom ne correspond aux médecins inscrits de ${slot.title}.');
      }
      final result = await _backend.importOfficialEmergencyRoster(
        resource: resource,
        assignments: parsed.assignments.map((a) => a.toJson()).toList(growable: false),
        unmatchedCells: parsed.unmatchedCells,
        parserRevision: OfficialRosterImportService.parserRevision,
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

  /// Relit à nouveau le PDF choisi avec pdfrx, sans cache ni appel IA.
  /// Les calendriers et le rapport R6 certifié ne sont jamais écrasés.
  Future<void> _rereadPdfrx(
    _OfficialSlot slot,
    SharedResource resource,
  ) async {
    if (_busySlot != null || _autoImportingSlots.contains(slot.id)) return;
    if (context.read<AppState>().currentUser?.role != UserRole.admin) return;

    final selected = _resourceFor(slot.id);
    if (selected == null ||
        selected.id != resource.id ||
        selected.slot != slot.id ||
        selected.updatedAt.toUtc() != resource.updatedAt.toUtc()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(
          'Le PDF sélectionné a changé : actualisez avant de relire avec pdfrx.',
        )),
      );
      return;
    }

    setState(() {
      _busySlot = slot.id;
      _importStatus[slot.id] = 'Lecture locale pdfrx en cours…';
    });
    try {
      // Télécharger et relire uniquement la version exacte du PDF sélectionné.
      final bytes = await _backend.downloadSharedResource(resource.storagePath);
      final profiles = await _backend.fetchVisibleProfiles();
      final parsed = await OfficialRosterImportService.parse(
        bytes: bytes,
        displayName: resource.displayName,
        hospital: slot.hospital,
        profiles: profiles,
        resourceUpdatedAt: resource.updatedAt,
      );
      if (!mounted) return;
      final complete = parsed.isComplete &&
          parsed.detectedRows > 0 &&
          parsed.coveredDates.isNotEmpty;
      setState(() {
        _importStatus[slot.id] = complete
            ? 'pdfrx relu : ${parsed.detectedCells} cellule(s), '
              '${parsed.assignments.length} garde(s) attribuable(s). '
              'Résultat à contrôler, calendriers inchangés.'
            : 'pdfrx : lecture incomplète, aucune modification. '
              'Vérifiez le détail ou lancez Groq manuellement.';
      });
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Lecture 1 — pdfrx : ${slot.title}'),
          content: SizedBox(
            width: 610,
            height: MediaQuery.sizeOf(dialogContext).height * 0.58,
            child: ListView(
              children: [
                Text(resource.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 9),
                Text(
                  '${parsed.detectedRows} date(s) • '
                  '${parsed.detectedCells} cellule(s) • '
                  '${parsed.assignments.length} affectation(s) reconnue(s) • '
                  '${parsed.unmatchedCells.length} cellule(s) non attribuée(s)',
                ),
                const SizedBox(height: 10),
                Text(
                  complete
                      ? 'Extraction locale terminée. Contrôlez les noms et les '
                        'créneaux avant une éventuelle correction Groq.'
                      : 'Extraction locale incomplète. Aucune garde modifiée. '
                        'Vous pouvez relire ce PDF avec Groq.',
                  style: TextStyle(
                    color: complete ? AppColors.success : AppColors.danger,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (parsed.validationErrors.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final error in parsed.validationErrors)
                    Text('• $error',
                        style: const TextStyle(color: AppColors.danger)),
                ],
                const SizedBox(height: 12),
                const Text(
                  'Dates, créneaux et noms extraits',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                if (parsed.localCells.isEmpty)
                  const Text('Aucune cellule exploitable dans ce PDF.'),
                for (final cell in parsed.localCells)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${cell.date} • ${cell.shift} : '
                      '${cell.text.trim().isEmpty ? "(vide)" : cell.text}'
                      '${cell.redText.trim().isEmpty ? "" : " • ROUGE : ${cell.redText}"}',
                    ),
                  ),
                const SizedBox(height: 12),
                const Text(
                  'Cette relecture ne publie pas de rapport R6 vérifié et '
                  'ne modifie pas les calendriers. Le recalcul des '
                  'superpositions exige toujours une source R6 validée.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _importStatus[slot.id] =
            'Lecture pdfrx impossible : aucune garde modifiée.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Échec de la relecture pdfrx : $error')),
      );
    } finally {
      if (mounted) setState(() => _busySlot = null);
    }
  }

  /// R6/Groq : publie le rapport de lecture officiel uniquement.
  /// Le recalcul des superpositions personnelles reste une étape séparée
  /// soumise à un aperçu et à une validation administrateur.
  Future<void> _rereadR6(
    _OfficialSlot slot,
    SharedResource resource,
  ) async {
    if (_busySlot != null || _autoImportingSlots.contains(slot.id)) return;
    if (context.read<AppState>().currentUser?.role != UserRole.admin) return;

    // Ne relire QUE le document sélectionné. La liste des autres
    // établissements n'entre jamais dans cette requête réseau.
    final selected = _resourceFor(slot.id);
    if (selected == null ||
        selected.id != resource.id ||
        selected.slot != slot.id ||
        selected.updatedAt.toUtc() != resource.updatedAt.toUtc()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ce PDF a changé : actualisez la liste avant de lancer Groq.',
          ),
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Relecture Groq ciblée'),
        content: Text(
          'Envoyer uniquement « ${resource.displayName} » '
          '(${slot.title}) à Groq ? '
          'Aucun PDF des autres établissements ne sera envoyé. '
          'La lecture peut comporter plusieurs pages du même PDF. '
          'Les calendriers restent inchangés jusqu’à validation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Lire ce PDF avec Groq'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    if (_busySlot != null || _autoImportingSlots.contains(slot.id)) return;
    setState(() {
      _busySlot = slot.id;
      _importStatus[slot.id] = 'Relecture R6 / Groq en cours…';
    });
    try {
      final profiles = await _backend.fetchVisibleProfiles();
      final identityLinks = await _backend.fetchOfficialRosterIdentityLinks(
        hospital: slot.hospital,
      );
      // Déclenchement EXPLICITE de B : ne pas réutiliser un cache
      // potentiellement erroné lorsque l'admin constate une mauvaise lecture.
      var localEvidence = const <Map<String, dynamic>>[];
      try {
        final bytes = await _backend.downloadSharedResource(resource.storagePath);
        final local = await OfficialRosterImportService.parse(
          bytes: bytes,
          displayName: resource.displayName,
          hospital: slot.hospital,
          profiles: profiles,
          resourceUpdatedAt: resource.updatedAt,
        );
        localEvidence = local.localCells
            .map((cell) => cell.toJson())
            .toList(growable: false);
      } catch (error) {
        debugPrint('Lecture pdfrx initiale indisponible : $error');
      }
      final extraction = await _backend.analyzeOfficialRosterResource(
        resource.id,
        parserRevision: OfficialRosterImportService.parserRevision,
        selectedSlot: slot.id,
        selectedUpdatedAt: resource.updatedAt,
        manualGroqConfirmed: true,
        localEvidence: localEvidence,
        forceReread: true,
      );
      final read = OfficialRosterVerifiedReadService.fromExtraction(
        extraction: extraction,
        hospital: slot.hospital,
        profiles: profiles,
        identityLinks: identityLinks,
      );
      if (extraction['verified'] != true ||
          extraction['document_scope'] != 'urgences' ||
          !read.isComplete ||
          read.detectedRows == 0) {
        final details = read.validationErrors.take(3).join(' • ');
        throw StateError(details.isEmpty
            ? 'Lecture Urgences non vérifiée. Publication bloquée.'
            : 'Vérification refusée : $details');
      }

      await _backend.saveOfficialRosterAnalysisR6(
        resource: resource,
        extraction: extraction,
        guards: read.officialGuards,
        unmatchedCells: read.unmatchedCells,
      );
      if (!mounted) return;
      setState(() {
        _importStatus[slot.id] =
            'Source Urgences vérifiée avec R6/Groq : '
            '${read.officialGuards.length} garde(s) officielle(s). '
            'Calendriers inchangés. Lancez ensuite l’aperçu des superpositions.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Source R6 vérifiée et enregistrée. '
            'Aucune superposition personnelle modifiée.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _importStatus[slot.id] =
            'Relecture R6 refusée : aucune modification des calendriers.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Relecture R6 impossible : $error')),
      );
    } finally {
      if (mounted) setState(() => _busySlot = null);
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
      // Validation renforcée avant publication :
      // A = lecture géométrique locale indépendante quand elle est exploitable ;
      // B = lecture visuelle distante sans connaissance des comptes ;
      // C = lecture d'arbitrage déclenchée seulement si A/B ou les contrôles
      // de complétude signalent un désaccord.
      final profiles = await _backend.fetchVisibleProfiles();
      final identityLinks =
          await _backend.fetchOfficialRosterIdentityLinks(hospital: slot.hospital);
      OfficialRosterParseResult? localPreflight;
      try {
        localPreflight = await OfficialRosterImportService.parse(
          bytes: bytes,
          displayName: file.name,
          hospital: slot.hospital,
          profiles: profiles,
        );
      } catch (e) {
        debugPrint('Prélecture locale non exploitable: ' + e.toString());
      }

      if (!mounted) return;
      final localComplete = localPreflight != null &&
          localPreflight.isComplete &&
          localPreflight.detectedRows > 0 &&
          localPreflight.coveredDates.isNotEmpty;
      final choice = await showDialog<_OfficialRosterReadChoice>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Lecture du planning Urgences'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Lecture 1 : pdfrx 2.6.5 (locale, sans appel IA). '
                  'Vérifiez le PDF et les gardes détectées avant de publier.',
                ),
                const SizedBox(height: 12),
                Text(
                  '${localPreflight?.detectedRows ?? 0} jour(s), '
                  '${localPreflight?.detectedCells ?? 0} cellule(s), '
                  '${localPreflight?.assignments.length ?? 0} affectation(s) '
                  'reconnue(s), '
                  '${localPreflight?.unmatchedCells.length ?? 0} élément(s) '
                  'sans correspondance.',
                ),
                const SizedBox(height: 12),
                if (localPreflight != null)
                  ExpansionTile(
                    initiallyExpanded: !localComplete,
                    tilePadding: EdgeInsets.zero,
                    title: Text(
                      'Détail des cellules détectées '
                      '(${localPreflight.localCells.length})',
                    ),
                    children: [
                      for (final cell in localPreflight.localCells)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '${cell.date} • ${cell.shift} : '
                              '${cell.text.trim().isEmpty ? "(vide)" : cell.text}'
                              '${cell.redText.trim().isEmpty ? "" : " • ROUGE : ${cell.redText}"}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: 12),
                if (!localComplete)
                  const Text(
                    'Lecture locale incomplète : publication avec pdfrx '
                    'bloquée. Vous pouvez déclencher Groq manuellement.',
                    style: TextStyle(color: Colors.deepOrange),
                  ),
                if (localPreflight?.validationErrors.isNotEmpty ?? false)
                  Text(
                    localPreflight!.validationErrors.take(5).join(' • '),
                    style: const TextStyle(fontSize: 12),
                  ),
                const SizedBox(height: 12),
                const Text(
                  'Lecture 2 : Groq uniquement si vous le demandez. '
                  'Lecture 3 : arbitrage R6 automatique uniquement '
                  'en cas de désaccord ou de lecture insuffisante.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            TextButton.icon(
              onPressed: () => Navigator.pop(
                dialogContext,
                _OfficialRosterReadChoice.groq,
              ),
              icon: const Icon(Icons.auto_fix_high_rounded),
              label: const Text('Corriger avec Groq'),
            ),
            FilledButton(
              onPressed: !localComplete
                  ? null
                  : () => Navigator.pop(
                        dialogContext,
                        _OfficialRosterReadChoice.pdfrx,
                      ),
              child: const Text('Valider la lecture pdfrx'),
            ),
          ],
        ),
      );
      if (choice == null || !mounted) return;
      if (choice == _OfficialRosterReadChoice.pdfrx) {
        final accepted = localPreflight!;
        // Aucun Groq invoqué dans ce parcours. Import de la seule
        // extraction locale complète, après validation explicite de l'admin.
        final resource = await _backend.uploadOfficialPlanningPdf(
          slot: slot.id,
          bytes: bytes,
          fileName: file.name,
          coveredDates: accepted.coveredDates,
          parserRevision: OfficialRosterImportService.parserRevision,
        );
        Map<String, dynamic>? imported;
        Object? importError;
        try {
          imported = await _processOfficialRoster(slot, resource, bytes: bytes);
        } catch (error) {
          importError = error;
        }
        await _load();
        if (mounted) {
          final count = ((imported?['inserted'] as num?)?.toInt() ?? 0) +
              ((imported?['updated'] as num?)?.toInt() ?? 0);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(importError == null
                ? 'PDF publié avec pdfrx : $count garde(s) Urgences '
                  'synchronisée(s). Groq non appelé.'
                : 'PDF publié. Import local à vérifier : $importError. '
                  'Vous pouvez lancer Groq manuellement.'),
          ));
        }
        return;
      }

      // Groq B est exclusivement déclenché par cette action administrateur.
      // Le moteur R6 déclenche C si A/B divergent, sans jamais écraser une
      // lecture non validée.
      final localEvidence = localPreflight?.localCells
              .map((cell) => cell.toJson())
              .toList(growable: false) ??
          const <Map<String, dynamic>>[];
      var verifiedPayload = await _backend.analyzeOfficialRosterPreflight(
        bytes: bytes,
        fileName: file.name,
        slot: slot.id,
        manualGroqConfirmed: true,
        localEvidence: localEvidence,
        parserRevision: OfficialRosterImportService.parserRevision,
      );

      if (verifiedPayload['verified'] != true &&
          verifiedPayload['status']?.toString().toLowerCase() == 'red') {
        final conflicts = verifiedPayload['conflicts'] is List
            ? (verifiedPayload['conflicts'] as List)
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList(growable: false)
            : const <Map<String, dynamic>>[];
        if (conflicts.isNotEmpty && mounted) {
          final resolutions = await showDialog<List<Map<String, dynamic>>>(
            context: context,
            barrierDismissible: false,
            builder: (_) => _OfficialRosterConflictReviewDialog(
              conflicts: conflicts,
            ),
          );
          if (resolutions == null) {
            throw StateError(
              'Publication annulée : les zones litigieuses restent en statut ROUGE.',
            );
          }
          verifiedPayload = await _backend.analyzeOfficialRosterPreflight(
            bytes: bytes,
            fileName: file.name,
            slot: slot.id,
            manualGroqConfirmed: true,
            localEvidence: localEvidence,
            manualResolutions: resolutions,
            parserRevision: OfficialRosterImportService.parserRevision,
          );
        }
      }

      final preflight = OfficialRosterVerifiedReadService.fromExtraction(
        extraction: verifiedPayload,
        hospital: slot.hospital,
        profiles: profiles,
        identityLinks: identityLinks,
      );
      if (preflight.detectedRows == 0 || !preflight.isComplete) {
        final details = preflight.validationErrors.take(5).join(' • ');
        throw StateError(
          details.isEmpty
              ? 'Le planning n’a pas passé la vérification indépendante A/B/C.'
              : 'Planning refusé avant publication : ' + details,
        );
      }
      final verificationToken =
          verifiedPayload['_verification_token']?.toString();
      if (verificationToken == null || verificationToken.isEmpty) {
        throw StateError(
          'La vérification A/B/C a réussi mais son jeton de vérification est absent.',
        );
      }

      final resource = await _backend.uploadOfficialPlanningPdf(
        slot: slot.id,
        bytes: bytes,
        fileName: file.name,
        coveredDates: preflight.coveredDates,
        parserRevision: OfficialRosterImportService.parserRevision,
      );

      // Relecture de la version réellement publiée : elle est mise en cache
      // et devient la référence vérifiée utilisée ensuite par tous les comptes.
      final publishedVerification =
          await _backend.analyzeOfficialRosterResource(
        resource.id,
        parserRevision: OfficialRosterImportService.parserRevision,
        selectedSlot: slot.id,
        selectedUpdatedAt: resource.updatedAt,
        manualGroqConfirmed: true,
        verificationToken: verificationToken,
      );
      final publishedRead =
          OfficialRosterVerifiedReadService.fromExtraction(
        extraction: publishedVerification,
        hospital: slot.hospital,
        profiles: profiles,
        identityLinks: identityLinks,
      );
      if (!publishedRead.isComplete ||
          !OfficialRosterVerifiedReadService.sameCoreAssignments(
            preflight,
            publishedRead,
          )) {
        throw StateError(
          'La vérification de la version publiée ne concorde pas avec la '
          'prélecture. Synchronisation automatique bloquée.',
        );
      }
      await _backend.saveOfficialRosterAnalysisR6(
        resource: resource,
        extraction: publishedVerification,
        guards: publishedRead.officialGuards,
        unmatchedCells: publishedRead.unmatchedCells,
      );

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
    return DecorScaffold(scene: ScreenDecorScene.planning, 
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
                      if (isAdmin && widget.preferredReader != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          widget.preferredReader == OfficialPlanningReader.pdfrx
                              ? 'Choisissez l’établissement puis « Relire avec pdfrx ».'
                              : 'Choisissez l’établissement puis « Relire avec Groq ».',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
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
                          onRereadPdfrx: (r) => _rereadPdfrx(_slots[i], r),
                          onRereadR6: (r) => _rereadR6(_slots[i], r),
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

class _OfficialRosterConflictReviewDialog extends StatefulWidget {
  final List<Map<String, dynamic>> conflicts;

  const _OfficialRosterConflictReviewDialog({required this.conflicts});

  @override
  State<_OfficialRosterConflictReviewDialog> createState() =>
      _OfficialRosterConflictReviewDialogState();
}

class _OfficialRosterConflictReviewDialogState
    extends State<_OfficialRosterConflictReviewDialog> {
  late final List<_RosterConflictDraft> _drafts;
  late final List<Map<String, dynamic>> _structuralConflicts;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    final grouped = <String, List<Map<String, dynamic>>>{};
    final structural = <Map<String, dynamic>>[];
    for (final conflict in widget.conflicts) {
      final date = conflict['date']?.toString().trim() ?? '';
      final shift = conflict['shift']?.toString().trim() ?? '';
      if (date.isEmpty ||
          (shift != 'urg-jour' &&
              shift != 'urg-nuit' &&
              shift != 'urg-24h')) {
        structural.add(conflict);
        continue;
      }
      grouped.putIfAbsent('$date|$shift', () => []).add(conflict);
    }

    _structuralConflicts = structural;
    _drafts = grouped.entries.map((entry) {
      final conflicts = entry.value;
      final first = conflicts.first;
      final b = _rowMap(first['b']);
      final c = _rowMap(first['c']);
      return _RosterConflictDraft(
        date: first['date'].toString(),
        shift: first['shift'].toString(),
        messages: conflicts
            .map((item) => item['message']?.toString() ?? 'Désaccord')
            .toSet()
            .join(' • '),
        b: b,
        c: c,
      );
    }).toList(growable: false)
      ..sort((a, b) {
        final byDate = a.date.compareTo(b.date);
        return byDate != 0 ? byDate : a.shift.compareTo(b.shift);
      });
  }

  @override
  void dispose() {
    for (final draft in _drafts) {
      draft.dispose();
    }
    super.dispose();
  }

  static Map<String, dynamic>? _rowMap(dynamic value) {
    if (value is! Map) return null;
    final row = Map<String, dynamic>.from(value);
    if ((row['date'] ?? '').toString().isEmpty ||
        (row['shift'] ?? '').toString().isEmpty) {
      return null;
    }
    return row;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.report_problem_rounded, color: AppColors.danger),
          SizedBox(width: 10),
          Expanded(child: Text('Planning en statut ROUGE')),
        ],
      ),
      content: SizedBox(
        width: 760,
        height: MediaQuery.sizeOf(context).height * .68,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Aucune publication automatique n’est autorisée. '
              'Corrigez uniquement les cellules litigieuses ci-dessous. '
              'Le moteur relancera ensuite tous les contrôles de complétude.',
              style: TextStyle(color: AppColors.inkSoft),
            ),
            if (_structuralConflicts.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: AppColors.danger.withOpacity(.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.danger.withOpacity(.30),
                  ),
                ),
                child: Text(
                  '${_structuralConflicts.length} anomalie(s) structurelle(s) '
                  'sans cellule localisable restent bloquantes. '
                  'Le PDF doit être corrigé ou relu avec une structure exploitable.',
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
            if (_validationError != null) ...[
              const SizedBox(height: 10),
              Text(
                _validationError!,
                style: const TextStyle(
                  color: AppColors.danger,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: _drafts.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, index) => _buildConflict(_drafts[index]),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler la publication'),
        ),
        FilledButton.icon(
          onPressed: _structuralConflicts.isNotEmpty ? null : _submit,
          icon: const Icon(Icons.verified_rounded),
          label: const Text('Valider ces corrections'),
        ),
      ],
    );
  }

  Widget _buildConflict(_RosterConflictDraft draft) {
    final bAvailable = draft.b != null;
    final cAvailable = draft.c != null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${draft.date} • ${draft.shift}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
              const Icon(Icons.lock_outline_rounded, size: 18),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            draft.messages,
            style: TextStyle(color: AppColors.inkSoft, fontSize: 12),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: draft.action,
            decoration: const InputDecoration(
              labelText: 'Décision administrateur',
            ),
            items: [
              if (bAvailable)
                const DropdownMenuItem(
                  value: 'use_b',
                  child: Text('Conserver la Lecture B'),
                ),
              if (cAvailable)
                const DropdownMenuItem(
                  value: 'use_c',
                  child: Text('Conserver la Lecture C'),
                ),
              const DropdownMenuItem(
                value: 'manual',
                child: Text('Saisie manuelle de cette cellule'),
              ),
              const DropdownMenuItem(
                value: 'remove',
                child: Text('Supprimer cette cellule parasite'),
              ),
            ],
            onChanged: (value) => setState(() => draft.action = value),
          ),
          if (bAvailable || cAvailable) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (bAvailable)
                  Expanded(
                    child: _ConflictReadPreview(
                      label: 'B',
                      row: draft.b!,
                    ),
                  ),
                if (bAvailable && cAvailable) const SizedBox(width: 8),
                if (cAvailable)
                  Expanded(
                    child: _ConflictReadPreview(
                      label: 'C',
                      row: draft.c!,
                    ),
                  ),
              ],
            ),
          ],
          if (draft.action == 'manual') ...[
            const SizedBox(height: 12),
            TextField(
              controller: draft.finalDate,
              decoration: const InputDecoration(
                labelText: 'Date finale YYYY-MM-DD',
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: draft.finalShift,
              decoration: const InputDecoration(labelText: 'Créneau final'),
              items: const [
                DropdownMenuItem(
                  value: 'urg-jour',
                  child: Text('Urgences Jour'),
                ),
                DropdownMenuItem(
                  value: 'urg-nuit',
                  child: Text('Urgences Nuit'),
                ),
                DropdownMenuItem(
                  value: 'urg-24h',
                  child: Text('Urgences 24H'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => draft.finalShift = value);
                }
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: draft.doctors,
              minLines: 2,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Médecins — une ligne par médecin',
                helperText:
                    'Format : Prénom | Nom | Nom complet (3e champ optionnel)',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: draft.redNames,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Noms rouges — un nom complet par ligne',
                helperText: 'Laisser vide si aucune garde disciplinaire.',
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _submit() {
    if (_drafts.isEmpty) {
      setState(() => _validationError =
          'Aucune cellule localisable ne peut être corrigée.');
      return;
    }

    final resolutions = <Map<String, dynamic>>[];
    for (final draft in _drafts) {
      final action = draft.action;
      if (action == null) {
        setState(() => _validationError =
            'Une décision explicite est requise pour chaque cellule.');
        return;
      }

      final resolution = <String, dynamic>{
        'date': draft.date,
        'shift': draft.shift,
        'action': action,
      };
      if (action == 'manual') {
        final finalDate = draft.finalDate.text.trim();
        if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(finalDate)) {
          setState(() =>
              _validationError = 'Date manuelle invalide : $finalDate');
          return;
        }
        final doctors = <Map<String, dynamic>>[];
        for (final rawLine in draft.doctors.text.split('\n')) {
          final line = rawLine.trim();
          if (line.isEmpty) continue;
          final parts = line.split('|').map((part) => part.trim()).toList();
          if (parts.length < 2 ||
              parts[0].isEmpty ||
              parts[1].isEmpty) {
            setState(() => _validationError =
                'Format médecin invalide pour ${draft.date} ${draft.shift}.');
            return;
          }
          doctors.add({
            'first_name': parts[0],
            'last_name': parts[1],
            'full_name': parts.length >= 3 && parts[2].isNotEmpty
                ? parts[2]
                : '${parts[0]} ${parts[1]}',
            'confidence': 1.0,
          });
        }

        resolution['final_date'] = finalDate;
        resolution['final_shift'] = draft.finalShift;
        resolution['doctors'] = doctors;
        resolution['red_names'] = draft.redNames.text
            .split('\n')
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList(growable: false);
      }
      resolutions.add(resolution);
    }

    Navigator.pop(context, resolutions);
  }
}

class _RosterConflictDraft {
  final String date;
  final String shift;
  final String messages;
  final Map<String, dynamic>? b;
  final Map<String, dynamic>? c;
  String? action;
  late final TextEditingController finalDate;
  String finalShift;
  late final TextEditingController doctors;
  late final TextEditingController redNames;

  _RosterConflictDraft({
    required this.date,
    required this.shift,
    required this.messages,
    required this.b,
    required this.c,
  }) : finalShift = shift {
    finalDate = TextEditingController(text: date);
    final preferred = c ?? b;
    doctors = TextEditingController(text: _doctorsText(preferred));
    redNames = TextEditingController(text: _redNamesText(preferred));
  }

  static String _doctorsText(Map<String, dynamic>? row) {
    final raw = row?['doctors'];
    if (raw is! List) return '';
    return raw
        .whereType<Map>()
        .map((doctor) {
          final first = doctor['first_name']?.toString().trim() ?? '';
          final last = doctor['last_name']?.toString().trim() ?? '';
          final full = doctor['full_name']?.toString().trim() ?? '';
          return '$first | $last | $full';
        })
        .where((line) => line.replaceAll('|', '').trim().isNotEmpty)
        .join('\n');
  }

  static String _redNamesText(Map<String, dynamic>? row) {
    final raw = row?['red_names'];
    if (raw is! List) return '';
    return raw
        .map((value) => value.toString().trim())
        .where((value) => value.isNotEmpty)
        .join('\n');
  }

  void dispose() {
    finalDate.dispose();
    doctors.dispose();
    redNames.dispose();
  }
}

class _ConflictReadPreview extends StatelessWidget {
  final String label;
  final Map<String, dynamic> row;

  const _ConflictReadPreview({
    required this.label,
    required this.row,
  });

  @override
  Widget build(BuildContext context) {
    final doctors = row['doctors'] is List
        ? (row['doctors'] as List)
            .whereType<Map>()
            .map(
              (doctor) =>
                  doctor['full_name']?.toString().trim() ?? '',
            )
            .where((value) => value.isNotEmpty)
            .join(', ')
        : '';
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: AppColors.paperAlt,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppColors.line),
      ),
      child: Text(
        'Lecture $label\n'
        "${row['date'] ?? '—'} • ${row['shift'] ?? '—'}\n"
        "${doctors.isEmpty ? 'Aucun médecin lu' : doctors}",
        style: TextStyle(
          color: AppColors.inkSoft,
          fontSize: 11.5,
          height: 1.35,
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
  final ValueChanged<SharedResource> onRereadPdfrx;
  final ValueChanged<SharedResource> onRereadR6;
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
    required this.onRereadPdfrx,
    required this.onRereadR6,
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
              if (isAdmin && r != null)
                OutlinedButton.icon(
                  onPressed: busy ? null : () => onRereadPdfrx(r),
                  icon: const Icon(Icons.document_scanner_rounded, size: 18),
                  label: const Text('Relire avec pdfrx'),
                ),
              if (isAdmin && r != null)
                OutlinedButton.icon(
                  onPressed: busy ? null : () => onRereadR6(r),
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.fact_check_rounded, size: 18),
                  label: const Text('Relire avec Groq'),
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

    return DecorScaffold(scene: ScreenDecorScene.planning, 
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
