import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/planning_entry.dart';
import '../models/shift_type.dart';
import '../theme/app_theme.dart';
import '../ui/components.dart';

/// Presentation-only calendar shared by the personal and administrative views.
class PlanningCalendar extends StatelessWidget {
  final DateTime month;
  final Map<String, PlanningEntry> entries;
  final ValueChanged<DateTime> onDayTap;
  final bool Function(DateTime, String)? canDrop;
  final void Function(DateTime, String)? onDrop;
  final String? selectedDate;
  const PlanningCalendar({super.key, required this.month, required this.entries,
    required this.onDayTap, this.canDrop, this.onDrop, this.selectedDate});
  static String dateKey(DateTime date) => DateFormat('yyyy-MM-dd').format(date);
  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month).weekday - 1;
    final days = DateTime(month.year, month.month + 1, 0).day;
    final c = Theme.of(context).colorScheme;
    final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
    return Column(children: [
      Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Row(children: [
        for (final day in ['L', 'M', 'M', 'J', 'V', 'S', 'D'])
          Expanded(child: Text(day, textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelMedium)),
      ])),
      GridView.builder(
        shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), padding: EdgeInsets.zero,
        itemCount: ((first + days) / 7).ceil() * 7,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7,
          crossAxisSpacing: 2, mainAxisSpacing: 4, mainAxisExtent: math.max(66.0, 54 * scale)),
        itemBuilder: (context, index) {
          final day = index - first + 1;
          if (day < 1 || day > days) return const SizedBox.shrink();
          final date = DateTime(month.year, month.month, day);
          final key = dateKey(date);
          final entry = entries[key];
          final shift = entry == null ? null : ShiftCatalog.byId(entry.shiftId);
          final v = shift == null ? null : ShiftVisual.of(context, shift);
          final today = key == dateKey(DateTime.now());
          final selected = key == selectedDate;
          final label = '${DateFormat('EEEE d MMMM', 'fr_FR').format(date)}${shift == null ? ', aucune garde' : ', ${v!.category}, ${shift.label}'}${entry?.isDisciplinary == true ? ', garde disciplinaire' : ''}';
          return DragTarget<String>(
            onWillAcceptWithDetails: (d) => canDrop?.call(date, d.data) ?? false,
            onAcceptWithDetails: (d) => onDrop?.call(date, d.data),
            builder: (context, candidates, _) => Semantics(
              label: label, button: true, selected: selected, excludeSemantics: true,
              child: Material(color: Colors.transparent, child: InkWell(
                key: ValueKey('calendar-day-$key'), onTap: () => onDayTap(date),
                borderRadius: AppRadius.smR,
                child: AnimatedContainer(
                  duration: AppMotion.duration(context),
                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                  decoration: BoxDecoration(
                    color: candidates.isNotEmpty || selected ? c.primaryContainer : Colors.transparent,
                    borderRadius: AppRadius.smR,
                    border: today ? Border.all(color: c.primary, width: 1.5) : null,
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                    Text('$day', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: today ? FontWeight.w700 : FontWeight.w500)),
                    if (v != null) Container(
                      constraints: const BoxConstraints(minHeight: 20),
                      width: double.infinity,
                      decoration: BoxDecoration(color: v.background, borderRadius: BorderRadius.circular(6)),
                      child: Text(v.shortLabel == '24H' && scale > 1.5 ? '24' : v.shortLabel,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: v.foreground, fontWeight: FontWeight.w700)),
                    ) else const SizedBox(height: 20),
                    if (entry?.isDisciplinary == true) Icon(Icons.lock_outline_rounded, size: 12, color: c.onSurfaceVariant),
                  ]),
                ),
              )),
            ),
          );
        },
      ),
    ]);
  }
}
