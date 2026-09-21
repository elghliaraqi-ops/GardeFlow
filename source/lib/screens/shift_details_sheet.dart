import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../data/hospitals.dart';
import '../models/leave_request.dart';
import '../models/planning_month.dart';
import '../models/shift_type.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../ui/components.dart';
import '../ui/planning_access.dart';
import 'exchange_request_sheet.dart';

class ShiftDetailsSheet extends StatefulWidget {
  final DateTime date;
  const ShiftDetailsSheet({super.key, required this.date});
  @override
  State<ShiftDetailsSheet> createState() => _ShiftDetailsSheetState();
}
class _ShiftDetailsSheetState extends State<ShiftDetailsSheet> {
  bool _busy = false;
  String? _error;
  Future<void> _run(Future<String?> Function() action) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      final error = await action();
      if (!mounted) return;
      if (error == null) { Navigator.pop(context); return; }
      setState(() => _error = error);
    } catch (_) {
      if (mounted) setState(() => _error = 'La modification n’a pas abouti. Réessayez.');
    } finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final key = AppState.dateKey(widget.date);
    final entry = state.myEntryForDate(key);
    final me = state.currentUser;
    final shift = entry == null ? null : ShiftCatalog.byId(entry.shiftId);
    final reason = planningEditReason(state, widget.date, entry);
    final exchangeReason = entry == null ? null : exchangeDisabledReason(state, entry);
    final record = state.myPlanningMonth(widget.date);
    final pendingLeave = entry != null && state.leaveRequestForEntry(entry)?.status == LeaveRequestStatus.pendingAdmin;
    return SafeArea(top: false, child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(DateFormat('EEEE d MMMM yyyy', 'fr_FR').format(widget.date), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 20),
        if (shift != null) ...[
          Wrap(spacing: 8, runSpacing: 8, children: [ShiftBadge(shift: shift),
            StatusBadge(status: record?.status ?? PlanningMonthStatus.draft, reopened: record?.rejectionReason?.trim().isNotEmpty ?? false),
            if (entry!.isDisciplinary) const DisciplinaryBadge(),
          ]),
          const SizedBox(height: 20),
          if (shift.hasSchedule) Text('${shift.start} → ${shift.end}${shift.end == '08:00' ? ' (+1 j)' : ''}', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(shift.id.startsWith('urg-') ? 'Urgences' : shift.id == 'conge' ? 'Congé${pendingLeave ? ' · en attente de validation' : ''}' : me?.service ?? 'Service'),
          if (me != null) Text(hospitalDisplayName(me.hospital), style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 24),
        ] else ...[
          Text('Aucune garde prévue', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
        ],
        if (reason == null) ...[
          Text(shift == null ? 'Choisir une tuile' : 'Remplacer la tuile', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ShiftPalette(date: widget.date, enabled: !_busy, onSelect: (id) => _run(() => state.placeShift(key, id))),
          if (entry != null) ...[
            const SizedBox(height: 12),
            SecondaryButton(label: 'Retirer cette garde', onPressed: _busy ? null : () => _run(() => state.removeShift(entry.id))),
          ],
        ] else Text(reason, style: Theme.of(context).textTheme.bodyMedium),
        if (entry != null && shift!.hasSchedule) ...[
          const SizedBox(height: 20),
          PrimaryButton(label: 'Proposer un échange', icon: Icons.swap_horiz_rounded,
            onPressed: exchangeReason != null || _busy ? null : () => _openRequest(true)),
          const SizedBox(height: 10),
          SecondaryButton(label: 'Transférer cette garde', onPressed: exchangeReason != null || _busy ? null : () => _openRequest(false)),
          if (exchangeReason != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(exchangeReason, style: Theme.of(context).textTheme.bodySmall)),
        ],
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      ]),
    ));
  }
  void _openRequest(bool exchange) {
    final state = context.read<AppState>();
    final entry = state.myEntryForDate(AppState.dateKey(widget.date));
    if (entry == null || exchangeDisabledReason(state, entry) != null) return;
    // Replace sheet content with a route; all request validation stays in AppState.
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => Scaffold(
      appBar: AppBar(title: Text(exchange ? 'Proposer un échange' : 'Transférer une garde')),
      body: ExchangeRequestSheet(dateStr: entry.dateStr, entry: entry, initialExchange: exchange),
    )));
  }
}

class ShiftPalette extends StatelessWidget {
  final DateTime? date;
  final bool enabled;
  final ValueChanged<String>? onSelect;
  const ShiftPalette({super.key, this.date, this.enabled = true, this.onSelect});
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final group in [
        ('Service', [ShiftCatalog.serviceJour, ShiftCatalog.serviceNuit, ShiftCatalog.service24h]),
        ('Urgences', [ShiftCatalog.urgJour, ShiftCatalog.urgNuit, ShiftCatalog.urg24h]),
      ]) ...[
        Padding(padding: const EdgeInsets.only(top: 8, bottom: 8), child: Text(group.$1, style: Theme.of(context).textTheme.labelLarge)),
        LayoutBuilder(builder: (context, box) {
          final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
          final columns = box.maxWidth < 290 && scale > 1.4 ? 2 : 3;
          return Wrap(spacing: 8, runSpacing: 8, children: [
            for (final shift in group.$2) SizedBox(width: (box.maxWidth - 8 * (columns - 1)) / columns,
              child: _PaletteTile(shift: shift, enabled: enabled && (date == null || !shiftHasStarted(date!, shift)), onSelect: onSelect)),
          ]);
        }),
      ],
      const SizedBox(height: 12),
      _PaletteTile(shift: ShiftCatalog.conge, enabled: enabled, onSelect: onSelect),
    ]);
  }
}
class _PaletteTile extends StatelessWidget {
  final ShiftType shift;
  final bool enabled;
  final ValueChanged<String>? onSelect;
  const _PaletteTile({required this.shift, required this.enabled, this.onSelect});
  @override
  Widget build(BuildContext context) {
    final v = ShiftVisual.of(context, shift);
    final tile = Semantics(button: true, enabled: enabled, label: '${v.category} ${shift.label}, ${shift.start ?? ''} ${shift.end ?? ''}',
      child: Material(color: enabled ? v.background : Theme.of(context).colorScheme.surfaceContainerHigh, borderRadius: AppRadius.smR,
        child: InkWell(onTap: enabled && onSelect != null ? () => onSelect!(shift.id) : null, borderRadius: AppRadius.smR,
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12), child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(shift.icon, color: enabled ? v.foreground : Theme.of(context).colorScheme.onSurfaceVariant, size: 22),
            const SizedBox(height: 6),
            Text(shift.label, style: TextStyle(fontWeight: FontWeight.w600, color: enabled ? v.foreground : Theme.of(context).colorScheme.onSurfaceVariant)),
            if (shift.hasSchedule) Text('${shift.start}–${shift.end}', textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: enabled ? v.foreground : Theme.of(context).colorScheme.onSurfaceVariant)),
          ])),
        ),
      ));
    return Draggable<String>(data: shift.id, maxSimultaneousDrags: enabled ? 1 : 0,
      feedback: Material(color: Colors.transparent, child: SizedBox(width: 110, child: tile)),
      childWhenDragging: Opacity(opacity: .4, child: tile), child: tile);
  }
}
