from pathlib import Path

EXPECTED = "version: 11.6.21+181"
TARGET = "version: 11.6.22+182"

pubspec = Path("pubspec.yaml")
pub = pubspec.read_text()
if EXPECTED not in pub:
    raise SystemExit("V11.6.22: base version mismatch")
pubspec.write_text(pub.replace(EXPECTED, TARGET, 1))

def replace_class(source: str, class_name: str, replacement: str) -> str:
    marker = f"class {class_name} "
    start = source.find(marker)
    if start < 0:
        raise SystemExit(f"V11.6.22: {class_name} not found")
    brace = source.find("{", start)
    if brace < 0:
        raise SystemExit(f"V11.6.22: opening brace missing for {class_name}")
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
        raise SystemExit(f"V11.6.22: closing brace missing for {class_name}")
    return source[:start] + replacement.rstrip() + source[end:]

home = Path("lib/screens/home_screen.dart")
text = home.read_text()

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
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
      child: GridView.count(
        key: ValueKey('grid-${month.year}-${month.month}'),
        crossAxisCount: 7,
        mainAxisSpacing: 7,
        crossAxisSpacing: 7,
        childAspectRatio: 0.70,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 8),
        children: cells,
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

        final tile = AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.fromLTRB(4, 5, 4, 4),
          decoration: BoxDecoration(
            color: hovering
                ? const Color(0xFFDCEBFF)
                : isToday
                    ? const Color(0xFFF1F7FF)
                    : AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hovering || isToday ? AppColors.brand : AppColors.line,
              width: hovering ? 2 : (isToday ? 1.8 : 1.2),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.navy.withOpacity(
                  currentEntry != null ? 0.075 : 0.035,
                ),
                blurRadius: currentEntry != null ? 10 : 7,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 24,
                child: Row(
                  children: [
                    Container(
                      constraints: const BoxConstraints(
                        minWidth: 23,
                        minHeight: 23,
                      ),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: isToday ? AppColors.brand : Colors.transparent,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        '$day',
                        style: TextStyle(
                          fontFamily: 'SpaceGrotesk',
                          fontSize: 11.5,
                          color: isToday ? Colors.white : AppColors.ink,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (locked && currentEntry == null)
                      const Padding(
                        padding: EdgeInsets.only(right: 2),
                        child: Icon(
                          Icons.lock_outline_rounded,
                          size: 13,
                          color: AppColors.inkFaint,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: currentEntry != null
                    ? GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: canExchange ? onExchange : null,
                        child: _ShiftChip(entry: currentEntry),
                      )
                    : AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        decoration: BoxDecoration(
                          color: hovering
                              ? Colors.white.withOpacity(0.76)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(11),
                          border: hovering
                              ? Border.all(
                                  color: AppColors.brand.withOpacity(0.22),
                                )
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: hovering
                            ? const Icon(
                                Icons.add_rounded,
                                size: 23,
                                color: AppColors.brand,
                              )
                            : null,
                      ),
              ),
            ],
          ),
        );

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: tile),
            if (editable && currentEntry != null && onRemove != null)
              Positioned(
                top: -4,
                right: -4,
                child: _CalendarCellAction(
                  tooltip: 'Retirer cette garde',
                  icon: Icons.close_rounded,
                  onTap: onRemove!,
                  compact: false,
                  foreground: const Color(0xFFB42318),
                  background: const Color(0xFFFFE7E5),
                ),
              )
            else if (canExchange && onExchange != null)
              Positioned(
                top: -5,
                right: -5,
                child: _CalendarCellAction(
                  tooltip: 'Transfert / échange',
                  icon: Icons.swap_horiz_rounded,
                  onTap: onExchange!,
                  compact: false,
                  foreground: Colors.white,
                  background: AppColors.brandDark,
                ),
              ),
          ],
        );
      },
    );
  }
}
"""

cell_action = r"""class _CalendarCellAction extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final bool compact;
  final Color foreground;
  final Color background;

  const _CalendarCellAction({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    required this.compact,
    required this.foreground,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    final size = compact ? 26.0 : 31.0;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: background,
        shape: const CircleBorder(),
        elevation: 3,
        shadowColor: AppColors.navy.withOpacity(0.20),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              icon,
              size: compact ? 15 : 18,
              color: foreground,
            ),
          ),
        ),
      ),
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
    final leave =
        isLeave ? context.watch<AppState>().leaveRequestForEntry(entry) : null;
    final pendingLeave = leave?.status == LeaveRequestStatus.pendingAdmin;

    final groupLabel = isLeave
        ? 'CONGÉ'
        : isUrgence
            ? 'URG'
            : 'SERV';
    final shiftLabel =
        isLeave ? (pendingLeave ? 'Attente' : 'Congé') : shift.label;

    return LayoutBuilder(
      builder: (context, constraints) {
        final short = constraints.maxHeight < 48;

        return Container(
          width: double.infinity,
          height: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: 3,
            vertical: short ? 3 : 5,
          ),
          decoration: BoxDecoration(
            color: shift.color,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: shift.textColor.withOpacity(0.12),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: shift.textColor.withOpacity(0.06),
                blurRadius: 5,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!short) ...[
                  Icon(
                    shift.icon,
                    size: 18,
                    color: shift.textColor,
                  ),
                  const SizedBox(height: 3),
                ],
                Text(
                  groupLabel,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.35,
                    color: shift.textColor.withOpacity(0.84),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  shiftLabel,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'SpaceGrotesk',
                    fontSize: 12.5,
                    height: 1,
                    fontWeight: FontWeight.w900,
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

text = replace_class(text, "_CalendarGrid", calendar_grid)
text = replace_class(text, "_DayCell", day_cell)
text = replace_class(text, "_CalendarCellAction", cell_action)
text = replace_class(text, "_ShiftChip", shift_chip)
home.write_text(text)

notifications = Path("lib/screens/notifications_screen.dart")
ntext = notifications.read_text()

notifications_screen = r"""class NotificationsScreen extends StatelessWidget {
  final int initialIndex;
  const NotificationsScreen({super.key, this.initialIndex = 0});

  Future<void> _clean(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nettoyer les notifications ?'),
        content: const Text(
          'Les rappels passés et les demandes déjà terminées seront masqués. '
          'Les transferts, échanges et congés encore à traiter restent visibles.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.cleaning_services_rounded, size: 18),
            label: const Text('Nettoyer'),
          ),
        ],
      ),
    );

    if (ok == true && context.mounted) {
      context.read<AppState>().clearReadAndPastNotifications();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notifications lues et passées nettoyées.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: initialIndex < 0 ? 0 : (initialIndex > 2 ? 2 : initialIndex),
      child: Scaffold(
        backgroundColor: AppColors.paper,
        appBar: AppBar(
          toolbarHeight: 76,
          backgroundColor: AppColors.paper,
          surfaceTintColor: Colors.transparent,
          titleSpacing: 0,
          title: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.brandSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.notifications_active_outlined,
                  color: AppColors.brand,
                  size: 22,
                ),
              ),
              const SizedBox(width: 11),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Notifications',
                      style: TextStyle(
                        fontFamily: 'SpaceGrotesk',
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        color: AppColors.ink,
                        letterSpacing: -0.35,
                      ),
                    ),
                    SizedBox(height: 1),
                    Text(
                      'GardeFlow',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Tooltip(
                message: 'Nettoyer les notifications',
                child: Material(
                  color: AppColors.brandSoft,
                  borderRadius: BorderRadius.circular(13),
                  child: InkWell(
                    onTap: () => _clean(context),
                    borderRadius: BorderRadius.circular(13),
                    child: const SizedBox(
                      width: 43,
                      height: 43,
                      child: Icon(
                        Icons.cleaning_services_rounded,
                        color: AppColors.brand,
                        size: 21,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(54),
            child: Container(
              margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.paperAlt,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.line),
              ),
              child: TabBar(
                dividerColor: Colors.transparent,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.navy.withOpacity(0.07),
                      blurRadius: 9,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                labelColor: AppColors.brand,
                unselectedLabelColor: AppColors.inkSoft,
                labelStyle: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
                tabs: const [
                  Tab(text: 'Rappels'),
                  Tab(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Transferts / Échanges'),
                    ),
                  ),
                  Tab(text: 'Congés'),
                ],
              ),
            ),
          ),
        ),
        body: const TabBarView(
          children: [
            _RemindersTab(),
            _ExchangesTab(),
            _LeavesTab(),
          ],
        ),
      ),
    );
  }
}
"""

reminders_tab = r"""class _RemindersTab extends StatelessWidget {
  const _RemindersTab();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final reminders = appState.reminders.toList()
      ..sort((a, b) {
        final aSent = a.status == ReminderStatus.sent;
        final bSent = b.status == ReminderStatus.sent;
        if (aSent != bSent) return aSent ? 1 : -1;
        return aSent
            ? b.fireAt.compareTo(a.fireAt)
            : a.fireAt.compareTo(b.fireAt);
      });

    if (reminders.isEmpty) {
      return const _EmptyState(
        icon: Icons.notifications_none_rounded,
        message:
            'Aucun rappel de garde pour l’instant. Les rappels sont créés '
            'à partir des gardes des calendriers validés.',
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            itemCount: reminders.length,
            separatorBuilder: (_, __) => const SizedBox(height: 11),
            itemBuilder: (context, i) => _ReminderCard(reminder: reminders[i]),
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: BoxDecoration(
              color: AppColors.paper,
              border: Border(
                top: BorderSide(color: AppColors.line.withOpacity(0.65)),
              ),
            ),
            child: OutlinedButton.icon(
              onPressed: appState.clearSentReminders,
              icon: const Icon(Icons.delete_sweep_outlined, size: 19),
              label: const Text('Effacer les rappels déjà envoyés'),
            ),
          ),
        ),
      ],
    );
  }
}

class _ReminderCard extends StatelessWidget {
  final ReminderNotification reminder;

  const _ReminderCard({required this.reminder});

  @override
  Widget build(BuildContext context) {
    final sent = reminder.status == ReminderStatus.sent;
    final parts = reminder.label
        .split('·')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();

    final guardLabel = parts.length >= 2
        ? '${parts[0]} · ${parts[1]}'
        : reminder.label;
    final reminderLabel = parts.length >= 3
        ? parts.sublist(2).join(' · ')
        : 'Rappel de garde';

    final isUrgence = guardLabel.toLowerCase().contains('urgence');
    final accent = sent
        ? AppColors.inkSoft
        : (isUrgence ? AppColors.catUrgence : AppColors.catService);
    final rawDate =
        DateFormat('EEEE d MMMM · HH:mm', 'fr_FR').format(reminder.fireAt);
    final dateLabel = rawDate.isEmpty
        ? rawDate
        : rawDate[0].toUpperCase() + rawDate.substring(1);

    return Container(
      padding: const EdgeInsets.fromLTRB(15, 15, 15, 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: sent ? AppColors.line : accent.withOpacity(0.28),
          width: sent ? 1 : 1.3,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withOpacity(0.055),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 43,
            height: 43,
            decoration: BoxDecoration(
              color: accent.withOpacity(sent ? 0.08 : 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              sent
                  ? Icons.notifications_none_rounded
                  : Icons.alarm_rounded,
              color: accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        guardLabel,
                        style: const TextStyle(
                          fontFamily: 'SpaceGrotesk',
                          fontSize: 15,
                          height: 1.15,
                          fontWeight: FontWeight.w900,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: sent
                            ? AppColors.paperAlt
                            : accent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        sent ? 'Envoyée' : 'À venir',
                        style: TextStyle(
                          color: sent ? AppColors.inkSoft : accent,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.paperAlt,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    reminderLabel,
                    style: const TextStyle(
                      color: AppColors.inkSoft,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(
                      Icons.schedule_rounded,
                      size: 15,
                      color: AppColors.inkFaint,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        dateLabel,
                        style: const TextStyle(
                          color: AppColors.inkSoft,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
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

ntext = replace_class(ntext, "NotificationsScreen", notifications_screen)
ntext = replace_class(ntext, "_RemindersTab", reminders_tab)
notifications.write_text(ntext)

print("GardeFlow V11.6.22: calendrier lisible, échange restauré, notifications réorganisées")
