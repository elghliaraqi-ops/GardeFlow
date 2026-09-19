from pathlib import Path

EXPECTED = "version: 11.6.34+194"
TARGET = "version: 11.6.35+195"

pubspec = Path("pubspec.yaml")
pub = pubspec.read_text()
if EXPECTED not in pub:
    raise SystemExit("V11.6.35: base version mismatch")
pubspec.write_text(pub.replace(EXPECTED, TARGET, 1))

def replace_class(source: str, class_name: str, replacement: str) -> str:
    marker = f"class {class_name} "
    start = source.find(marker)
    if start < 0:
        raise SystemExit(f"V11.6.35: {class_name} not found")
    brace = source.find("{", start)
    depth = 0
    end = None
    for i in range(brace, len(source)):
        if source[i] == "{":
            depth += 1
        elif source[i] == "}":
            depth -= 1
            if depth == 0:
                end = i + 1
                break
    if end is None:
        raise SystemExit(f"V11.6.35: closing brace missing for {class_name}")
    return source[:start] + replacement.rstrip() + source[end:]

# ---------------------------------------------------------------------------
# 1) Bottom navigation: explicitly reserve the Android system-navigation inset.
# ---------------------------------------------------------------------------
home = Path("lib/screens/home_screen.dart")
h = home.read_text()

main_bottom_bar = r"""class _MainBottomBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onReminders;

  const _MainBottomBar({
    required this.selectedIndex,
    required this.onSelected,
    required this.onReminders,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    Widget item(
      int index,
      IconData icon,
      IconData selectedIcon,
      String label,
    ) {
      final selected = selectedIndex == index;
      return Expanded(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onSelected(index),
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(2, 6, 2, 5),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 38,
                    height: 28,
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.brandSoft
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      selected ? selectedIcon : icon,
                      color: selected
                          ? AppColors.brand
                          : AppColors.inkSoft,
                      size: 21,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 9,
                      height: 1.05,
                      fontWeight: FontWeight.w800,
                      color: selected
                          ? AppColors.brand
                          : AppColors.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      height: 72 + bottomInset,
      decoration: BoxDecoration(
        color: AppColors.card,
        border: const Border(
          top: BorderSide(color: AppColors.line),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withOpacity(0.08),
            blurRadius: 18,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: SizedBox(
          height: 72,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  item(
                    0,
                    Icons.home_outlined,
                    Icons.home_rounded,
                    'Accueil',
                  ),
                  item(
                    1,
                    Icons.calendar_month_outlined,
                    Icons.calendar_month_rounded,
                    'Planning',
                  ),
                  const SizedBox(width: 74),
                  item(
                    2,
                    Icons.badge_outlined,
                    Icons.badge_rounded,
                    'Annuaire',
                  ),
                  item(
                    3,
                    Icons.medical_services_outlined,
                    Icons.medical_services_rounded,
                    'Astreintes',
                  ),
                ],
              ),
              Positioned(
                top: -18,
                child: Tooltip(
                  message: 'Réglages des rappels de garde',
                  child: Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      onTap: onReminders,
                      customBorder: const CircleBorder(),
                      child: Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppColors.brandDark,
                              AppColors.brand,
                            ],
                          ),
                          border: Border.all(
                            color: AppColors.card,
                            width: 4,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.brand.withOpacity(0.30),
                              blurRadius: 15,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.notifications_active_rounded,
                          color: Colors.white,
                          size: 27,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const Positioned(
                top: 42,
                child: Text(
                  'Rappels',
                  style: TextStyle(
                    color: AppColors.brandDark,
                    fontSize: 8.5,
                    height: 1,
                    fontWeight: FontWeight.w900,
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

h = replace_class(h, "_MainBottomBar", main_bottom_bar)
home.write_text(h)

# ---------------------------------------------------------------------------
# 2) Profile footer: show the real transparent Elghali signature, not only text.
# ---------------------------------------------------------------------------
profile = Path("lib/screens/profile_screen.dart")
p = profile.read_text()

old_signature = """              Opacity(
                opacity: 0.92,
                child: Image.asset(
                  'assets/branding/elghali_signature.webp',
                  width: 190,
                  height: 88,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
              const SizedBox(height: 5),"""

new_signature = """              Image.asset(
                'assets/branding/elghali_signature.webp',
                width: 235,
                height: 105,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                gaplessPlayback: true,
              ),
              const SizedBox(height: 2),"""

if old_signature not in p:
    raise SystemExit("V11.6.35: signature block not found")
profile.write_text(p.replace(old_signature, new_signature, 1))

# ---------------------------------------------------------------------------
# 3) Daily news: display the latest synchronized official items, including
#    website fallback feeds when Instagram API credentials are unavailable.
# ---------------------------------------------------------------------------
news = Path("lib/screens/daily_news_section.dart")
n = news.read_text()

old_load_tail = """    final all = rows.map(_DailyNewsItem.fromMap).toList();
    if (all.isEmpty) return all;

    final now = DateTime.now();
    final today = all.where((item) {
      final local = item.postedAt.toLocal();
      return local.year == now.year &&
          local.month == now.month &&
          local.day == now.day;
    }).toList();

    return (today.isNotEmpty ? today : all).take(8).toList();"""

new_load_tail = """    final all = rows.map(_DailyNewsItem.fromMap).toList();
    return all.take(8).toList();"""

if old_load_tail not in n:
    raise SystemExit("V11.6.35: news load-tail block not found")
n = n.replace(old_load_tail, new_load_tail, 1)

n = n.replace(
    "'Voir sur Instagram'",
    "'Ouvrir la source'",
)

old_clean = """    final value = (caption ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    return value.isEmpty ? 'Nouvelle publication.' : value;"""
new_clean = """    final value = (caption ?? '')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&nbsp;', ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
    return value.isEmpty ? 'Nouvelle actualité.' : value;"""
if old_clean not in n:
    raise SystemExit("V11.6.35: news caption cleaner not found")
n = n.replace(old_clean, new_clean, 1)

old_relative = """    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 60) return '${diff.inMinutes.clamp(1, 59)} min';
    if (diff.inHours < 24) return '${diff.inHours} h';
    if (diff.inDays == 1) return 'Hier';
    return DateFormat('d MMM', 'fr_FR').format(date);"""

new_relative = """    final now = DateTime.now();
    if (date.isAfter(now)) {
      return 'À venir · ${DateFormat('d MMM', 'fr_FR').format(date)}';
    }
    final diff = now.difference(date);
    if (diff.inMinutes < 60) return '${diff.inMinutes.clamp(1, 59)} min';
    if (diff.inHours < 24) return '${diff.inHours} h';
    if (diff.inDays == 1) return 'Hier';
    return DateFormat('d MMM', 'fr_FR').format(date);"""
if old_relative not in n:
    raise SystemExit("V11.6.35: news relative-date block not found")
n = n.replace(old_relative, new_relative, 1)

n = n.replace(
    "'Le flux Instagram se synchronise.'",
    "'Les dernières actualités officielles arrivent ici.'",
)
n = n.replace(
    "'Vous pouvez déjà accéder aux sources officielles :'",
    "'Accès direct aux comptes officiels :'",
)

news.write_text(n)

print("GardeFlow V11.6.35: signature visible + nav Android safe + actualités officielles")
