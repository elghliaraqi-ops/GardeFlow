import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_user.dart';
import '../services/supabase_backend_service.dart';
import '../services/official_roster_identity_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/screen_decor.dart';
import '../theme/widgets.dart';
import 'official_planning_screen.dart';

class AdminOfficialRosterReviewScreen extends StatefulWidget {
  const AdminOfficialRosterReviewScreen({super.key});

  @override
  State<AdminOfficialRosterReviewScreen> createState() =>
      _AdminOfficialRosterReviewScreenState();
}

class _AdminOfficialRosterReviewScreenState
    extends State<AdminOfficialRosterReviewScreen> {
  final _backend = SupabaseBackendService.instance;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _reports = const [];
  List<Map<String, dynamic>> _guards = const [];
  List<Map<String, dynamic>> _anomalies = const [];
  List<Map<String, dynamic>> _links = const [];
  String? _selectedReportId;

  Map<String, dynamic>? get _selectedReport {
    final id = _selectedReportId;
    if (id == null) return null;
    for (final report in _reports) {
      if (report['id']?.toString() == id) return report;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload({String? reportId}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final reports = await _backend.fetchOfficialRosterImportReports();
      final links = await _backend.fetchOfficialRosterIdentityLinkRows();
      final selected = reportId ??
          _selectedReportId ??
          (reports.isEmpty ? null : reports.first['id']?.toString());

      var guards = const <Map<String, dynamic>>[];
      var anomalies = const <Map<String, dynamic>>[];
      if (selected != null) {
        guards = await _backend.fetchOfficialRosterGuards(reportId: selected);
        anomalies =
            await _backend.fetchOfficialRosterAnomalies(reportId: selected);
      }

      if (!mounted) return;
      setState(() {
        _reports = reports;
        _links = links;
        _selectedReportId = selected;
        _guards = guards;
        _anomalies = anomalies;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DecorScaffold(
      scene: ScreenDecorScene.admin,
      appBar: AppBar(
        title: const GardeFlowTitle('Vérification des imports'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _loading ? null : _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _reload)
              : _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_reports.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.picture_as_pdf_rounded, size: 40),
              const SizedBox(height: 12),
              const Text(
                'Aucune lecture officielle R6 validée. '
                'Vous pouvez relire les PDF Urgences déjà publiés, '
                'sans les remplacer ni modifier les calendriers.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const OfficialPlanningScreen(),
                  ),
                ).then((_) => _reload()),
                icon: const Icon(Icons.fact_check_rounded),
                label: const Text('Relire les PDF existants avec R6'),
              ),
            ],
          ),
        ),
      );
    }

    final report = _selectedReport!;
    final problemGuards = _guards
        .where(
          (guard) =>
              guard['match_status'] != 'matched' ||
              ((guard['confidence'] as num?)?.toDouble() ?? 0) < .95,
        )
        .toList(growable: false);
    final activeProfiles = context.watch<AppState>().users
        .where((profile) => profile.accountStatus == AccountStatus.active)
        .toList(growable: false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      children: [
        const DecorSectionBanner(
          scene: ScreenDecorScene.admin,
          title: 'Lecture officielle contrôlée',
          subtitle:
              'VERT = A/B concordants. ORANGE = arbitrage C ou correction tracée. '
              'Les gardes non inscrites restent dans la source officielle.',
          icon: Icons.fact_check_rounded,
        ),
        const SizedBox(height: 16),
        AppCard(
          child: DropdownButtonFormField<String>(
            value: _selectedReportId,
            decoration: const InputDecoration(
              labelText: 'Rapport d’import',
              prefixIcon: Icon(Icons.picture_as_pdf_rounded),
            ),
            items: _reports
                .map(
                  (item) => DropdownMenuItem<String>(
                    value: item['id']?.toString(),
                    child: Text(
                      '${item['file_name'] ?? 'Planning'} • '
                      '${(item['status'] ?? '').toString().toUpperCase()}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) {
              if (value != null && value != _selectedReportId) {
                _reload(reportId: value);
              }
            },
          ),
        ),
        const SizedBox(height: 12),
        _ReportSummary(report: report),
        const SizedBox(height: 18),
        _SectionHeader(
          title: 'À vérifier',
          subtitle:
              '${problemGuards.length} garde(s) nécessitant une attention ciblée',
          icon: Icons.manage_search_rounded,
        ),
        const SizedBox(height: 10),
        if (problemGuards.isEmpty)
          const _InfoCard(
            icon: Icons.verified_rounded,
            title: 'Aucune identité à revoir',
            text:
                'Toutes les gardes de ce rapport sont associées de manière sûre.',
            color: AppColors.success,
          )
        else
          ...problemGuards.map(
            (guard) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _GuardReviewCard(
                guard: guard,
                candidates: _candidateLabels(guard, activeProfiles),
                onLink: () => _linkGuard(guard),
                onCorrect: () => _correctGuard(guard),
              ),
            ),
          ),
        const SizedBox(height: 14),
        _SectionHeader(
          title: 'Conflits A/B/C',
          subtitle:
              '${_anomalies.length} conflit(s) ou zone(s) arbitrée(s) conservé(s) dans la traçabilité',
          icon: Icons.compare_arrows_rounded,
        ),
        const SizedBox(height: 10),
        if (_anomalies.isEmpty)
          const _InfoCard(
            icon: Icons.done_all_rounded,
            title: 'Aucun conflit enregistré',
            text: 'La lecture ne contient pas de désaccord conservé.',
            color: AppColors.success,
          )
        else
          ..._anomalies.map(
            (anomaly) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _AnomalyCard(anomaly: anomaly),
            ),
          ),
        const SizedBox(height: 14),
        _SectionHeader(
          title: 'Liaisons persistantes',
          subtitle:
              '${_links.length} identité(s) officielle(s) liée(s) à un compte GardeFlow',
          icon: Icons.link_rounded,
        ),
        const SizedBox(height: 10),
        if (_links.isEmpty)
          const _InfoCard(
            icon: Icons.link_off_rounded,
            title: 'Aucune liaison manuelle',
            text:
                'Les correspondances exactes continuent à fonctionner sans créer de liaison artificielle.',
            color: AppColors.info,
          )
        else
          ..._links.map(
            (link) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                child: Row(
                  children: [
                    const Icon(Icons.link_rounded, color: AppColors.info),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (link['official_full_name'] ?? '').toString(),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            (link['hospital'] ?? '').toString(),
                            style: TextStyle(
                              color: AppColors.inkSoft,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Supprimer la liaison',
                      onPressed: () => _unlink(link),
                      icon: const Icon(
                        Icons.link_off_rounded,
                        color: AppColors.danger,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  List<String> _candidateLabels(
    Map<String, dynamic> guard,
    List<AppUser> profiles,
  ) {
    final hospital = (guard['hospital'] ?? '').toString();
    final sameHospital = profiles
        .where((profile) => profile.hospital == hospital)
        .toList(growable: false);
    final resolution = OfficialRosterIdentityService.resolve(
      firstName: (guard['first_name'] ?? '').toString(),
      lastName: (guard['last_name'] ?? '').toString(),
      profiles: sameHospital,
    );
    return resolution.suggestions
        .take(3)
        .map(
          (candidate) =>
              '${candidate.profile.fullName} • '
              '${candidate.exact ? 'exact' : '${(candidate.score * 100).round()} %'}',
        )
        .toList(growable: false);
  }

  Future<void> _linkGuard(Map<String, dynamic> guard) async {
    final appState = context.read<AppState>();
    final hospital = (guard['hospital'] ?? '').toString();
    final profiles = appState.users
        .where(
          (user) =>
              user.accountStatus == AccountStatus.active &&
              user.hospital == hospital,
        )
        .toList(growable: false)
      ..sort(
        (a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
      );
    if (profiles.isEmpty) {
      _snack('Aucun compte actif dans cet établissement.');
      return;
    }

    final resolution = OfficialRosterIdentityService.resolve(
      firstName: (guard['first_name'] ?? '').toString(),
      lastName: (guard['last_name'] ?? '').toString(),
      profiles: profiles,
    );
    String? selectedId = resolution.profileId;
    if (selectedId == null && resolution.suggestions.length == 1) {
      selectedId = resolution.suggestions.single.profile.id;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('Associer au compte GardeFlow'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (guard['full_name'] ?? '').toString(),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  'Cette action crée une liaison persistante et tracée.',
                  style: TextStyle(color: AppColors.inkSoft),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Compte médecin',
                  ),
                  items: profiles
                      .map(
                        (profile) => DropdownMenuItem(
                          value: profile.id,
                          child: Text(
                            '${profile.fullName} • ${profile.service}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) =>
                      setLocalState(() => selectedId = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: selectedId == null
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: const Text('Confirmer la liaison'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || selectedId == null) return;

    try {
      await _backend.setOfficialRosterIdentityLink(
        hospital: hospital,
        firstName: (guard['first_name'] ?? '').toString(),
        lastName: (guard['last_name'] ?? '').toString(),
        fullName: (guard['full_name'] ?? '').toString(),
        profileId: selectedId!,
        reason: 'Association confirmée depuis la console administrateur R6',
      );
      if (!mounted) return;
      _snack('Liaison enregistrée. Les imports futurs la réutiliseront.');
      await _reload(reportId: _selectedReportId);
    } catch (e) {
      if (mounted) _snack('Association impossible : $e');
    }
  }

  Future<void> _unlink(Map<String, dynamic> link) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer cette liaison ?'),
        content: Text(
          'Les gardes officielles resteront présentes, mais elles ne seront '
          'plus rattachées automatiquement au compte.',
        ),
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
    if (accepted != true) return;
    try {
      await _backend.deleteOfficialRosterIdentityLink(
        linkId: link['id'].toString(),
        reason: 'Liaison retirée depuis la console administrateur R6',
      );
      await _reload(reportId: _selectedReportId);
    } catch (e) {
      if (mounted) _snack('Suppression impossible : $e');
    }
  }

  Future<void> _correctGuard(Map<String, dynamic> guard) async {
    final date = TextEditingController(text: (guard['date_str'] ?? '').toString());
    final first =
        TextEditingController(text: (guard['first_name'] ?? '').toString());
    final last =
        TextEditingController(text: (guard['last_name'] ?? '').toString());
    final full =
        TextEditingController(text: (guard['full_name'] ?? '').toString());
    final reason = TextEditingController();
    var shift = (guard['shift_id'] ?? 'urg-jour').toString();

    final patch = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('Corriger uniquement cette garde'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: date,
                    decoration: const InputDecoration(
                      labelText: 'Date YYYY-MM-DD',
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: shift,
                    decoration: const InputDecoration(labelText: 'Créneau'),
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
                      if (value != null) setLocalState(() => shift = value);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: first,
                    decoration: const InputDecoration(labelText: 'Prénom'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: last,
                    decoration: const InputDecoration(labelText: 'Nom'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: full,
                    decoration: const InputDecoration(
                      labelText: 'Nom complet tel que validé',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: reason,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Motif obligatoire',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                if (first.text.trim().isEmpty ||
                    last.text.trim().isEmpty ||
                    reason.text.trim().isEmpty) {
                  return;
                }
                Navigator.pop(dialogContext, {
                  'patch': {
                    'date': date.text.trim(),
                    'shift_id': shift,
                    'first_name': first.text.trim(),
                    'last_name': last.text.trim(),
                    'full_name': full.text.trim(),
                  },
                  'reason': reason.text.trim(),
                });
              },
              child: const Text('Enregistrer la correction'),
            ),
          ],
        ),
      ),
    );

    date.dispose();
    first.dispose();
    last.dispose();
    full.dispose();
    reason.dispose();
    if (patch == null) return;

    try {
      await _backend.correctOfficialRosterGuard(
        guardId: guard['id'].toString(),
        patch: Map<String, dynamic>.from(patch['patch'] as Map),
        reason: patch['reason'].toString(),
      );
      if (!mounted) return;
      _snack('Correction tracée. Vérifiez ensuite la liaison au compte.');
      await _reload(reportId: _selectedReportId);
    } catch (e) {
      if (mounted) _snack('Correction impossible : $e');
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _ReportSummary extends StatelessWidget {
  final Map<String, dynamic> report;
  const _ReportSummary({required this.report});

  @override
  Widget build(BuildContext context) {
    final status = (report['status'] ?? 'red').toString().toLowerCase();
    final confidence =
        ((report['confidence'] as num?)?.toDouble() ?? 0) * 100;
    final color = status == 'green'
        ? AppColors.success
        : status == 'orange'
            ? AppColors.warning
            : AppColors.danger;

    final items = <(String, String)>[
      ('Statut', status.toUpperCase()),
      ('Confiance', '${confidence.toStringAsFixed(1)} %'),
      ('Gardes', '${report['total_guards'] ?? 0}'),
      ('Médecins', '${report['doctor_count'] ?? 0}'),
      ('Inscrits', '${report['registered_doctors'] ?? 0}'),
      ('Non inscrits', '${report['unregistered_doctors'] ?? 0}'),
      ('Ambigus', '${report['ambiguous_matches'] ?? 0}'),
      ('Conflits A/B', '${report['ab_difference_count'] ?? 0}'),
    ];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withOpacity(.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .3,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  (report['file_name'] ?? '').toString(),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: items
                .map(
                  (item) => Container(
                    width: 145,
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: AppColors.paperAlt,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.$1,
                          style: TextStyle(
                            color: AppColors.inkSoft,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item.$2,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}

class _GuardReviewCard extends StatelessWidget {
  final Map<String, dynamic> guard;
  final List<String> candidates;
  final VoidCallback onLink;
  final VoidCallback onCorrect;

  const _GuardReviewCard({
    required this.guard,
    required this.candidates,
    required this.onLink,
    required this.onCorrect,
  });

  @override
  Widget build(BuildContext context) {
    final status = (guard['match_status'] ?? '').toString();
    final confidence =
        ((guard['confidence'] as num?)?.toDouble() ?? 0) * 100;
    final color = status == 'matched'
        ? AppColors.success
        : status == 'ambiguous'
            ? AppColors.danger
            : AppColors.warning;
    final label = switch (status) {
      'matched' => 'Compte associé',
      'ambiguous' => 'Correspondance ambiguë',
      'manual_review' => 'Validation admin requise',
      _ => 'Médecin non inscrit',
    };

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person_search_rounded, color: color),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  (guard['full_name'] ?? '').toString(),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                '${confidence.toStringAsFixed(1)} %',
                style: TextStyle(
                  color: confidence >= 95
                      ? AppColors.success
                      : AppColors.warning,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${guard['date_str']} • ${guard['shift_id']} • '
            'page ${guard['page_number'] ?? '—'}',
            style: TextStyle(color: AppColors.inkSoft),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
          if ((guard['zone'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              'Zone : ${guard['zone']}',
              style: TextStyle(color: AppColors.inkFaint, fontSize: 12),
            ),
          ],
          if (status != 'matched' && candidates.isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(
              'Compte(s) potentiel(s) : ${candidates.join(' • ')}',
              style: const TextStyle(
                color: AppColors.warning,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onCorrect,
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: const Text('Corriger cette garde'),
              ),
              if (status != 'matched')
                FilledButton.icon(
                  onPressed: onLink,
                  icon: const Icon(Icons.link_rounded, size: 18),
                  label: const Text('Associer à un compte'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AnomalyCard extends StatelessWidget {
  final Map<String, dynamic> anomaly;
  const _AnomalyCard({required this.anomaly});

  @override
  Widget build(BuildContext context) {
    final status = (anomaly['status'] ?? '').toString();
    final resolved = status.startsWith('resolved');
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 8),
        leading: Icon(
          resolved ? Icons.auto_fix_high_rounded : Icons.error_outline_rounded,
          color: resolved ? AppColors.warning : AppColors.danger,
        ),
        title: Text(
          (anomaly['message'] ?? 'Désaccord de lecture').toString(),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${anomaly['date_str'] ?? 'Date non déterminée'} • '
          '${anomaly['shift_id'] ?? 'zone structurelle'} • '
          'page ${anomaly['page_number'] ?? '—'}',
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Zone : ${anomaly['zone'] ?? '—'}',
              style: TextStyle(color: AppColors.inkSoft),
            ),
          ),
          const SizedBox(height: 8),
          _ReadPayload(label: 'Lecture A', value: anomaly['read_a']),
          _ReadPayload(label: 'Lecture B', value: anomaly['read_b']),
          if (anomaly['read_c'] != null)
            _ReadPayload(label: 'Lecture C', value: anomaly['read_c']),
        ],
      ),
    );
  }
}

class _ReadPayload extends StatelessWidget {
  final String label;
  final dynamic value;
  const _ReadPayload({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final text = const JsonEncoder.withIndent('  ').convert(value ?? {});
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.paperAlt,
          borderRadius: BorderRadius.circular(12),
        ),
        child: SelectableText(
          '$label\n$text',
          style: TextStyle(
            color: AppColors.inkSoft,
            fontFamily: 'monospace',
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.warning),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(color: AppColors.inkSoft, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  final Color color;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(text, style: TextStyle(color: AppColors.inkSoft)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function({String? reportId}) onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: AppCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: AppColors.danger,
                size: 36,
              ),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () => onRetry(),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
