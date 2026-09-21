import 'package:flutter/material.dart';
import '../models/planning_month.dart';
import '../models/shift_type.dart';
import '../theme/app_theme.dart';

Future<bool> confirmAction(BuildContext context, {
  required String title,
  required String message,
  required String actionLabel,
  bool destructive = false,
}) async => await showDialog<bool>(
  context: context,
  builder: (dialogContext) {
    final c = Theme.of(dialogContext).colorScheme;
    return AlertDialog(
      scrollable: true,
      title: Text(title),
      content: Text(message),
      actionsOverflowButtonSpacing: 8,
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Revenir')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: c.error, foregroundColor: c.onError) : null,
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(actionLabel),
        ),
      ],
    );
  },
) == true;

class AppSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? action;
  const AppSection({super.key, required this.title, required this.child, this.subtitle, this.action});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpace.xl),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)), if (action != null) action!]),
      if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(subtitle!, style: Theme.of(context).textTheme.bodySmall)),
      const SizedBox(height: 12), child,
    ]),
  );
}

class StatusBadge extends StatelessWidget {
  final PlanningMonthStatus status;
  final bool reopened;
  const StatusBadge({super.key, required this.status, this.reopened = false});
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final isReopened = reopened && status != PlanningMonthStatus.approved;
    final label = isReopened ? 'Rouvert' : switch (status) {
      PlanningMonthStatus.approved => 'Validé',
      PlanningMonthStatus.submitted => 'À valider',
      PlanningMonthStatus.rejected => 'À revoir',
      PlanningMonthStatus.draft => 'Brouillon',
    };
    final icon = isReopened ? Icons.lock_open_rounded : switch (status) {
      PlanningMonthStatus.approved => Icons.verified_outlined,
      PlanningMonthStatus.submitted => Icons.schedule_rounded,
      _ => Icons.edit_calendar_outlined,
    };
    return _LabelBadge(label: label, icon: icon,
      background: isReopened ? c.tertiaryContainer : c.primaryContainer,
      foreground: isReopened ? c.onTertiaryContainer : c.onPrimaryContainer);
  }
}

class ShiftVisual {
  final Color background, foreground;
  final String shortLabel, category;
  final IconData icon;
  const ShiftVisual(this.background, this.foreground, this.shortLabel, this.category, this.icon);
  factory ShiftVisual.of(BuildContext context, ShiftType shift) {
    final theme = Theme.of(context);
    final leave = shift.id == 'conge';
    final urg = shift.id.startsWith('urg-');
    final night = shift.id.endsWith('nuit');
    final full = shift.id.endsWith('24h');
    final palette = theme.extension<AppShiftTheme>() ?? AppShiftTheme.forBrightness(theme.brightness);
    final tone = palette.tones[shift.id];
    return ShiftVisual(tone?.background ?? theme.colorScheme.surfaceContainerHigh,
      tone?.foreground ?? theme.colorScheme.onSurface,
      leave ? 'C' : full ? '24H' : night ? 'N' : 'J', leave ? 'Congé' : urg ? 'Urgences' : 'Service', shift.icon);
  }
}
class ShiftBadge extends StatelessWidget {
  final ShiftType shift;
  final bool compact;
  const ShiftBadge({super.key, required this.shift, this.compact = false});
  @override
  Widget build(BuildContext context) {
    final v = ShiftVisual.of(context, shift);
    return _LabelBadge(label: compact ? v.shortLabel : '${v.category} · ${shift.label}',
      icon: compact ? null : v.icon, background: v.background, foreground: v.foreground);
  }
}
class DisciplinaryBadge extends StatelessWidget {
  const DisciplinaryBadge({super.key});
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return _LabelBadge(label: 'Garde disciplinaire', icon: Icons.lock_outline_rounded,
      background: c.surfaceContainerHigh, foreground: c.onSurface);
  }
}
class _LabelBadge extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color background, foreground;
  const _LabelBadge({required this.label, this.icon, required this.background, required this.foreground});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: background, borderRadius: AppRadius.smR),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (icon != null) ...[Icon(icon, color: foreground, size: 16), const SizedBox(width: 6)],
      Flexible(child: Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: foreground))),
    ]),
  );
}

class DoctorTile extends StatelessWidget {
  final String name, subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool selected;
  const DoctorTile({super.key, required this.name, required this.subtitle, this.onTap, this.trailing, this.selected = false});
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final initials = name.split(RegExp(r'\s+')).where((s) => s.isNotEmpty && s.toLowerCase() != 'dr').take(2).map((s) => s.characters.first.toUpperCase()).join();
    return Semantics(selected: selected, child: Material(
      color: selected ? c.primaryContainer : Colors.transparent,
      borderRadius: AppRadius.mdR,
      child: InkWell(onTap: onTap, borderRadius: AppRadius.mdR,
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(children: [
            CircleAvatar(radius: 22, backgroundColor: c.surfaceContainerHigh, foregroundColor: c.onSurface, child: Text(initials, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 3), Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ])),
            if (trailing != null) trailing! else if (selected) Icon(Icons.check_circle_rounded, color: c.primary),
          ]),
        ),
      ),
    ));
  }
}
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 36, color: Theme.of(context).colorScheme.primary),
      const SizedBox(height: 12), Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
      if (message != null) ...[const SizedBox(height: 8), Text(message!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium)],
      if (action != null) ...[const SizedBox(height: 16), action!],
    ]),
  );
}
class AppBottomSheet {
  AppBottomSheet._();
  static Future<T?> show<T>(BuildContext context, {required WidgetBuilder builder}) => showModalBottomSheet<T>(
    context: context, isScrollControlled: true, useSafeArea: true, showDragHandle: true,
    constraints: BoxConstraints(maxWidth: 640, maxHeight: MediaQuery.sizeOf(context).height * .94),
    builder: builder,
  );
}
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;
  const PrimaryButton({super.key, required this.label, required this.onPressed, this.busy = false, this.icon});
  @override
  Widget build(BuildContext context) => SizedBox(width: double.infinity,
    child: FilledButton(onPressed: busy ? null : onPressed,
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (busy) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
        else if (icon != null) Icon(icon, size: 20),
        if (busy || icon != null) const SizedBox(width: 10),
        Flexible(child: Text(label, textAlign: TextAlign.center)),
      ]),
    ));
}
class SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const SecondaryButton({super.key, required this.label, required this.onPressed});
  @override
  Widget build(BuildContext context) => SizedBox(width: double.infinity,
    child: OutlinedButton(onPressed: onPressed, child: Text(label, textAlign: TextAlign.center)));
}
class AppMenuItem extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  final Widget? trailing;
  const AppMenuItem({super.key, required this.title, required this.icon, this.subtitle, this.onTap, this.trailing});
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon), title: Text(title), subtitle: subtitle == null ? null : Text(subtitle!),
    onTap: onTap, trailing: trailing ?? const Icon(Icons.chevron_right_rounded),
  );
}

class NotificationTile extends StatelessWidget {
  final String title, subtitle, status;
  final bool active;
  const NotificationTile({super.key, required this.title, required this.subtitle, required this.status, required this.active});
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(top: 3), child: Icon(active ? Icons.alarm_outlined : Icons.notifications_none_rounded, color: active ? c.primary : c.onSurfaceVariant)),
      const SizedBox(width: 16), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
        const SizedBox(height: 6), Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 6), Text(status, style: Theme.of(context).textTheme.labelMedium),
      ])),
    ]));
  }
}
