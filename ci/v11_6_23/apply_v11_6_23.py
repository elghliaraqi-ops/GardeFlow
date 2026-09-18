from pathlib import Path

EXPECTED = "version: 11.6.22+182"
TARGET = "version: 11.6.23+183"

pubspec = Path("pubspec.yaml")
pub = pubspec.read_text()
if EXPECTED not in pub:
    raise SystemExit("V11.6.23: base version mismatch")
pubspec.write_text(pub.replace(EXPECTED, TARGET, 1))

home = Path("lib/screens/home_screen.dart")
text = home.read_text()

def replace_class(source: str, class_name: str, replacement: str) -> str:
    marker = f"class {class_name} "
    start = source.find(marker)
    if start < 0:
        raise SystemExit(f"V11.6.23: {class_name} not found")
    brace = source.find("{", start)
    if brace < 0:
        raise SystemExit(f"V11.6.23: opening brace missing for {class_name}")
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
        raise SystemExit(f"V11.6.23: closing brace missing for {class_name}")
    return source[:start] + replacement.rstrip() + source[end:]

planning_view = r"""class _PlanningView extends StatelessWidget {
  final AppState appState;

  const _PlanningView({required this.appState});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
          child: Align(
            alignment: Alignment.center,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const OfficialPlanningScreen(),
                  ),
                ),
                borderRadius: BorderRadius.circular(999),
                child: Ink(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.line),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.navy.withOpacity(0.08),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.picture_as_pdf_rounded,
                        size: 18,
                        color: AppColors.urg24h,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Planning officiel',
                        style: TextStyle(
                          color: AppColors.ink,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        _MonthBar(appState: appState),
        const _WeekdaysRow(),
        const SizedBox(height: 2),
        const Expanded(child: _CalendarGrid()),
        _ShiftTray(
          enabled: appState.canEditMyPlanningMonth(appState.visibleMonth),
        ),
      ],
    );
  }
}
"""

month_bar = r"""class _MonthBar extends StatelessWidget {
  final AppState appState;
  const _MonthBar({required this.appState});

  @override
  Widget build(BuildContext context) {
    final month = appState.visibleMonth;
    final record = appState.myPlanningMonth(month);
    final status = record?.status ?? PlanningMonthStatus.draft;
    final monthLabel = _capitalize(DateFormat.yMMMM('fr_FR').format(month));

    String statusLabel;
    IconData statusIcon;
    Color statusBg;
    Color statusFg;
    String? reopenReason;

    switch (status) {
      case PlanningMonthStatus.approved:
        statusLabel = 'Validé';
        statusIcon = Icons.verified_rounded;
        statusBg = AppColors.conge.withOpacity(0.22);
        statusFg = AppColors.congeText;
        break;
      case PlanningMonthStatus.draft:
      case PlanningMonthStatus.submitted:
      case PlanningMonthStatus.rejected:
        reopenReason = record?.rejectionReason?.trim();
        final reopened = reopenReason != null && reopenReason.isNotEmpty;
        statusLabel = reopened ? 'Rouvert' : 'En préparation';
        statusIcon =
            reopened ? Icons.lock_open_rounded : Icons.edit_calendar_rounded;
        statusBg = reopened ? AppColors.serviceJour : AppColors.paperAlt;
        statusFg = AppColors.ink;
        break;
    }

    final canSubmit = status != PlanningMonthStatus.approved;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 42,
            child: Row(
              children: [
                _MonthArrowButton(
                  icon: Icons.chevron_left_rounded,
                  onTap: appState.previousMonth,
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      monthLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'SpaceGrotesk',
                        color: AppColors.ink,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.45,
                      ),
                    ),
                  ),
                ),
                _MonthArrowButton(
                  icon: Icons.chevron_right_rounded,
                  onTap: appState.nextMonth,
                ),
              ],
            ),
          ),
          const SizedBox(height: 3),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () => _showMonthInfo(
                  context,
                  status,
                  reopenReason,
                ),
                child: Container(
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: 11),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 15, color: statusFg),
                      const SizedBox(width: 5),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusFg,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (canSubmit) ...[
                const SizedBox(width: 8),
                _ValidateButton(appState: appState, month: month),
              ],
            ],
          ),
        ],
      ),
    );
  }

  void _showMonthInfo(
    BuildContext context,
    PlanningMonthStatus status,
    String? reopenReason,
  ) {
    late String title;
    late String detail;
    switch (status) {
      case PlanningMonthStatus.approved:
        title = 'Calendrier validé définitivement';
        detail =
            'Le mois est verrouillé. Un administrateur peut supprimer une garde validée ou rouvrir le calendrier pour correction.';
        break;
      case PlanningMonthStatus.draft:
      case PlanningMonthStatus.submitted:
      case PlanningMonthStatus.rejected:
        if (reopenReason != null && reopenReason.isNotEmpty) {
          title = 'Calendrier rouvert par un administrateur';
          detail =
              'Motif : $reopenReason. Modifiez vos tuiles puis validez à nouveau le mois.';
        } else {
          title = 'Calendrier en préparation';
          detail =
              'Placez vos tuiles Service, Urgences et Congé puis validez définitivement le mois.';
        }
        break;
    }
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.xl,
          AppSpace.md,
          AppSpace.xl,
          AppSpace.xxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpace.sm),
            Text(detail, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _MonthArrowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _MonthArrowButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.brandSoft,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(icon, color: AppColors.brand, size: 26),
        ),
      ),
    );
  }
}
"""

calendar_grid = r"""class _CalendarGrid extends StatelessWidget {
  const _CalendarGrid();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final month = appState.visibleMonth;
    final firstWeekday = DateTime(month.year, month.month, 1).weekday - 1;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final todayKey = AppState.dateKey(DateTime.now());
    final monthStatus =
        appState.myPlanningMonth(month)?.status ?? PlanningMonthStatus.draft;
    final monthEditable = appState.canEditMyPlanningMonth(month);
    final monthApproved = monthStatus == PlanningMonthStatus.approved;
    final totalCells = firstWeekday + daysInMonth;
    final rows = ((totalCells + 6) ~/ 7).clamp(5, 6);

    final cells = <Widget>[];

    for (var i = 0; i < firstWeekday; i++) {
      cells.add(
        KeyedSubtree(
          key: ValueKey('empty-$i'),
          child: const SizedBox.shrink(),
        ),
      );
    }

    for (var d = 1; d <= daysInMonth; d++) {
      final date = DateTime(month.year, month.month, d);
      final dateStr = AppState.dateKey(date);
      final entry = appState.myEntryForDate(dateStr);
      final editable = monthEditable &&
          !appState.dateIsPast(dateStr) &&
          (entry == null || !appState.isApprovedLeaveEntry(entry));
      final canExchange = monthApproved &&
          entry != null &&
          ShiftCatalog.byId(entry.shiftId).hasSchedule &&
          !appState.guardHasStarted(entry);

      cells.add(
        KeyedSubtree(
          key: ValueKey(dateStr),
          child: _DayCell(
            day: d,
            dateStr: dateStr,
            isToday: dateStr == todayKey,
            entry: entry,
            editable: editable,
            locked: !monthEditable,
            canExchange: canExchange,
            onDrop: (shiftId) async {
              final err = await appState.placeShift(dateStr, shiftId);
              if (err != null && context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(err)));
              }
            },
            onRemove: entry == null
                ? null
                : () async {
                    final err = await appState.removeShift(entry.id);
                    if (err != null && context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(err)));
                    }
                  },
            onExchange: entry == null
                ? null
                : () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      showDragHandle: true,
                      builder: (_) =>
                          ExchangeRequestSheet(dateStr: dateStr, entry: entry),
                    ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 5),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = 5.0;
          final itemWidth =
              (constraints.maxWidth - gap * 6) / 7;
          final itemHeight =
              (constraints.maxHeight - gap * (rows - 1)) / rows;
          final safeHeight =
              itemHeight.isFinite && itemHeight > 1 ? itemHeight : 1.0;
          final aspectRatio = itemWidth / safeHeight;

          return GridView.count(
            key: ValueKey('grid-${month.year}-${month.month}'),
            crossAxisCount: 7,
            mainAxisSpacing: gap,
            crossAxisSpacing: gap,
            childAspectRatio: aspectRatio,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            children: cells,
          );
        },
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
    final shift =
        currentEntry == null ? null : ShiftCatalog.byId(currentEntry.shiftId);
    final isUrgence = shift?.id.startsWith('urg-') ?? false;
    final isLeave = shift?.id == 'conge';

    String? groupLabel;
    String? shiftLabel;
    if (shift != null) {
      if (isLeave) {
        final leave =
            context.watch<AppState>().leaveRequestForEntry(currentEntry!);
        final pending = leave?.status == LeaveRequestStatus.pendingAdmin;
        groupLabel = 'CONGÉ';
        shiftLabel = pending ? 'Attente' : 'Congé';
      } else {
        groupLabel = isUrgence ? 'URG' : 'SERV';
        shiftLabel = shift.label;
      }
    }

    return DragTarget<String>(
      onWillAcceptWithDetails: (_) => editable,
      onAcceptWithDetails: (details) => onDrop(details.data),
      builder: (context, candidateData, rejectedData) {
        final hovering = candidateData.isNotEmpty && editable;
        final background = hovering
            ? const Color(0xFFDCEBFF)
            : shift?.color ?? AppColors.card;
        final foreground = shift?.textColor ?? AppColors.ink;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: canExchange ? onExchange : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: hovering || isToday
                    ? AppColors.brand
                    : shift != null
                        ? foreground.withOpacity(0.15)
                        : AppColors.line,
                width: hovering ? 2 : (isToday ? 1.8 : 1),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.navy.withOpacity(
                    shift != null ? 0.075 : 0.035,
                  ),
                  blurRadius: shift != null ? 9 : 5,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 25, 4, 4),
                    child: Center(
                      child: hovering && shift == null
                          ? const Icon(
                              Icons.add_rounded,
                              color: AppColors.brand,
                              size: 24,
                            )
                          : shift == null
                              ? const SizedBox.shrink()
                              : FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        groupLabel!,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: foreground.withOpacity(0.84),
                                          fontSize: 10.5,
                                          height: 1,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.25,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        shiftLabel!,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: foreground,
                                          fontFamily: 'SpaceGrotesk',
                                          fontSize: 12,
                                          height: 1,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                    ),
                  ),
                ),
                Positioned(
                  top: 5,
                  left: 5,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 23,
                      minHeight: 23,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isToday
                          ? AppColors.brand
                          : shift != null
                              ? Colors.white.withOpacity(0.78)
                              : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$day',
                      style: TextStyle(
                        color: isToday ? Colors.white : AppColors.ink,
                        fontFamily: 'SpaceGrotesk',
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                if (editable && currentEntry != null && onRemove != null)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: _CalendarCellAction(
                      tooltip: 'Retirer cette garde',
                      icon: Icons.close_rounded,
                      onTap: onRemove!,
                      compact: true,
                      foreground: const Color(0xFFB42318),
                      background: const Color(0xFFFFE7E5),
                    ),
                  )
                else if (canExchange && onExchange != null)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: _CalendarCellAction(
                      tooltip: 'Transfert / échange',
                      icon: Icons.swap_horiz_rounded,
                      onTap: onExchange!,
                      compact: true,
                      foreground: Colors.white,
                      background: AppColors.brandDark,
                    ),
                  )
                else if (locked && currentEntry == null)
                  const Positioned(
                    top: 7,
                    right: 7,
                    child: Icon(
                      Icons.lock_outline_rounded,
                      size: 12,
                      color: AppColors.inkFaint,
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
    if (!enabled) {
      return Container(
        height: 42,
        margin: const EdgeInsets.fromLTRB(8, 2, 8, 5),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.line),
          boxShadow: [
            BoxShadow(
              color: AppColors.navy.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 15,
              color: AppColors.inkSoft,
            ),
            SizedBox(width: 7),
            Text(
              'Planning validé · tuiles verrouillées',
              style: TextStyle(
                color: AppColors.inkSoft,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }

    const shifts = <ShiftType>[
      ShiftCatalog.serviceJour,
      ShiftCatalog.service24h,
      ShiftCatalog.serviceNuit,
      ShiftCatalog.urgJour,
      ShiftCatalog.urg24h,
      ShiftCatalog.urgNuit,
      ShiftCatalog.conge,
    ];

    return Container(
      height: 92,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(22),
        ),
        border: const Border(
          top: BorderSide(color: AppColors.line),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        children: [
          const Row(
            children: [
              Text(
                'Glisser une tuile',
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Spacer(),
              Text(
                'Service · Urgences · Congé',
                style: TextStyle(
                  color: AppColors.inkFaint,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Expanded(
            child: Row(
              children: [
                for (var i = 0; i < shifts.length; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(
                    child: _CompactShiftTile(
                      shift: shifts[i],
                      enabled: enabled,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactShiftTile extends StatelessWidget {
  final ShiftType shift;
  final bool enabled;

  const _CompactShiftTile({
    required this.shift,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final isUrgence = shift.id.startsWith('urg-');
    final isLeave = shift.id == 'conge';
    final prefix = isLeave
        ? ''
        : isUrgence
            ? 'URG'
            : 'SERV';

    final tile = Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
      decoration: BoxDecoration(
        color: shift.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: shift.textColor.withOpacity(0.10),
        ),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isLeave)
              Text(
                prefix,
                style: TextStyle(
                  color: shift.textColor.withOpacity(0.76),
                  fontSize: 8,
                  height: 1,
                  fontWeight: FontWeight.w900,
                ),
              ),
            if (!isLeave) const SizedBox(height: 2),
            Icon(
              shift.icon,
              size: 15,
              color: shift.textColor,
            ),
            const SizedBox(height: 2),
            Text(
              shift.label,
              style: TextStyle(
                color: shift.textColor,
                fontFamily: 'SpaceGrotesk',
                fontSize: 9.5,
                height: 1,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );

    return Draggable<String>(
      data: shift.id,
      maxSimultaneousDrags: enabled ? 1 : 0,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: 58,
          height: 62,
          child: tile,
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.28,
        child: tile,
      ),
      child: tile,
    );
  }
}
"""

text = replace_class(text, "_PlanningView", planning_view)
text = replace_class(text, "_MonthBar", month_bar)
text = replace_class(text, "_CalendarGrid", calendar_grid)
text = replace_class(text, "_DayCell", day_cell)
text = replace_class(text, "_ShiftTray", shift_tray)

home.write_text(text)

print("GardeFlow V11.6.23: planning plein écran, calendrier non scrollable, tuiles pleine case")
