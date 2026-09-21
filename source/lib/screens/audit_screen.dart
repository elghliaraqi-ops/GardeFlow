import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/audit_event.dart';
import '../services/supabase_backend_service.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';

class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key});

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  late Future<List<AuditEvent>> _future;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _future = SupabaseBackendService.instance.fetchAudit();
  }

  void _refresh() {
    setState(() {
      _future = SupabaseBackendService.instance.fetchAudit();
    });
  }

  Future<void> _clearAudit() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('Nettoyer l’historique ?'),
        content: const Text(
          'Cette action supprime définitivement les anciennes entrées du journal administratif. Elle ne modifie ni les gardes, ni les comptes, ni les plannings.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Annuler')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_sweep_rounded),
            label: const Text('Nettoyer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final count = await SupabaseBackendService.instance.clearAuditLog();
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$count entrée${count > 1 ? 's' : ''} supprimée${count > 1 ? 's' : ''}.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Nettoyage impossible : $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: GardeFlowTitle('Journal des actions'),
        actions: [
          SoftIconButton(
            icon: Icons.delete_sweep_outlined,
            onTap: _clearAudit,
            tooltip: 'Nettoyer l’historique',
          ),
          SizedBox(width: 4),
          SoftIconButton(
            icon: Icons.refresh_rounded,
            onTap: _refresh,
            tooltip: 'Actualiser',
          ),
          SizedBox(width: 6),
        ],
      ),
      body: FutureBuilder<List<AuditEvent>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _AuditErrorState(
              message: 'Impossible de charger le journal.',
              onRetry: _refresh,
            );
          }

          final allEvents = snapshot.data ?? const <AuditEvent>[];
          if (allEvents.isEmpty) {
            return const _AuditEmptyState();
          }

          final events = allEvents
              .where((event) =>
                  _filter == 'all' || _actionCategory(event.action) == _filter)
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

          return Column(
            children: [
              _AuditOverview(
                total: allEvents.length,
                selectedFilter: _filter,
                onFilterChanged: (value) {
                  setState(() => _filter = value);
                },
              ),
              Expanded(
                child: events.isEmpty
                    ? const _FilteredEmptyState()
                    : _AuditTimeline(events: events),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AuditOverview extends StatelessWidget {
  final int total;
  final String selectedFilter;
  final ValueChanged<String> onFilterChanged;

  const _AuditOverview({
    required this.total,
    required this.selectedFilter,
    required this.onFilterChanged,
  });

  static const _filters = <_AuditFilter>[
    _AuditFilter('all', 'Tout', Icons.history_rounded),
    _AuditFilter('planning', 'Planning', Icons.calendar_month_rounded),
    _AuditFilter('exchange', 'Échanges', Icons.swap_horiz_rounded),
    _AuditFilter('leave', 'Congés', Icons.event_available_rounded),
    _AuditFilter('account', 'Comptes', Icons.person_outline_rounded),
  ];

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('$total actions enregistrées', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 12),
      SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
        for (final filter in _filters) Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(
          avatar: Icon(filter.icon, size: 18), label: Text(filter.label),
          selected: selectedFilter == filter.id,
          onSelected: (_) => onFilterChanged(filter.id),
        )),
      ])),
    ]),
  );
}

class _AuditTimeline extends StatelessWidget {
  final List<AuditEvent> events;

  const _AuditTimeline({required this.events});

  @override
  Widget build(BuildContext context) {
    final rows = <_AuditRow>[];
    String? lastDayKey;

    for (final event in events) {
      final local = event.createdAt.toLocal();
      final key = DateFormat('yyyy-MM-dd').format(local);
      if (key != lastDayKey) {
        rows.add(_AuditRow.header(_dayLabel(local)));
        lastDayKey = key;
      }
      rows.add(_AuditRow.event(event));
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 11, 16, 28),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        if (row.header != null) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
              2,
              index == 0 ? 2 : 8,
              2,
              8,
            ),
            child: Text(
              row.header!,
              style: TextStyle(
                color: AppColors.inkSoft,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.35,
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _AuditEventCard(event: row.event!),
        );
      },
    );
  }

  static String _dayLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final difference = today.difference(day).inDays;

    if (difference == 0) return 'AUJOURD’HUI';
    if (difference == 1) return 'HIER';

    final raw = DateFormat('EEEE d MMMM yyyy', 'fr_FR').format(date);
    return raw.toUpperCase();
  }
}

class _AuditEventCard extends StatelessWidget {
  final AuditEvent event;

  const _AuditEventCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final look = _actionLook(event.action);
    final subject = (event.subjectName ?? '').trim();
    final actor = event.actorName.trim().isEmpty ? 'Système' : event.actorName.trim();
    final reason = (event.reason ?? '').trim();
    return AppCard(padding: const EdgeInsets.all(16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(look.icon, color: Theme.of(context).colorScheme.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Text(_actionLabel(event.action), style: Theme.of(context).textTheme.titleMedium)),
        ]),
        const SizedBox(height: 8),
        Text(_categoryLabel(_actionCategory(event.action)), style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 16),
        if (subject.isNotEmpty) ...[
          _AuditDetailRow(icon: Icons.person_outline_rounded, label: 'Concerné', value: subject),
          const SizedBox(height: 12),
        ],
        _AuditDetailRow(icon: Icons.shield_outlined, label: 'Effectué par', value: actor),
        if (reason.isNotEmpty) ...[
          const SizedBox(height: 12),
          _AuditDetailRow(icon: Icons.notes_rounded, label: 'Motif', value: reason),
        ],
        const SizedBox(height: 16),
        Text(DateFormat('dd MMM yyyy · HH:mm', 'fr_FR').format(event.createdAt.toLocal()),
          style: Theme.of(context).textTheme.bodySmall),
      ],
    ));
  }
}

class _AuditDetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _AuditDetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
    const SizedBox(width: 10),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(height: 3),
      Text(value, style: Theme.of(context).textTheme.bodyMedium),
    ])),
  ]);
}

class _AuditErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _AuditErrorState({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 44,
              color: AppColors.danger,
            ),
            SizedBox(height: AppSpace.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.inkSoft,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: AppSpace.md),
            FilledButton.icon(
              onPressed: onRetry,
              icon: Icon(Icons.refresh_rounded),
              label: Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuditEmptyState extends StatelessWidget {
  const _AuditEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.history_rounded,
            size: 40,
            color: AppColors.inkFaint,
          ),
          SizedBox(height: 10),
          Text(
            'Aucune action enregistrée.',
            style: TextStyle(
              color: AppColors.inkSoft,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilteredEmptyState extends StatelessWidget {
  const _FilteredEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Aucune action dans cette catégorie.',
        style: TextStyle(
          color: AppColors.inkSoft,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _AuditFilter {
  final String id;
  final String label;
  final IconData icon;

  const _AuditFilter(this.id, this.label, this.icon);
}

class _AuditRow {
  final String? header;
  final AuditEvent? event;

  const _AuditRow._({
    this.header,
    this.event,
  });

  factory _AuditRow.header(String value) => _AuditRow._(header: value);
  factory _AuditRow.event(AuditEvent value) => _AuditRow._(event: value);
}

class _ActionLook {
  final IconData icon;
  final Color background;
  final Color foreground;

  const _ActionLook(
    this.icon,
    this.background,
    this.foreground,
  );
}

_ActionLook _actionLook(String action) {
  if (action == 'planning_month.finalized') {
    return _ActionLook(
      Icons.verified_outlined,
      AppColors.success.withOpacity(0.12),
      AppColors.success,
    );
  }

  if (action == 'planning_month.reopened') {
    return _ActionLook(
      Icons.lock_open_rounded,
      AppColors.brandSoft,
      AppColors.brand,
    );
  }

  if (action.endsWith('.approved') || action.endsWith('.accepted')) {
    return _ActionLook(
      Icons.check_circle_outline_rounded,
      AppColors.success.withOpacity(0.12),
      AppColors.success,
    );
  }

  if (action.endsWith('.rejected') ||
      action.endsWith('.declined') ||
      action.endsWith('.deleted') ||
      action.endsWith('.suspended') ||
      action.endsWith('.cancelled')) {
    return _ActionLook(
      Icons.cancel_outlined,
      AppColors.danger.withOpacity(0.10),
      AppColors.danger,
    );
  }

  if (_actionCategory(action) == 'planning') {
    return _ActionLook(
      Icons.calendar_month_rounded,
      AppColors.brandSoft,
      AppColors.brand,
    );
  }

  if (_actionCategory(action) == 'exchange') {
    return _ActionLook(
      Icons.swap_horiz_rounded,
      AppColors.brandSoft,
      AppColors.brand,
    );
  }

  if (_actionCategory(action) == 'leave') {
    return _ActionLook(
      Icons.event_available_rounded,
      AppColors.brandSoft,
      AppColors.brand,
    );
  }

  if (_actionCategory(action) == 'account') {
    return _ActionLook(
      Icons.person_outline_rounded,
      AppColors.paperAlt,
      AppColors.inkSoft,
    );
  }

  return _ActionLook(
    Icons.history_rounded,
    AppColors.paperAlt,
    AppColors.inkSoft,
  );
}

String _actionCategory(String action) {
  if (action.startsWith('planning.') ||
      action.startsWith('planning_month.')) {
    return 'planning';
  }
  if (action.startsWith('exchange.')) return 'exchange';
  if (action.startsWith('leave.')) return 'leave';
  if (action.startsWith('account.')) return 'account';
  return 'other';
}

String _categoryLabel(String category) {
  switch (category) {
    case 'planning':
      return 'PLANNING';
    case 'exchange':
      return 'ÉCHANGE';
    case 'leave':
      return 'CONGÉ';
    case 'account':
      return 'COMPTE';
    default:
      return 'ACTION';
  }
}

String _actionLabel(String action) {
  switch (action) {
    case 'planning_month.finalized':
      return 'Calendrier mensuel validé';
    case 'planning_month.reopened':
      return 'Calendrier rouvert';
    case 'planning.assigned':
      return 'Garde affectée ou modifiée';
    case 'planning.deleted':
      return 'Affectation supprimée';
    case 'exchange.created':
      return 'Demande d’échange créée';
    case 'exchange.accepted':
      return 'Échange accepté par le destinataire';
    case 'exchange.declined':
      return 'Échange refusé par le destinataire';
    case 'exchange.approved':
      return 'Échange ou transfert validé';
    case 'exchange.rejected':
      return 'Échange ou transfert refusé';
    case 'exchange.cancelled':
      return 'Demande d’échange annulée';
    case 'leave.created':
      return 'Demande de congé créée';
    case 'leave.approved':
      return 'Congé validé';
    case 'leave.rejected':
      return 'Congé refusé';
    case 'leave.cancelled':
      return 'Demande de congé annulée';
    case 'account.approved':
      return 'Compte médecin validé';
    case 'account.suspended':
      return 'Compte médecin suspendu';
    case 'account.deleted':
      return 'Compte médecin supprimé';
    default:
      return _fallbackActionLabel(action);
  }
}

String _fallbackActionLabel(String action) {
  final clean = action
      .replaceAll('.', ' ')
      .replaceAll('_', ' ')
      .trim();

  if (clean.isEmpty) return 'Action administrative';

  final words = clean
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();

  if (words.isEmpty) return 'Action administrative';

  final text = words.join(' ');
  return '${text[0].toUpperCase()}${text.substring(1)}';
}
