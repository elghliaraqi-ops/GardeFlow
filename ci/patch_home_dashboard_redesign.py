from pathlib import Path

path = Path('source/lib/screens/home_screen.dart')
text = path.read_text(encoding='utf-8')


def replace_once(old: str, new: str, label: str) -> None:
    global text
    if old not in text:
        raise SystemExit(f'{label} anchor not found')
    text = text.replace(old, new, 1)


replace_once(
    """  int _tab = 0;\n  final GlobalKey _newsFeedKey = GlobalKey();\n  final ScrollController _homeScrollController = ScrollController();\n""",
    """  int _tab = 0;\n  int _homeRefreshTick = 0;\n  final GlobalKey _newsFeedKey = GlobalKey();\n  final ScrollController _homeScrollController = ScrollController();\n""",
    'home state',
)

replace_once(
    """                    scrollController: _homeScrollController,\n                    onOpenPlanning: () => setState(() => _tab = 1),\n""",
    """                    scrollController: _homeScrollController,\n                    refreshToken: _homeRefreshTick,\n                    onOpenPlanning: () => setState(() => _tab = 1),\n""",
    'dashboard call',
)

replace_once(
    """        selectedIndex: _tab,\n        onSelected: (value) => setState(() => _tab = value),\n        onReminders: () => Navigator.push(\n""",
    """        selectedIndex: _tab,\n        onSelected: (value) => _handleTabSelection(value, appState),\n        onReminders: () => Navigator.push(\n""",
    'bottom bar callback',
)

home_methods = r"""  void _handleTabSelection(int value, AppState appState) {
    if (value != 0) {
      if (_tab != value) setState(() => _tab = value);
      return;
    }

    if (_tab != 0) setState(() => _tab = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_scrollHomeToTopAndRefresh(appState));
    });
  }

  Future<void> _scrollHomeToTopAndRefresh(AppState appState) async {
    if (_homeScrollController.hasClients) {
      await _homeScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
      );
    }
    try {
      await appState.refreshBackend();
    } catch (_) {
      // L'accueil reste fluide même si le réseau est momentanément indisponible.
    }
    if (mounted) setState(() => _homeRefreshTick++);
  }

"""
replace_once(
    "  Future<void> _showQuickAdd(BuildContext context, AppState appState) async {\n",
    home_methods + "  Future<void> _showQuickAdd(BuildContext context, AppState appState) async {\n",
    'home methods',
)

replace_once(
    """  final GlobalKey newsFeedKey;\n  final ScrollController scrollController;\n  final VoidCallback onOpenPlanning;\n""",
    """  final GlobalKey newsFeedKey;\n  final ScrollController scrollController;\n  final int refreshToken;\n  final VoidCallback onOpenPlanning;\n""",
    'dashboard fields',
)

replace_once(
    """    required this.newsFeedKey,\n    required this.scrollController,\n    required this.onOpenPlanning,\n""",
    """    required this.newsFeedKey,\n    required this.scrollController,\n    required this.refreshToken,\n    required this.onOpenPlanning,\n""",
    'dashboard constructor',
)

replace_once(
    """          _NextGuardCard(entry: next, onTap: onOpenPlanning),\n          const SizedBox(height: 14),\n          PracticeHomeSummary(appState: appState, user: me),\n""",
    """          _NextGuardCard(entry: next, onTap: onOpenPlanning),\n          const SizedBox(height: 14),\n          _HomeAnnouncementsCard(\n            appState: appState,\n            refreshToken: refreshToken,\n          ),\n          const SizedBox(height: 14),\n          PracticeHomeSummary(appState: appState, user: me),\n""",
    'dashboard order',
)

announcements_code = r"""class _HomeAnnouncement {
  final String id;
  final String authorId;
  final String authorName;
  final String hospital;
  final String dateStr;
  final String shiftId;
  final String message;

  const _HomeAnnouncement({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.hospital,
    required this.dateStr,
    required this.shiftId,
    required this.message,
  });

  factory _HomeAnnouncement.fromMap(Map<String, dynamic> map) {
    return _HomeAnnouncement(
      id: '${map['id'] ?? ''}',
      authorId: '${map['author_id'] ?? ''}',
      authorName: '${map['author_name'] ?? 'Médecin'}',
      hospital: '${map['hospital'] ?? ''}',
      dateStr: '${map['date_str'] ?? ''}',
      shiftId: '${map['shift_id'] ?? ''}',
      message: '${map['message'] ?? ''}'.trim(),
    );
  }
}

class _HomeAnnouncementsCard extends StatefulWidget {
  final AppState appState;
  final int refreshToken;

  const _HomeAnnouncementsCard({
    required this.appState,
    required this.refreshToken,
  });

  @override
  State<_HomeAnnouncementsCard> createState() => _HomeAnnouncementsCardState();
}

class _HomeAnnouncementsCardState extends State<_HomeAnnouncementsCard> {
  late Future<List<_HomeAnnouncement>> _future;
  StreamSubscription? _realtime;

  @override
  void initState() {
    super.initState();
    _future = _load();
    final backend = SupabaseBackendService.instance;
    if (backend.enabled) {
      _realtime = backend.client
          .from('public_announcements')
          .stream(primaryKey: ['id'])
          .listen((_) => unawaited(_reload()), onError: (_) {});
    }
  }

  @override
  void didUpdateWidget(covariant _HomeAnnouncementsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      unawaited(_reload());
    }
  }

  @override
  void dispose() {
    _realtime?.cancel();
    super.dispose();
  }

  bool _isRelevant(_HomeAnnouncement item) {
    final me = widget.appState.currentUser;
    if (me == null) return false;
    if (item.authorId == me.id) return true;
    if (item.hospital != me.hospital) return false;
    final author =
        widget.appState.users.where((u) => u.id == item.authorId).firstOrNull;
    if (author != null &&
        widget.appState.promotionExchangeBlocked(
          me,
          author,
          sourceShiftId: item.shiftId,
        )) {
      return false;
    }
    return true;
  }

  Future<List<_HomeAnnouncement>> _load() async {
    final backend = SupabaseBackendService.instance;
    if (!backend.enabled) return const <_HomeAnnouncement>[];
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final rows = await backend.client
        .from('public_announcements')
        .select()
        .isFilter('closed_at', null)
        .gte('date_str', today)
        .order('created_at', ascending: false)
        .limit(20);
    return (rows as List)
        .map(
          (raw) => _HomeAnnouncement.fromMap(
            Map<String, dynamic>.from(raw as Map),
          ),
        )
        .where(_isRelevant)
        .take(5)
        .toList(growable: false);
  }

  Future<void> _reload() async {
    if (!mounted) return;
    final next = _load();
    setState(() => _future = next);
    try {
      await next;
    } catch (_) {
      // La carte conserve son état d'erreur sans bloquer l'accueil.
    }
  }

  Future<void> _openAnnouncements() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AnnouncementsScreen()),
    );
    if (mounted) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 13),
      decoration: BoxDecoration(
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
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.brand.withOpacity(0.22),
                      AppColors.brandBright.withOpacity(0.10),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.swap_horiz_rounded,
                  color: AppColors.brandBright,
                  size: 23,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Annonces & échanges',
                      style: TextStyle(
                        color: AppColors.ink,
                        fontFamily: 'SpaceGrotesk',
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Dernières gardes proposées par vos collègues',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.inkSoft,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _openAnnouncements,
                child: const Text('Voir tout'),
              ),
            ],
          ),
          const SizedBox(height: 11),
          FutureBuilder<List<_HomeAnnouncement>>(
            future: _future,
            builder: (context, snapshot) {
              final items = snapshot.data ?? const <_HomeAnnouncement>[];
              if (snapshot.connectionState == ConnectionState.waiting &&
                  items.isEmpty) {
                return const SizedBox(
                  height: 86,
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              if (snapshot.hasError && items.isEmpty) {
                return _HomeAnnouncementsEmpty(
                  icon: Icons.cloud_off_rounded,
                  text: 'Annonces momentanément indisponibles',
                  onTap: _reload,
                );
              }
              if (items.isEmpty) {
                return _HomeAnnouncementsEmpty(
                  icon: Icons.forum_outlined,
                  text: 'Aucune annonce active pour le moment',
                  onTap: _openAnnouncements,
                );
              }
              return SizedBox(
                height: 104,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 9),
                  itemBuilder: (context, index) => _HomeAnnouncementPreview(
                    item: items[index],
                    onTap: _openAnnouncements,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HomeAnnouncementsEmpty extends StatelessWidget {
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
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 78,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.paperAlt,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.inkFaint, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: AppColors.inkSoft,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppColors.inkFaint),
          ],
        ),
      ),
    );
  }
}

class _HomeAnnouncementPreview extends StatelessWidget {
  final _HomeAnnouncement item;
  final VoidCallback onTap;

  const _HomeAnnouncementPreview({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final shift = ShiftCatalog.byId(item.shiftId);
    final parsedDate = DateTime.tryParse(item.dateStr);
    final dateLabel = parsedDate == null
        ? item.dateStr
        : DateFormat('EEE d MMM', 'fr_FR').format(parsedDate);
    final isUrgence = item.shiftId.toLowerCase().contains('urg');
    final category = isUrgence ? 'Urgences' : 'Service';
    final message =
        item.message.isEmpty ? 'Disponible pour un échange' : item.message;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          width: 270,
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
          decoration: BoxDecoration(
            color: AppColors.paperAlt,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: shift.color.withOpacity(0.32)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    constraints: const BoxConstraints(maxWidth: 165),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: shift.color,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$category · ${shift.label}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: shift.textColor,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    dateLabel,
                    style: TextStyle(
                      color: AppColors.inkSoft,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                item.authorName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.inkSoft,
                  fontSize: 10.5,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
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

insert_anchor = 'class _HomeHeroCard extends StatelessWidget {'
if insert_anchor not in text:
    raise SystemExit('home hero insertion anchor not found')
text = text.replace(insert_anchor, announcements_code + insert_anchor, 1)

guard_start = text.index(
    '    final current = entry!;',
    text.index('class _NextGuardCard'),
)
guard_end = text.index('\nclass _GuardMetaChip', guard_start)

guard_code = r"""    final current = entry!;
    final shift = ShiftCatalog.byId(current.shiftId);
    final shiftId = shift.id.toLowerCase();
    final shiftLabel = shift.label.trim().toLowerCase();

    final isUrgence = shiftId.startsWith('urg-') ||
        shiftId.contains('urgence') ||
        shiftLabel.contains('urgence');
    final is24h = shiftId.contains('24h') ||
        shiftId.contains('24-h') ||
        shiftLabel.contains('24h');
    final isNight =
        !is24h && (shiftId.contains('nuit') || shiftLabel.contains('nuit'));

    final category = isUrgence ? 'URGENCES' : 'SERVICE';
    final period = is24h ? '24H' : (isNight ? 'Nuit' : 'Jour');

    final date = DateTime.tryParse(current.dateStr);
    final dateLabel = date == null
        ? current.dateStr
        : DateFormat('EEE d MMMM', 'fr_FR').format(date);
    final timeLabel = shift.start != null && shift.end != null
        ? '${shift.start} → ${shift.end}'
        : is24h
            ? '08:00 → 08:00'
            : isNight
                ? '20:00 → 08:00'
                : '08:00 → 20:00';

    late final List<Color> colors;
    late final Color foreground;
    if (isUrgence) {
      if (isNight) {
        colors = const [Color(0xFF310812), Color(0xFF7A1D31)];
        foreground = Colors.white;
      } else if (is24h) {
        colors = const [Color(0xFFF58A1F), Color(0xFFFFB34E)];
        foreground = const Color(0xFF3A1B00);
      } else {
        colors = const [Color(0xFFFFD9DE), Color(0xFFFF8798)];
        foreground = const Color(0xFF48131C);
      }
    } else {
      if (isNight) {
        colors = const [Color(0xFF06152E), Color(0xFF174F89)];
        foreground = Colors.white;
      } else if (is24h) {
        colors = const [Color(0xFFA9E6FF), Color(0xFF4DBDEA)];
        foreground = const Color(0xFF0B3048);
      } else {
        colors = const [Color(0xFFD9F2FF), Color(0xFF75C7F4)];
        foreground = const Color(0xFF092B47);
      }
    }

    final surface = foreground.withOpacity(0.09);
    final surfaceBorder = foreground.withOpacity(0.13);

    String countdownLabel = 'À venir';
    if (date != null) {
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
          padding: const EdgeInsets.fromLTRB(16, 15, 14, 15),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: colors.last.withOpacity(0.22),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                right: -30,
                top: -40,
                child: Container(
                  width: 132,
                  height: 132,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: foreground.withOpacity(0.06),
                  ),
                ),
              ),
              Positioned(
                right: 42,
                bottom: -54,
                child: Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: foreground.withOpacity(0.045),
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: surfaceBorder),
                        ),
                        child: Center(
                          child: _GuardPeriodGlyph(
                            isNight: isNight,
                            is24h: is24h,
                            size: 27,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'PROCHAINE GARDE · $countdownLabel',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: foreground.withOpacity(0.72),
                                fontSize: 9.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.45,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    category,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: foreground,
                                      fontFamily: 'SpaceGrotesk',
                                      fontSize: 21,
                                      height: 1.05,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: surface,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(color: surfaceBorder),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _GuardPeriodGlyph(
                                        isNight: isNight,
                                        is24h: is24h,
                                        size: 14,
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        period,
                                        style: TextStyle(
                                          color: foreground,
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
                        decoration: BoxDecoration(
                          color: surface,
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(color: surfaceBorder),
                        ),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          color: foreground.withOpacity(0.90),
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 13),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      _GuardMetaChip(
                        icon: Icons.calendar_month_rounded,
                        text: dateLabel,
                        foreground: foreground,
                        background: surface,
                      ),
                      _GuardMetaChip(
                        icon: Icons.schedule_rounded,
                        text: timeLabel,
                        foreground: foreground,
                        background: surface,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuardPeriodGlyph extends StatelessWidget {
  final bool isNight;
  final bool is24h;
  final double size;

  const _GuardPeriodGlyph({
    required this.isNight,
    required this.is24h,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    if (is24h) {
      return SizedBox(
        width: size * 1.35,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              top: 0,
              child: Icon(
                Icons.wb_sunny_rounded,
                color: const Color(0xFFFFD43B),
                size: size * 0.78,
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Icon(
                Icons.nightlight_round,
                color: Colors.white,
                size: size * 0.76,
              ),
            ),
          ],
        ),
      );
    }
    return Icon(
      isNight ? Icons.nightlight_round : Icons.wb_sunny_rounded,
      color: isNight ? Colors.white : const Color(0xFFFFD43B),
      size: size,
    );
  }
}
"""

text = text[:guard_start] + guard_code + text[guard_end:]

chip_start = text.index('class _GuardMetaChip extends StatelessWidget {')
chip_end = text.index('\nclass _DashboardAction extends StatelessWidget {', chip_start)
chip_code = r"""class _GuardMetaChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color foreground;
  final Color background;

  const _GuardMetaChip({
    required this.icon,
    required this.text,
    this.foreground = Colors.white,
    this.background = const Color(0x1FFFFFFF),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: foreground.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: foreground.withOpacity(0.88), size: 14),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: foreground.withOpacity(0.94),
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
"""
text = text[:chip_start] + chip_code + text[chip_end:]

replace_once(
    """              Positioned(\n                top: 42,\n                child: Text(\n                  'Rappels',\n                  style: TextStyle(\n                    color: Colors.white,\n                    fontSize: 8.5,\n                    height: 1,\n                    fontWeight: FontWeight.w900,\n                  ),\n                ),\n              ),\n""",
    """              Positioned(\n                top: 42,\n                child: Text(\n                  'Rappels',\n                  style: TextStyle(\n                    color: AppColors.ink,\n                    fontSize: 9.5,\n                    height: 1,\n                    fontWeight: FontWeight.w900,\n                  ),\n                ),\n              ),\n""",
    'reminder label',
)

path.write_text(text, encoding='utf-8')
