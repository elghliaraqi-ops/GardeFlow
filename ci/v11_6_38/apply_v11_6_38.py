from pathlib import Path
import re

EXPECTED="version: 11.6.37+197"
TARGET="version: 11.6.38+198"
p=Path("pubspec.yaml"); s=p.read_text()
if EXPECTED not in s: raise SystemExit("V11.6.38 base mismatch")
p.write_text(s.replace(EXPECTED,TARGET,1))

# HOME: total + Urgences + Service, Junior first, roomier Astreintes.
p=Path("lib/screens/home_screen.dart"); s=p.read_text()

anchor="""  int _guardsThisMonth(AppUser me, DateTime now) {
    return appState.planning.where((entry) {
      if (entry.ownerId != me.id && entry.ownerPhone != me.phone) return false;
      if (entry.shiftId == 'conge') return false;
      final date = DateTime.tryParse(entry.dateStr);
      if (date == null) return false;
      return date.year == now.year && date.month == now.month;
    }).length;
  }"""
if anchor not in s: raise SystemExit("monthly guard anchor missing")
replacement=anchor+"""

  int _guardsThisMonthByCategory(AppUser me, DateTime now, {required bool urgence}) {
    return appState.planning.where((entry) {
      if (entry.ownerId != me.id && entry.ownerPhone != me.phone) return false;
      if (entry.shiftId == 'conge') return false;
      final date = DateTime.tryParse(entry.dateStr);
      if (date == null || date.year != now.year || date.month != now.month) return false;
      final id = entry.shiftId.toLowerCase();
      final isUrgence = id.contains('urg');
      return urgence ? isUrgence : !isUrgence;
    }).length;
  }"""
s=s.replace(anchor,replacement,1)

# Insert category counts after monthlyCount declaration.
m=re.search(r"(final monthlyCount\s*=\s*_guardsThisMonth\(me, now\);)",s)
if not m: raise SystemExit("monthlyCount declaration missing")
s=s[:m.end()]+"""
    final urgenceMonthlyCount = _guardsThisMonthByCategory(me, now, urgence: true);
    final serviceMonthlyCount = _guardsThisMonthByCategory(me, now, urgence: false);"""+s[m.end():]

old="""                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.calendar_month_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 7),
                        Text(
                          '$monthlyCount garde${monthlyCount > 1 ? 's' : ''} ce mois-ci',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),"""
new="""                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.calendar_month_rounded, color: Colors.white, size: 18),
                            const SizedBox(width: 7),
                            Text(
                              '$monthlyCount garde${monthlyCount > 1 ? 's' : ''} au total ce mois',
                              style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w900),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            _MonthlyGuardChip(label: 'Urgences', value: urgenceMonthlyCount),
                            _MonthlyGuardChip(label: 'Service', value: serviceMonthlyCount),
                          ],
                        ),
                      ],
                    ),"""
if old not in s: raise SystemExit("monthly hero block missing")
s=s.replace(old,new,1)

# Junior by default and first in switch.
s=s.replace("  bool _showSenior = true;","  bool _showSenior = false;",1)
s=s.replace("""children: const [
                AstreinteScreen(embedded: true),
                JuniorOnCallScreen(embedded: true),
              ],""","""children: const [
                AstreinteScreen(embedded: true),
                JuniorOnCallScreen(embedded: true),
              ],""",1)

# Make astreinte header more spacious and explanatory.
old="""          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: _AstreinteModeSwitch("""
new="""          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Astreintes',
                  style: TextStyle(fontFamily: 'SpaceGrotesk', fontSize: 25, fontWeight: FontWeight.w900, color: AppColors.ink),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Consultez d’abord le planning des juniors, ou basculez vers les astreintes séniors.',
                  style: TextStyle(fontSize: 12.5, height: 1.4, fontWeight: FontWeight.w600, color: AppColors.inkSoft),
                ),
                const SizedBox(height: 14),
                _AstreinteModeSwitch("""
if old not in s: raise SystemExit("astreinte header anchor missing")
s=s.replace(old,new,1)
old="""              },
            ),
          ),
          Expanded("""
new="""              },
            ),
              ],
            ),
          ),
          Expanded("""
# only first after astreinte header
idx=s.find(old,s.find("class _AstreintesHubViewState"))
if idx<0: raise SystemExit("astreinte close anchor missing")
s=s[:idx]+s[idx:].replace(old,new,1)

# Junior button first visually.
old="""          Expanded(
            child: _AstreinteModeButton(
              label: 'Astreinte Senior',
              icon: Icons.photo_library_rounded,
              selected: showSenior,
              onTap: () => onChanged(true),
            ),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: _AstreinteModeButton(
              label: 'Astreinte Junior',
              icon: Icons.calendar_view_week_rounded,
              selected: !showSenior,
              onTap: () => onChanged(false),
            ),
          ),"""
new="""          Expanded(
            child: _AstreinteModeButton(
              label: 'Astreinte Junior',
              icon: Icons.calendar_view_week_rounded,
              selected: !showSenior,
              onTap: () => onChanged(false),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: _AstreinteModeButton(
              label: 'Astreinte Senior',
              icon: Icons.photo_library_rounded,
              selected: showSenior,
              onTap: () => onChanged(true),
            ),
          ),"""
if old not in s: raise SystemExit("astreinte switch order missing")
s=s.replace(old,new,1)
s=s.replace("      height: 50,","      height: 58,",1)

# Add chip widget before BadgeCount.
marker="class _BadgeCount extends StatelessWidget {"
chip="""class _MonthlyGuardChip extends StatelessWidget {
  final String label;
  final int value;
  const _MonthlyGuardChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.13),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: Colors.white.withOpacity(0.13)),
        ),
        child: Text(
          '$label · $value',
          style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800),
        ),
      );
}

"""
if marker not in s: raise SystemExit("BadgeCount marker missing")
s=s.replace(marker,chip+marker,1)
p.write_text(s)

# NEWS: keep horizontal briefs, add vertical detailed feed below.
p=Path("lib/screens/daily_news_section.dart"); s=p.read_text()
old="""              _NewsEmptyState(
                profiles: _profiles,
                onOpen: _open,
                hasError: snapshot.hasError,
              ),
          ],"""
new="""              _NewsEmptyState(
                profiles: _profiles,
                onOpen: _open,
                hasError: snapshot.hasError,
              ),
            if (items.isNotEmpty) ...[
              const SizedBox(height: 28),
              const Text(
                'Fil d’actualités',
                style: TextStyle(
                  fontFamily: 'SpaceGrotesk',
                  color: AppColors.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Plus de détails sur les dernières publications Instagram',
                style: TextStyle(color: AppColors.inkSoft, fontSize: 11.5, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              for (final item in items) ...[
                _NewsDetailCard(item: item, onTap: () => _open(item.permalink)),
                const SizedBox(height: 12),
              ],
            ],
          ],"""
if old not in s: raise SystemExit("news build end anchor missing")
s=s.replace(old,new,1)

marker="class _NewsLoading extends StatelessWidget {"
detail="""class _NewsDetailCard extends StatelessWidget {
  final _DailyNewsItem item;
  final VoidCallback onTap;
  const _NewsDetailCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final imageUrl = item.cachedMediaUrl ?? item.thumbnailUrl ?? item.mediaUrl;
    final caption = _NewsCard._cleanCaption(item.caption);
    final time = _NewsCard._relativeDate(item.postedAt.toLocal());
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (imageUrl != null && imageUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(21)),
                  child: Image.network(
                    imageUrl,
                    width: double.infinity,
                    height: 210,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.camera_alt_rounded, size: 16, color: AppColors.danger),
                      const SizedBox(width: 7),
                      Expanded(child: Text(item.displayName, style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.ink))),
                      Text(time, style: const TextStyle(fontSize: 10.5, color: AppColors.inkFaint, fontWeight: FontWeight.w700)),
                    ]),
                    const SizedBox(height: 11),
                    Text(caption, style: const TextStyle(fontSize: 13, height: 1.48, color: AppColors.inkSoft, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    const Row(children: [
                      Text('Voir la publication sur Instagram', style: TextStyle(color: AppColors.brand, fontSize: 11.5, fontWeight: FontWeight.w900)),
                      SizedBox(width: 4),
                      Icon(Icons.open_in_new_rounded, size: 14, color: AppColors.brand),
                    ]),
                  ],
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
if marker not in s: raise SystemExit("news loading marker missing")
s=s.replace(marker,detail+marker,1)
p.write_text(s)

# PROFILE: guaranteed visible signature area. Keep exact image, add visible fallback lettering behind it.
p=Path("lib/screens/profile_screen.dart"); s=p.read_text()
old="""              Image.asset(
                'assets/branding/elghali_signature.webp',
                width: 235,
                height: 105,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                gaplessPlayback: true,
              ),"""
new="""              Container(
                width: 270,
                height: 120,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.line),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Text(
                      'Elghali',
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 38,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1.5,
                      ),
                    ),
                    Image.asset(
                      'assets/branding/elghali_signature.webp',
                      width: 245,
                      height: 110,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),"""
if old not in s: raise SystemExit("signature block missing")
s=s.replace(old,new,1)
p.write_text(s)

# Notifications: preserve dismissed notification keys across backend reload/login.
p=Path("lib/state/app_state.dart"); s=p.read_text()
old="""        currentUser=user;
        _applyReminderPrefsForCurrentUser();
        await _reloadFromBackend();"""
new="""        currentUser=user;
        _applyReminderPrefsForCurrentUser();
        final locallyDismissedNotifications = Set<String>.from(_dismissedNotificationKeys);
        await _reloadFromBackend();
        _dismissedNotificationKeys.addAll(locallyDismissedNotifications);"""
if old not in s: raise SystemExit("login reload anchor missing")
s=s.replace(old,new,1)
p.write_text(s)

# Backend: expose existing secure admin RPC.
p=Path("lib/services/supabase_backend_service.dart"); s=p.read_text()
marker="  Future<List<AuditEvent>> fetchAudit({int limit = 200}) async {"
if marker not in s: raise SystemExit("fetchAudit marker missing")
method="""  Future<int> clearAuditLog() async {
    final value = await client.rpc('admin_clear_audit_log');
    return (value as num?)?.toInt() ?? 0;
  }

"""
s=s.replace(marker,method+marker,1)
p.write_text(s)

# Audit UI: clean button + confirmation.
p=Path("lib/screens/audit_screen.dart"); s=p.read_text()
anchor="""  void _refresh() {
    setState(() {
      _future = SupabaseBackendService.instance.fetchAudit();
    });
  }"""
new=anchor+"""

  Future<void> _clearAudit() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
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
  }"""
if anchor not in s: raise SystemExit("audit refresh anchor missing")
s=s.replace(anchor,new,1)
old="""        actions: [
          SoftIconButton(
            icon: Icons.refresh_rounded,"""
new="""        actions: [
          SoftIconButton(
            icon: Icons.delete_sweep_outlined,
            onTap: _clearAudit,
            tooltip: 'Nettoyer l’historique',
          ),
          const SizedBox(width: 4),
          SoftIconButton(
            icon: Icons.refresh_rounded,"""
if old not in s: raise SystemExit("audit appbar anchor missing")
s=s.replace(old,new,1)
p.write_text(s)

print("GardeFlow V11.6.38: dashboard counters, dual news feed, Junior-first Astreintes, signature visibility, persistent cleanup, audit cleanup")
