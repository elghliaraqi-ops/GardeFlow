from pathlib import Path

PATH = Path('source/lib/screens/home_screen.dart')
text = PATH.read_text(encoding='utf-8')

if 'class _GuardVisualTheme {' in text:
    print('Home sky cards already applied.')
    raise SystemExit(0)


def require(anchor: str) -> None:
    if anchor not in text:
        raise SystemExit(f'Missing expected anchor: {anchor[:120]!r}')


# 1) Make the dashboard select an active approved guard first, then the next one.
future_anchor = '  List<PlanningEntry> _futureGuards(AppUser me) {'
require(future_anchor)
active_helper = r'''  PlanningEntry? _activeGuard(AppUser me, DateTime now) {
    final candidates = appState.planning.where(
      (entry) =>
          (entry.ownerId == me.id || entry.ownerPhone == me.phone) &&
          entry.shiftId != 'conge' &&
          appState.isPlanningEntryApproved(entry),
    );

    PlanningEntry? active;
    DateTime? latestStart;
    for (final entry in candidates) {
      final date = DateTime.tryParse(entry.dateStr);
      if (date == null) continue;
      final shift = ShiftCatalog.byId(entry.shiftId);
      if (!shift.hasSchedule || shift.start == null || shift.end == null) {
        continue;
      }

      final startParts = shift.start!.split(':').map(int.parse).toList();
      final endParts = shift.end!.split(':').map(int.parse).toList();
      final start = DateTime(
        date.year,
        date.month,
        date.day,
        startParts[0],
        startParts[1],
      );
      var end = DateTime(
        date.year,
        date.month,
        date.day,
        endParts[0],
        endParts[1],
      );
      if (!end.isAfter(start)) end = end.add(const Duration(days: 1));

      final inProgress = !now.isBefore(start) && now.isBefore(end);
      if (inProgress && (latestStart == null || start.isAfter(latestStart))) {
        active = entry;
        latestStart = start;
      }
    }
    return active;
  }

'''
text = text.replace(future_anchor, active_helper + future_anchor, 1)

old_build_selection = r'''    final future = _futureGuards(me);
    final next = future.isEmpty ? null : future.first;
    final now = DateTime.now();
    final isNight = now.hour >= 18 || now.hour < 6;
'''
require(old_build_selection)
new_build_selection = r'''    final now = DateTime.now();
    final activeGuard = _activeGuard(me, now);
    final future = _futureGuards(me);
    final nextGuard = future.isEmpty ? null : future.first;
    final displayedGuard = activeGuard ?? nextGuard;
    final isNight = now.hour >= 18 || now.hour < 6;
'''
text = text.replace(old_build_selection, new_build_selection, 1)

old_hero_call = r'''            isNight: isNight,
            monthlyCount: monthlyCount,
            urgenceCount: urgenceMonthlyCount,
            serviceCount: serviceMonthlyCount,
          ),
          const SizedBox(height: 14),
          _NextGuardCard(entry: next, onTap: onOpenPlanning),
'''
require(old_hero_call)
new_hero_call = r'''            isNight: isNight,
            guardEntry: displayedGuard,
            monthlyCount: monthlyCount,
            urgenceCount: urgenceMonthlyCount,
            serviceCount: serviceMonthlyCount,
          ),
          const SizedBox(height: 14),
          _NextGuardCard(
            entry: displayedGuard,
            isActive: activeGuard != null,
            onTap: onOpenPlanning,
          ),
'''
text = text.replace(old_hero_call, new_hero_call, 1)

# 2) Replace the hero with a practical sky-based card that follows the guard type.
hero_start = text.index('class _HomeHeroCard extends StatelessWidget {')
hero_end = text.index('class _HomeStatPill extends StatelessWidget {', hero_start)
new_hero = r'''class _GuardVisualTheme {
  final bool isUrgence;
  final bool isNight;
  final bool is24h;
  final List<Color> heroColors;
  final List<Color> dutyColors;
  final Color glow;

  const _GuardVisualTheme({
    required this.isUrgence,
    required this.isNight,
    required this.is24h,
    required this.heroColors,
    required this.dutyColors,
    required this.glow,
  });

  String get category => isUrgence ? 'URGENCES' : 'SERVICE';
  String get period => is24h ? '24H' : (isNight ? 'Nuit' : 'Jour');

  factory _GuardVisualTheme.fromEntry(
    PlanningEntry? entry, {
    required bool fallbackNight,
  }) {
    if (entry == null) {
      return fallbackNight
          ? const _GuardVisualTheme(
              isUrgence: false,
              isNight: true,
              is24h: false,
              heroColors: [
                Color(0xFF051329),
                Color(0xFF0B326A),
                Color(0xFF155AA4),
              ],
              dutyColors: [Color(0xFF071A36), Color(0xFF164F8E)],
              glow: Color(0xFF2F8FE8),
            )
          : const _GuardVisualTheme(
              isUrgence: false,
              isNight: false,
              is24h: false,
              heroColors: [
                Color(0xFF0B75C9),
                Color(0xFF2AA9F3),
                Color(0xFF7FD7FF),
              ],
              dutyColors: [Color(0xFF137FCB), Color(0xFF50BFF2)],
              glow: Color(0xFF5AC9FF),
            );
    }

    final id = entry.shiftId.toLowerCase();
    final isUrgence = id.startsWith('urg-') || id.contains('urgence');
    final is24h = id.contains('24h') || id.contains('24-h');
    final isNight = !is24h && id.contains('nuit');

    if (isUrgence && isNight) {
      return const _GuardVisualTheme(
        isUrgence: true,
        isNight: true,
        is24h: false,
        heroColors: [
          Color(0xFF25040C),
          Color(0xFF610A1C),
          Color(0xFF9A1831),
        ],
        dutyColors: [Color(0xFF360611), Color(0xFF8B1730)],
        glow: Color(0xFFD92A4A),
      );
    }
    if (isUrgence && is24h) {
      return const _GuardVisualTheme(
        isUrgence: true,
        isNight: false,
        is24h: true,
        heroColors: [
          Color(0xFF713008),
          Color(0xFFD95D13),
          Color(0xFFFF9B2F),
        ],
        dutyColors: [Color(0xFF9A3A09), Color(0xFFF47B18)],
        glow: Color(0xFFFFA23D),
      );
    }
    if (isUrgence) {
      return const _GuardVisualTheme(
        isUrgence: true,
        isNight: false,
        is24h: false,
        heroColors: [
          Color(0xFF9D102A),
          Color(0xFFE32B43),
          Color(0xFFFF626C),
        ],
        dutyColors: [Color(0xFFB51630), Color(0xFFF34052)],
        glow: Color(0xFFFF6272),
      );
    }
    if (isNight) {
      return const _GuardVisualTheme(
        isUrgence: false,
        isNight: true,
        is24h: false,
        heroColors: [
          Color(0xFF041229),
          Color(0xFF0A3169),
          Color(0xFF1455A1),
        ],
        dutyColors: [Color(0xFF06172F), Color(0xFF15559C)],
        glow: Color(0xFF388DDF),
      );
    }
    if (is24h) {
      return const _GuardVisualTheme(
        isUrgence: false,
        isNight: false,
        is24h: true,
        heroColors: [
          Color(0xFF0877B2),
          Color(0xFF2FB4E5),
          Color(0xFF76D7F5),
        ],
        dutyColors: [Color(0xFF0B83C0), Color(0xFF38BDE9)],
        glow: Color(0xFF72D8F8),
      );
    }
    return const _GuardVisualTheme(
      isUrgence: false,
      isNight: false,
      is24h: false,
      heroColors: [
        Color(0xFF0A6FCA),
        Color(0xFF28A8F2),
        Color(0xFF83D9FF),
      ],
      dutyColors: [Color(0xFF0F7DCE), Color(0xFF48BAF1)],
      glow: Color(0xFF58C8FF),
    );
  }
}

class _GuardSkyPainter extends CustomPainter {
  final _GuardVisualTheme theme;
  final bool compact;

  const _GuardSkyPainter({required this.theme, this.compact = false});

  @override
  void paint(Canvas canvas, Size size) {
    if (theme.isNight) {
      final starPaint = Paint()..color = Colors.white.withOpacity(0.34);
      final stars = <Offset>[
        Offset(size.width * .08, size.height * .18),
        Offset(size.width * .20, size.height * .11),
        Offset(size.width * .35, size.height * .24),
        Offset(size.width * .49, size.height * .13),
        Offset(size.width * .64, size.height * .21),
        Offset(size.width * .76, size.height * .09),
        Offset(size.width * .88, size.height * .26),
      ];
      for (var i = 0; i < stars.length; i++) {
        canvas.drawCircle(stars[i], i.isEven ? 1.15 : .75, starPaint);
      }
    } else {
      final cloudPaint = Paint()..color = Colors.white.withOpacity(0.07);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(size.width * .28, size.height * .22),
          width: size.width * .26,
          height: size.height * .12,
        ),
        cloudPaint,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(size.width * .68, size.height * .18),
          width: size.width * .23,
          height: size.height * .10,
        ),
        cloudPaint,
      );
    }

    final rearPaint = Paint()..color = Colors.black.withOpacity(0.10);
    final rear = Path()
      ..moveTo(0, size.height * .69)
      ..lineTo(size.width * .12, size.height * .58)
      ..lineTo(size.width * .24, size.height * .67)
      ..lineTo(size.width * .39, size.height * .50)
      ..lineTo(size.width * .52, size.height * .64)
      ..lineTo(size.width * .66, size.height * .52)
      ..lineTo(size.width * .81, size.height * .65)
      ..lineTo(size.width, size.height * .50)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(rear, rearPaint);

    final frontPaint = Paint()
      ..color = Colors.black.withOpacity(theme.isNight ? 0.26 : 0.15);
    final base = compact ? .80 : .76;
    final front = Path()
      ..moveTo(0, size.height * base)
      ..quadraticBezierTo(
        size.width * .18,
        size.height * (base - .10),
        size.width * .34,
        size.height * base,
      )
      ..quadraticBezierTo(
        size.width * .52,
        size.height * (base - .08),
        size.width * .69,
        size.height * base,
      )
      ..quadraticBezierTo(
        size.width * .84,
        size.height * (base - .07),
        size.width,
        size.height * (base - .01),
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(front, frontPaint);
  }

  @override
  bool shouldRepaint(covariant _GuardSkyPainter oldDelegate) =>
      oldDelegate.theme != theme || oldDelegate.compact != compact;
}

class _HomeHeroCard extends StatelessWidget {
  final AppUser user;
  final String greeting;
  final String dateLabel;
  final String timeLabel;
  final bool isNight;
  final PlanningEntry? guardEntry;
  final int monthlyCount;
  final int urgenceCount;
  final int serviceCount;

  const _HomeHeroCard({
    required this.user,
    required this.greeting,
    required this.dateLabel,
    required this.timeLabel,
    required this.isNight,
    required this.guardEntry,
    required this.monthlyCount,
    required this.urgenceCount,
    required this.serviceCount,
  });

  @override
  Widget build(BuildContext context) {
    final visual = _GuardVisualTheme.fromEntry(
      guardEntry,
      fallbackNight: isNight,
    );

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: visual.heroColors,
          stops: const [0.0, 0.58, 1.0],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
        boxShadow: [
          BoxShadow(
            color: visual.glow.withOpacity(0.17),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _GuardSkyPainter(theme: visual),
            ),
          ),
          Positioned(
            right: -24,
            top: -28,
            child: Container(
              width: 126,
              height: 126,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.white.withOpacity(0.16),
                    Colors.white.withOpacity(0.025),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 18,
            top: 21,
            child: Container(
              width: 57,
              height: 57,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.10),
                border: Border.all(color: Colors.white.withOpacity(0.10)),
              ),
              child: _GuardPeriodGlyph(
                isNight: visual.isNight,
                is24h: visual.is24h,
                size: 32,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 74),
                  child: Text(
                    '$greeting Dr ${user.nom}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'SpaceGrotesk',
                      fontSize: 25,
                      height: 1.04,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.65,
                    ),
                  ),
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      color: Colors.white.withOpacity(0.84),
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '$dateLabel · $timeLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.88),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w650,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _HomeStatPill(
                        icon: Icons.calendar_month_rounded,
                        value: monthlyCount,
                        label: 'Ce mois',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _HomeStatPill(
                        icon: Icons.emergency_rounded,
                        value: urgenceCount,
                        label: 'Urgences',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _HomeStatPill(
                        icon: Icons.medical_services_rounded,
                        value: serviceCount,
                        label: 'Service',
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

'''
text = text[:hero_start] + new_hero + text[hero_end:]

# 3) Replace the next/current guard card with the same deterministic palette system.
next_start = text.index('class _NextGuardCard extends StatelessWidget {')
next_end = text.index('class _GuardPeriodGlyph extends StatelessWidget {', next_start)
new_next = r'''class _NextGuardCard extends StatelessWidget {
  final PlanningEntry? entry;
  final bool isActive;
  final VoidCallback onTap;

  const _NextGuardCard({
    required this.entry,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (entry == null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Ink(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0A1C2C), Color(0xFF12354F)],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.event_available_rounded,
                    color: Color(0xFF56D8A0),
                    size: 25,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Prochaine garde',
                        style: TextStyle(
                          color: Colors.white,
                          fontFamily: 'SpaceGrotesk',
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Aucune garde validée à venir.',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.58),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white.withOpacity(0.58),
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final current = entry!;
    final shift = ShiftCatalog.byId(current.shiftId);
    final visual = _GuardVisualTheme.fromEntry(
      current,
      fallbackNight: false,
    );
    final date = DateTime.tryParse(current.dateStr);
    final rawDateLabel = date == null
        ? current.dateStr
        : DateFormat('EEE d MMMM', 'fr_FR').format(date);
    final dateLabel = rawDateLabel.isEmpty
        ? rawDateLabel
        : rawDateLabel[0].toUpperCase() + rawDateLabel.substring(1);
    final timeLabel = shift.start != null && shift.end != null
        ? '${shift.start} → ${shift.end}'
        : visual.is24h
            ? '08:00 → 08:00'
            : visual.isNight
                ? '20:00 → 08:00'
                : '08:00 → 20:00';

    String countdownLabel = 'À venir';
    if (isActive) {
      countdownLabel = 'En cours';
    } else if (date != null) {
      final today = DateTime.now();
      final startToday = DateTime(today.year, today.month, today.day);
      final guardDay = DateTime(date.year, date.month, date.day);
      final days = guardDay.difference(startToday).inDays;
      if (days == 0) {
        countdownLabel = "Aujourd'hui";
      } else if (days == 1) {
        countdownLabel = 'Demain';
      } else if (days > 1) {
        countdownLabel = 'Dans $days jours';
      }
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(26),
        child: Ink(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: visual.dutyColors,
            ),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
            boxShadow: [
              BoxShadow(
                color: visual.glow.withOpacity(0.16),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _GuardSkyPainter(theme: visual, compact: true),
                  ),
                ),
                Positioned(
                  right: -36,
                  top: -56,
                  child: Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          Colors.white.withOpacity(0.13),
                          Colors.white.withOpacity(0.015),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(15, 15, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.11),
                              ),
                            ),
                            child: _GuardPeriodGlyph(
                              isNight: visual.isNight,
                              is24h: visual.is24h,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isActive
                                            ? const Color(0xFF7CF2A7)
                                            : const Color(0xFFFFD43B),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        isActive
                                            ? 'GARDE EN COURS'
                                            : 'PROCHAINE GARDE',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.76),
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.45,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 5),
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        visual.category,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontFamily: 'SpaceGrotesk',
                                          fontSize: 21,
                                          height: 1.02,
                                          fontWeight: FontWeight.w900,
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
                                        color: Colors.white.withOpacity(0.11),
                                        borderRadius: BorderRadius.circular(999),
                                        border: Border.all(
                                          color: Colors.white.withOpacity(0.12),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _GuardPeriodGlyph(
                                            isNight: visual.isNight,
                                            is24h: visual.is24h,
                                            size: 13,
                                          ),
                                          const SizedBox(width: 5),
                                          Text(
                                            visual.period,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 38,
                            height: 38,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(13),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.11),
                              ),
                            ),
                            child: const Icon(
                              Icons.arrow_forward_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _GuardMetaChip(
                              icon: Icons.calendar_month_rounded,
                              text: dateLabel,
                              foreground: Colors.white,
                              background: Colors.white.withOpacity(0.095),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _GuardMetaChip(
                              icon: Icons.schedule_rounded,
                              text: timeLabel,
                              foreground: Colors.white,
                              background: Colors.white.withOpacity(0.095),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 9),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            countdownLabel,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.88),
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

'''
text = text[:next_start] + new_next + text[next_end:]

# 4) Make the announcements card consistently dark teal, including light app themes.
ann_start = text.index('class _HomeAnnouncementsCardState extends State<_HomeAnnouncementsCard> {')
ann_end = text.index('class _HomeAnnouncementsEmpty extends StatelessWidget {', ann_start)
ann = text[ann_start:ann_end]
old_outer = r'''      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.line),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withOpacity(0.07),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),'''
if old_outer not in ann:
    raise SystemExit('Announcements outer card anchor not found')
new_outer = r'''      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF071A18), Color(0xFF0B302A)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00C389).withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),'''
ann = ann.replace(old_outer, new_outer, 1)
ann = ann.replace(
    'color: AppColors.ink,\n                        fontFamily: \'SpaceGrotesk\'',
    'color: Colors.white,\n                        fontFamily: \'SpaceGrotesk\'',
    1,
)
ann = ann.replace(
    'color: AppColors.inkSoft,\n                        fontSize: 10.5,',
    'color: Colors.white.withOpacity(0.58),\n                        fontSize: 10.5,',
    1,
)
old_button = r'''              TextButton(
                onPressed: _openAnnouncements,
                child: const Text('Voir tout'),
              ),'''
new_button = r'''              TextButton(
                onPressed: _openAnnouncements,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF43E6A0),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  textStyle: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                child: const Text('Voir tout'),
              ),'''
if old_button not in ann:
    raise SystemExit('Announcements button anchor not found')
ann = ann.replace(old_button, new_button, 1)
text = text[:ann_start] + ann + text[ann_end:]

empty_start = text.index('class _HomeAnnouncementsEmpty extends StatelessWidget {')
empty_end = text.index('class _HomeAnnouncementPreview extends StatelessWidget {', empty_start)
new_empty = r'''class _HomeAnnouncementsEmpty extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback onTap;

  const _HomeAnnouncementsEmpty({
    required this.icon,
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(17),
      child: Container(
        minHeight: 78,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.035),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: Colors.white.withOpacity(0.07)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF20C986).withOpacity(0.08),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                icon,
                color: Colors.white.withOpacity(0.58),
                size: 21,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.70),
                  fontSize: 11.5,
                  height: 1.30,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFF43E6A0),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

'''
text = text[:empty_start] + new_empty + text[empty_end:]

# Make announcement previews blend into the teal card while preserving their data logic.
preview_start = text.index('class _HomeAnnouncementPreview extends StatelessWidget {')
preview_end = text.index('class _HomeHeroCard extends StatelessWidget {', preview_start) if 'class _HomeHeroCard extends StatelessWidget {' in text[preview_start:] else text.index('class _GuardVisualTheme {', preview_start)
# The hero is now preceded by _GuardVisualTheme; prefer that marker.
visual_marker = text.find('class _GuardVisualTheme {', preview_start)
if visual_marker != -1:
    preview_end = visual_marker
preview = text[preview_start:preview_end]
preview = preview.replace(
    'color: AppColors.paperAlt,',
    'color: Colors.white.withOpacity(0.04),',
    1,
)
preview = preview.replace(
    'color: AppColors.ink,',
    'color: Colors.white,',
)
preview = preview.replace(
    'color: AppColors.inkSoft,',
    'color: Colors.white.withOpacity(0.62),',
)
text = text[:preview_start] + preview + text[preview_end:]

PATH.write_text(text, encoding='utf-8')
print('Applied premium guard sky cards and announcements styling.')
