import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_user.dart';
import '../services/supabase_backend_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/screen_decor.dart';
import '../theme/widgets.dart';

class AdminRosterRecalculationScreen extends StatefulWidget {
  const AdminRosterRecalculationScreen({super.key});

  @override
  State<AdminRosterRecalculationScreen> createState() =>
      _AdminRosterRecalculationScreenState();
}

class _AdminRosterRecalculationScreenState
    extends State<AdminRosterRecalculationScreen> {
  final _backend = SupabaseBackendService.instance;
  String? _selectedProfileId;
  Map<String, dynamic>? _preview;
  List<Map<String, dynamic>> _globalPreviews = const [];
  String? _globalGuidance;
  bool _busy = false;
  bool _globalBusy = false;

  List<AppUser> _doctors(AppState appState) {
    final values = appState.users
        .where((user) => user.accountStatus == AccountStatus.active)
        .toList(growable: false);
    values.sort(
      (a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
    );
    return values;
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final doctors = _doctors(appState);
    _selectedProfileId ??= doctors.isEmpty ? null : doctors.first.id;

    return DecorScaffold(
      scene: ScreenDecorScene.admin,
      appBar: AppBar(
        title: const GardeFlowTitle('Superpositions'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          const DecorSectionBanner(
            scene: ScreenDecorScene.admin,
            title: 'Recalcul depuis la source officielle',
            subtitle:
                'Le PDF et les gardes officielles ne sont jamais modifiés. '
                'Seule la couche personnelle dérivée est reconstruite.',
            icon: Icons.layers_rounded,
          ),
          const SizedBox(height: 16),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Recalcul individuel',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                ),
                const SizedBox(height: 4),
                Text(
                  'Aperçu obligatoire avant toute application.',
                  style: TextStyle(color: AppColors.inkSoft),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: _selectedProfileId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Médecin',
                    prefixIcon: Icon(Icons.person_rounded),
                  ),
                  items: doctors
                      .map(
                        (doctor) => DropdownMenuItem<String>(
                          value: doctor.id,
                          child: Text(
                            '${doctor.fullName} • ${doctor.hospital}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: _busy
                      ? null
                      : (value) {
                          setState(() {
                            _selectedProfileId = value;
                            _preview = null;
                          });
                        },
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy || _selectedProfileId == null
                      ? null
                      : _previewIndividual,
                  icon: _busy
                      ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.preview_rounded),
                  label: const Text('Recalculer la superposition — aperçu'),
                ),
              ],
            ),
          ),
          if (_preview != null) ...[
            const SizedBox(height: 12),
            _PreviewCard(
              preview: _preview!,
              onApply: _busy ? null : _applyIndividual,
            ),
          ],
          const SizedBox(height: 20),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.groups_rounded, color: AppColors.warning),
                    SizedBox(width: 9),
                    Text(
                      'Recalcul global',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Prépare un aperçu pour chaque médecin actif. '
                  'Aucune écriture n’est faite avant la confirmation globale.',
                  style: TextStyle(color: AppColors.inkSoft),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _globalBusy ? null : _previewGlobal,
                  icon: _globalBusy
                      ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.manage_search_rounded),
                  label: const Text('Aperçu de toutes les superpositions'),
                ),
              ],
            ),
          ),
          if (_globalGuidance != null) ...[
            const SizedBox(height: 12),
            AppCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded, color: AppColors.info),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _globalGuidance!,
                      style: TextStyle(color: AppColors.inkSoft),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_globalPreviews.isNotEmpty) ...[
            const SizedBox(height: 12),
            _GlobalPreviewCard(
              previews: _globalPreviews,
              busy: _globalBusy,
              onApply: _applyGlobal,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _previewIndividual() async {
    final id = _selectedProfileId;
    if (id == null) return;
    setState(() => _busy = true);
    try {
      final preview = await _backend.previewOfficialRosterRecalculation(id);
      if (!mounted) return;
      setState(() => _preview = preview);
    } catch (e) {
      if (mounted) {
        final message = e.toString();
        _snack(message.contains('Aucune lecture R6 vérifiée')
            ? 'Analysez et validez d’abord le PDF officiel des Urgences en R6.'
            : 'Aperçu impossible : $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _applyIndividual() async {
    final id = _selectedProfileId;
    final preview = _preview;
    if (id == null || preview == null) return;
    final token = preview['preview_token']?.toString();
    if (token == null || token.isEmpty) {
      _snack('Jeton d’aperçu absent. Refaire l’aperçu.');
      return;
    }

    final accepted = await _confirmApply(
      title: 'Appliquer ce recalcul ?',
      message:
          'La couche personnelle de ce médecin sera reconstruite depuis la '
          'source officielle. Les protections des mois validés, mois passés '
          'et modifications manuelles restent actives.',
    );
    if (!accepted) return;

    setState(() => _busy = true);
    try {
      await _backend.applyOfficialRosterRecalculation(
        profileId: id,
        previewToken: token,
      );
      if (!mounted) return;
      await context.read<AppState>().refreshBackend();
      if (!mounted) return;
      _snack('Superposition recalculée et tracée.');
      await _previewIndividual();
    } catch (e) {
      if (mounted) _snack('Recalcul impossible : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _previewGlobal() async {
    final appState = context.read<AppState>();
    final doctors = _doctors(appState);
    setState(() {
      _globalBusy = true;
      _globalPreviews = const [];
      _globalGuidance = null;
    });

    // Do not produce an apparent 16-doctor "recalculation failure" when
    // no verified official R6 roster has ever been saved. This also prevents
    // accidental application of an empty source to historical calendars.
    try {
      final reports = await _backend.fetchOfficialRosterImportReports(limit: 1);
      if (!mounted) return;
      if (reports.isEmpty) {
        setState(() {
          _globalBusy = false;
          _globalGuidance =
              'Aucun planning Urgences vérifié par le moteur R6. '
              'Commencez par analyser et valider un PDF officiel dans '
              '« Vérification des imports ». Aucun calendrier n’a été modifié.';
        });
        return;
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _globalBusy = false;
        _globalGuidance =
            'Impossible de vérifier la source officielle R6 : $e';
      });
      return;
    }

    final previews = <Map<String, dynamic>>[];
    for (final doctor in doctors) {
      try {
        final preview =
            await _backend.previewOfficialRosterRecalculation(doctor.id);
        previews.add(preview);
      } catch (e) {
        previews.add({
          'profile_id': doctor.id,
          'profile_name': doctor.fullName,
          'hospital': doctor.hospital,
          'error': e.toString(),
          'added': const <dynamic>[],
          'modified': const <dynamic>[],
          'removed': const <dynamic>[],
          'unchanged': const <dynamic>[],
          'conflicts': const <dynamic>[],
        });
      }
      if (!mounted) return;
    }

    if (!mounted) return;
    setState(() {
      _globalPreviews = previews;
      _globalBusy = false;
    });
  }

  Future<void> _applyGlobal() async {
    final applicable = _globalPreviews.where((preview) {
      final token = preview['preview_token']?.toString();
      return token != null && token.isNotEmpty && preview['error'] == null;
    }).toList(growable: false);
    if (applicable.isEmpty) {
      _snack('Aucun aperçu applicable.');
      return;
    }

    final accepted = await _confirmApply(
      title: 'Recalculer toutes les superpositions ?',
      message:
          '${applicable.length} médecin(s) seront traités à partir des '
          'aperçus affichés. Si un aperçu a changé entre-temps, le serveur '
          'bloquera uniquement ce médecin et exigera un nouvel aperçu.',
    );
    if (!accepted) return;

    setState(() => _globalBusy = true);
    var applied = 0;
    final failures = <String>[];
    final resultItems = <Map<String, dynamic>>[];
    for (final preview in applicable) {
      final profileId = preview['profile_id']?.toString() ?? '';
      final token = preview['preview_token']?.toString() ?? '';
      if (profileId.isEmpty || token.isEmpty) continue;
      try {
        final result = await _backend.applyOfficialRosterRecalculation(
          profileId: profileId,
          previewToken: token,
        );
        applied++;
        resultItems.add({
          'profile_id': profileId,
          'profile_name': preview['profile_name'],
          'ok': true,
          'result': result,
        });
      } catch (e) {
        failures.add(
          '${preview['profile_name'] ?? profileId}: $e',
        );
        resultItems.add({
          'profile_id': profileId,
          'profile_name': preview['profile_name'],
          'ok': false,
          'error': e.toString(),
        });
      }
      if (!mounted) return;
    }

    try {
      await _backend.logGlobalOfficialRosterRecalculation(
        previews: applicable,
        result: {
          'applied_count': applied,
          'failure_count': failures.length,
          'items': resultItems,
          'source_unchanged': true,
        },
      );
    } catch (e) {
      failures.add('Traçabilité globale: $e');
    }

    try {
      await context.read<AppState>().refreshBackend();
    } catch (_) {
      // Le recalcul est serveur ; une erreur de rafraîchissement local
      // ne doit pas être confondue avec une erreur d'application.
    }
    if (!mounted) return;
    setState(() => _globalBusy = false);
    _snack(
      failures.isEmpty
          ? '$applied superposition(s) recalculée(s).'
          : '$applied recalculée(s) • ${failures.length} échec(s).',
    );
    await _previewGlobal();
  }

  Future<bool> _confirmApply({
    required String title,
    required String message,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Appliquer'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  final Map<String, dynamic> preview;
  final VoidCallback? onApply;

  const _PreviewCard({required this.preview, required this.onApply});

  @override
  Widget build(BuildContext context) {
    final added = _list(preview['added']);
    final modified = _list(preview['modified']);
    final removed = _list(preview['removed']);
    final unchanged = _list(preview['unchanged']);
    final conflicts = _list(preview['conflicts']);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            (preview['profile_name'] ?? 'Médecin').toString(),
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
          ),
          const SizedBox(height: 4),
          Text(
            (preview['hospital'] ?? '').toString(),
            style: TextStyle(color: AppColors.inkSoft),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _CountChip(
                label: 'Ajoutées',
                count: added.length,
                color: AppColors.success,
              ),
              _CountChip(
                label: 'Modifiées',
                count: modified.length,
                color: AppColors.warning,
              ),
              _CountChip(
                label: 'Retirées',
                count: removed.length,
                color: AppColors.danger,
              ),
              _CountChip(
                label: 'Inchangées',
                count: unchanged.length,
                color: AppColors.info,
              ),
              _CountChip(
                label: 'Conflits',
                count: conflicts.length,
                color: AppColors.violet,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _DiffSection(
            title: 'Gardes ajoutées',
            rows: added,
            color: AppColors.success,
          ),
          _DiffSection(
            title: 'Gardes modifiées',
            rows: modified,
            color: AppColors.warning,
          ),
          _DiffSection(
            title: 'Gardes retirées',
            rows: removed,
            color: AppColors.danger,
          ),
          _DiffSection(
            title: 'Conflits / protections',
            rows: conflicts,
            color: AppColors.violet,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onApply,
            icon: const Icon(Icons.check_circle_rounded),
            label: const Text('Valider et appliquer ce recalcul'),
          ),
        ],
      ),
    );
  }

  static List<Map<String, dynamic>> _list(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }
}

class _GlobalPreviewCard extends StatelessWidget {
  final List<Map<String, dynamic>> previews;
  final bool busy;
  final VoidCallback onApply;

  const _GlobalPreviewCard({
    required this.previews,
    required this.busy,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    int count(String key) => previews.fold<int>(
          0,
          (sum, preview) =>
              sum +
              (preview[key] is List ? (preview[key] as List).length : 0),
        );
    final errors = previews.where((preview) => preview['error'] != null).length;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Aperçu global',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _CountChip(
                label: 'Médecins',
                count: previews.length,
                color: AppColors.info,
              ),
              _CountChip(
                label: 'Ajouts',
                count: count('added'),
                color: AppColors.success,
              ),
              _CountChip(
                label: 'Modifications',
                count: count('modified'),
                color: AppColors.warning,
              ),
              _CountChip(
                label: 'Retraits',
                count: count('removed'),
                color: AppColors.danger,
              ),
              _CountChip(
                label: 'Conflits',
                count: count('conflicts'),
                color: AppColors.violet,
              ),
              if (errors > 0)
                _CountChip(
                  label: 'Erreurs aperçu',
                  count: errors,
                  color: AppColors.danger,
                ),
            ],
          ),
          const SizedBox(height: 12),
          ...previews.where((preview) => preview['error'] != null).map(
                (preview) => Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(
                    '${preview['profile_name']} : ${preview['error']}',
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: busy ? null : onApply,
            icon: busy
                ? const SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.layers_rounded),
            label: const Text('Valider et recalculer toutes les superpositions'),
          ),
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _CountChip({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(.11),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: color.withOpacity(.25)),
      ),
      child: Text(
        '$label: $count',
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _DiffSection extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> rows;
  final Color color;

  const _DiffSection({
    required this.title,
    required this.rows,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      leading: Icon(Icons.circle, size: 10, color: color),
      title: Text(
        '$title (${rows.length})',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      children: rows
          .map(
            (row) => ListTile(
              dense: true,
              contentPadding: const EdgeInsets.only(left: 22, right: 4),
              title: Text(
                (row['date_str'] ?? row['date'] ?? 'Date inconnue').toString(),
              ),
              subtitle: Text(
                [
                  if (row['current_shift_id'] != null)
                    'Actuel: ${row['current_shift_id']}',
                  if (row['shift_id'] != null)
                    'Officiel: ${row['shift_id']}',
                  if (row['month_status'] != null)
                    'Mois: ${row['month_status']}',
                ].join(' • '),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}
