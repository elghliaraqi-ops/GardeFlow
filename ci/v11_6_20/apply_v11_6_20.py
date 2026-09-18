from pathlib import Path

EXPECTED = "version: 11.6.19+179"
TARGET = "version: 11.6.20+180"

pubspec = Path("pubspec.yaml")
pub = pubspec.read_text()
if EXPECTED not in pub:
    raise SystemExit("V11.6.20: base version mismatch")
pubspec.write_text(pub.replace(EXPECTED, TARGET, 1))

home = Path("lib/screens/home_screen.dart")
text = home.read_text()

def replace_class(source: str, class_name: str, replacement: str) -> str:
    marker = f"class {class_name} "
    start = source.find(marker)
    if start < 0:
        raise SystemExit(f"V11.6.20: {class_name} not found")
    brace = source.find("{", start)
    if brace < 0:
        raise SystemExit(f"V11.6.20: opening brace missing for {class_name}")
    depth = 0
    end = None
    for i in range(brace, len(source)):
        ch = source[i]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                end = i + 1
                break
    if end is None:
        raise SystemExit(f"V11.6.20: closing brace missing for {class_name}")
    return source[:start] + replacement.rstrip() + source[end:]

planning_view = r"""class _PlanningView extends StatelessWidget {
  final AppState appState;

  const _PlanningView({required this.appState});

  @override
  Widget build(BuildContext context) {
    final me = appState.currentUser;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.brandSoft,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.calendar_month_rounded,
                  color: AppColors.brand,
                  size: 23,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mon planning',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontFamily: 'SpaceGrotesk',
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.35,
                          ),
                    ),
                    if (me != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${me.service} · ${hospitalDisplayName(me.hospital)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.inkSoft,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              SoftIconButton(
                icon: Icons.notifications_none_rounded,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                ),
                tooltip: 'Notifications',
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: _PlanningShortcut(
                  icon: Icons.picture_as_pdf_rounded,
                  label: 'Planning officiel',
                  accent: AppColors.urg24h,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const OfficialPlanningScreen()),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PlanningShortcut(
                  icon: Icons.badge_outlined,
                  label: 'Annuaire',
                  accent: AppColors.brand,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const DirectoryScreen()),
                  ),
                ),
              ),
            ],
          ),
        ),
        _MonthBar(appState: appState),
        const _WeekdaysRow(),
        const SizedBox(height: 4),
        const Expanded(child: _CalendarGrid()),
        _ShiftTray(
          enabled: appState.canEditMyPlanningMonth(appState.visibleMonth),
        ),
      ],
    );
  }
}

class _PlanningShortcut extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  const _PlanningShortcut({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.line),
            boxShadow: [
              BoxShadow(
                color: AppColors.navy.withOpacity(0.035),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 27,
                height: 27,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 16, color: accent),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
"""

day_cell = r"""class _DayCell extends StatelessWidget {
  final int day;
  final String dateStr;
  final bool isToday;
  final PlanningEntry? entry;
  final bool editable;
  final bool locked;
  final bool canExchange;
  final ValueChanged<String> onDrop;
  final VoidCallback? onRemove;
  final VoidCallback? onExchange;

  const _DayCell({
    required this.day,
    required this.dateStr,
    required this.isToday,
    required this.entry,
    required this.editable,
    required this.locked,
    required this.canExchange,
    required this.onDrop,
    required this.onRemove,
    required this.onExchange,
  });

  @override
  Widget build(BuildContext context) {
    final currentEntry = entry;

    return DragTarget<String>(
      onWillAcceptWithDetails: (_) => editable,
      onAcceptWithDetails: (details) => onDrop(details.data),
      builder: (context, candidateData, rejectedData) {
        final hovering = candidateData.isNotEmpty && editable;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: hovering
                ? const Color(0xFFDCEBFF)
                : isToday
                    ? const Color(0xFFF2F7FF)
                    : AppColors.card,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: hovering || isToday ? AppColors.brand : AppColors.line,
              width: hovering ? 2 : (isToday ? 1.5 : 1),
            ),
            boxShadow: currentEntry != null
                ? [
                    BoxShadow(
                      color: AppColors.navy.withOpacity(0.065),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : null,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final tiny = constraints.maxWidth < 49 || constraints.maxHeight < 54;
              final headerHeight = tiny ? 18.0 : 23.0;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: headerHeight,
                    child: Row(
                      children: [
                        Container(
                          constraints: BoxConstraints(
                            minWidth: tiny ? 18 : 23,
                            minHeight: tiny ? 18 : 23,
                          ),
                          alignment: Alignment.center,
                          padding: EdgeInsets.symmetric(horizontal: tiny ? 2 : 5),
                          decoration: BoxDecoration(
                            color: isToday ? AppColors.brand : Colors.transparent,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text(
                            '$day',
                            style: TextStyle(
                              fontFamily: 'SpaceGrotesk',
                              fontSize: tiny ? 9.5 : 11.5,
                              color: isToday ? Colors.white : AppColors.ink,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (editable && currentEntry != null && onRemove != null)
                          _CalendarCellAction(
                            tooltip: 'Retirer cette garde',
                            icon: Icons.close_rounded,
                            onTap: onRemove!,
                            compact: tiny,
                            foreground: AppColors.danger,
                            background: const Color(0xFFFFEEEE),
                          )
                        else if (canExchange && onExchange != null)
                          _CalendarCellAction(
                            tooltip: 'Échanger cette garde',
                            icon: Icons.swap_horiz_rounded,
                            onTap: onExchange!,
                            compact: tiny,
                            foreground: Colors.white,
                            background: AppColors.brandDark,
                          )
                        else if (locked && currentEntry == null)
                          Icon(
                            Icons.lock_outline_rounded,
                            size: tiny ? 11 : 13,
                            color: AppColors.inkFaint,
                          ),
                      ],
                    ),
                  ),
                  SizedBox(height: tiny ? 1 : 3),
                  Expanded(
                    child: currentEntry != null
                        ? _ShiftChip(entry: currentEntry)
                        : AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            decoration: BoxDecoration(
                              color: hovering
                                  ? Colors.white.withOpacity(0.72)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            alignment: Alignment.center,
                            child: hovering
                                ? Icon(
                                    Icons.add_rounded,
                                    size: tiny ? 18 : 22,
                                    color: AppColors.brand,
                                  )
                                : null,
                          ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
"""

shift_chip = r"""class _ShiftChip extends StatelessWidget {
  final PlanningEntry entry;

  const _ShiftChip({required this.entry});

  @override
  Widget build(BuildContext context) {
    final shift = ShiftCatalog.byId(entry.shiftId);
    final isUrgence = shift.id.startsWith('urg-');
    final isLeave = shift.id == 'conge';
    final leave = isLeave
        ? context.watch<AppState>().leaveRequestForEntry(entry)
        : null;
    final pendingLeave = leave?.status == LeaveRequestStatus.pendingAdmin;

    return LayoutBuilder(
      builder: (context, constraints) {
        final tiny = constraints.maxWidth < 48 || constraints.maxHeight < 32;
        final compact = constraints.maxWidth < 66 || constraints.maxHeight < 48;
        final groupLabel = isLeave
            ? 'CONGÉ'
            : isUrgence
                ? 'URG'
                : 'SERV';
        final shiftLabel = isLeave
            ? (pendingLeave ? 'Attente' : 'Congé')
            : shift.label;
        final showIcon = !tiny && constraints.maxHeight >= 44;

        return Container(
          width: double.infinity,
          height: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: tiny ? 2 : 4,
            vertical: tiny ? 2 : 4,
          ),
          decoration: BoxDecoration(
            color: shift.color,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: shift.textColor.withOpacity(0.10),
              width: 1,
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showIcon) ...[
                  Icon(
                    shift.icon,
                    size: compact ? 14 : 18,
                    color: shift.textColor,
                  ),
                  SizedBox(height: compact ? 1 : 2),
                ],
                Text(
                  groupLabel,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: tiny ? 8.5 : compact ? 9.5 : 10.5,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.25,
                    color: shift.textColor.withOpacity(0.84),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  shiftLabel,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'SpaceGrotesk',
                    fontSize: tiny ? 9.5 : compact ? 10.5 : 12,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    color: shift.textColor,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
"""

shift_tray = r"""class _ShiftTray extends StatelessWidget {
  final bool enabled;

  const _ShiftTray({required this.enabled});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        border: const Border(top: BorderSide(color: AppColors.line)),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withOpacity(0.10),
            blurRadius: 28,
            offset: const Offset(0, -10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 4,
            margin: const EdgeInsets.only(bottom: 9),
            decoration: BoxDecoration(
              color: const Color(0xFFD7DFE9),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Ajouter au planning',
                  style: TextStyle(
                    fontFamily: 'SpaceGrotesk',
                    color: AppColors.ink,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                enabled ? 'Glisser-déposer' : 'Verrouillé',
                style: TextStyle(
                  color: enabled ? AppColors.brand : AppColors.inkFaint,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          if (!enabled)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 13,
                    color: AppColors.inkSoft,
                  ),
                  SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      'Calendrier validé : les tuiles sont verrouillées.',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.inkSoft,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          Opacity(
            opacity: enabled ? 1 : 0.42,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      _TrayRow(
                        label: 'Service',
                        accent: AppColors.catService,
                        enabled: enabled,
                        shifts: const [
                          ShiftCatalog.serviceJour,
                          ShiftCatalog.service24h,
                          ShiftCatalog.serviceNuit,
                        ],
                      ),
                      const SizedBox(height: 8),
                      _TrayRow(
                        label: 'Urgences',
                        accent: AppColors.catUrgence,
                        enabled: enabled,
                        shifts: const [
                          ShiftCatalog.urgJour,
                          ShiftCatalog.urg24h,
                          ShiftCatalog.urgNuit,
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _CongeDock(
                  shift: ShiftCatalog.conge,
                  enabled: enabled,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
"""

tray_row = r"""class _TrayRow extends StatelessWidget {
  final String label;
  final Color accent;
  final List<ShiftType> shifts;
  final bool enabled;

  const _TrayRow({
    required this.label,
    required this.accent,
    required this.shifts,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.inkSoft,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: shifts
              .map(
                (shift) => Expanded(
                  child: _ShiftTile(
                    shift: shift,
                    enabled: enabled,
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}
"""

shift_tile = r"""class _ShiftTile extends StatelessWidget {
  final ShiftType shift;
  final bool enabled;

  const _ShiftTile({
    required this.shift,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final tile = Container(
      height: 58,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: shift.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: shift.textColor.withOpacity(0.09),
        ),
        boxShadow: [
          BoxShadow(
            color: shift.textColor.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            shift.icon,
            size: 20,
            color: shift.textColor,
          ),
          const SizedBox(height: 3),
          Text(
            shift.label,
            style: TextStyle(
              fontFamily: 'SpaceGrotesk',
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: shift.textColor,
            ),
          ),
        ],
      ),
    );

    return Draggable<String>(
      data: shift.id,
      maxSimultaneousDrags: enabled ? 1 : 0,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: 98,
          height: 66,
          child: Transform.scale(
            scale: 1.06,
            child: DecoratedBox(
              decoration: BoxDecoration(boxShadow: AppShadow.high),
              child: tile,
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.26,
        child: tile,
      ),
      child: tile,
    );
  }
}
"""

conge_dock = r"""class _CongeDock extends StatelessWidget {
  final ShiftType shift;
  final bool enabled;

  const _CongeDock({
    required this.shift,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final dock = Container(
      width: 86,
      height: 138,
      decoration: BoxDecoration(
        color: shift.color,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(
          color: shift.textColor.withOpacity(0.10),
        ),
        boxShadow: [
          BoxShadow(
            color: shift.textColor.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.30),
              shape: BoxShape.circle,
            ),
            child: Icon(
              shift.icon,
              size: 24,
              color: shift.textColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            shift.label,
            style: TextStyle(
              fontFamily: 'SpaceGrotesk',
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: shift.textColor,
            ),
          ),
        ],
      ),
    );

    return Draggable<String>(
      data: shift.id,
      maxSimultaneousDrags: enabled ? 1 : 0,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: 86,
          height: 138,
          child: Transform.scale(
            scale: 1.05,
            child: DecoratedBox(
              decoration: BoxDecoration(boxShadow: AppShadow.high),
              child: dock,
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.26,
        child: dock,
      ),
      child: dock,
    );
  }
}
"""

text = replace_class(text, "_PlanningView", planning_view)
text = replace_class(text, "_DayCell", day_cell)
text = replace_class(text, "_ShiftChip", shift_chip)
text = replace_class(text, "_ShiftTray", shift_tray)
text = replace_class(text, "_TrayRow", tray_row)
text = replace_class(text, "_ShiftTile", shift_tile)
text = replace_class(text, "_CongeDock", conge_dock)

home.write_text(text)

print("GardeFlow V11.6.20: planning redesign visuel appliqué, logique métier inchangée")
