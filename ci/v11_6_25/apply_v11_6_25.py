from pathlib import Path

EXPECTED = "version: 11.6.24+184"
TARGET = "version: 11.6.25+185"

pubspec = Path("pubspec.yaml")
pub = pubspec.read_text()
if EXPECTED not in pub:
    raise SystemExit("V11.6.25: base version mismatch")
pubspec.write_text(pub.replace(EXPECTED, TARGET, 1))

home = Path("lib/screens/home_screen.dart")
text = home.read_text()

news_import = "import 'daily_news_section.dart';"
if news_import not in text:
    anchor = "import 'settings_screen.dart';"
    if anchor not in text:
        raise SystemExit("V11.6.25: settings import anchor missing")
    text = text.replace(anchor, anchor + "\n" + news_import, 1)

def replace_class(source: str, class_name: str, replacement: str) -> str:
    marker = f"class {class_name} "
    start = source.find(marker)
    if start < 0:
        raise SystemExit(f"V11.6.25: {class_name} not found")
    brace = source.find("{", start)
    if brace < 0:
        raise SystemExit(f"V11.6.25: opening brace missing for {class_name}")
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
        raise SystemExit(f"V11.6.25: closing brace missing for {class_name}")
    return source[:start] + replacement.rstrip() + source[end:]

dashboard = r"""class _DashboardView extends StatelessWidget {
  final AppState appState;
  final VoidCallback onOpenPlanning;
  final VoidCallback onOpenDirectory;
  final VoidCallback onOpenProfile;

  const _DashboardView({
    required this.appState,
    required this.onOpenPlanning,
    required this.onOpenDirectory,
    required this.onOpenProfile,
  });

  List<PlanningEntry> _futureGuards(AppUser me) {
    final entries = appState.planning
        .where((entry) =>
            (entry.ownerId == me.id || entry.ownerPhone == me.phone) &&
            entry.shiftId != 'conge' &&
            appState.isPlanningEntryApproved(entry) &&
            !appState.guardHasStarted(entry))
        .toList()
      ..sort((a, b) {
        final ad = DateTime.parse(a.dateStr);
        final bd = DateTime.parse(b.dateStr);
        final cmp = ad.compareTo(bd);
        if (cmp != 0) return cmp;
        final ashift = ShiftCatalog.byId(a.shiftId);
        final bshift = ShiftCatalog.byId(b.shiftId);
        return (ashift.start ?? '').compareTo(bshift.start ?? '');
      });
    return entries;
  }

  int _guardsThisMonth(AppUser me, DateTime now) {
    return appState.planning.where((entry) {
      if (entry.ownerId != me.id && entry.ownerPhone != me.phone) return false;
      if (entry.shiftId == 'conge') return false;
      final date = DateTime.tryParse(entry.dateStr);
      if (date == null) return false;
      return date.year == now.year && date.month == now.month;
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    final me = appState.currentUser;
    if (me == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final future = _futureGuards(me);
    final next = future.isEmpty ? null : future.first;
    final now = DateTime.now();
    final hour = now.hour;
    final isNight = hour >= 18 || hour < 6;
    final greeting = isNight ? 'Bonsoir' : 'Bonjour';
    final monthlyCount = _guardsThisMonth(me, now);

    final rawDate = DateFormat('EEEE d MMMM yyyy', 'fr_FR').format(now);
    final dateLabel = rawDate.isEmpty
        ? ''
        : rawDate[0].toUpperCase() + rawDate.substring(1);
    final timeLabel = DateFormat('HH:mm').format(now);

    final heroColors = isNight
        ? const [Color(0xFF143B2C), Color(0xFF071C15)]
        : const [Color(0xFF22A764), Color(0xFF0B6C42)];

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 32),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: heroColors,
            ),
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: AppColors.brand.withOpacity(isNight ? 0.12 : 0.20),
                blurRadius: 28,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                right: -8,
                top: -14,
                child: Icon(
                  isNight
                      ? Icons.nightlight_round
                      : Icons.wb_sunny_rounded,
                  size: 104,
                  color: Colors.white.withOpacity(0.12),
                ),
              ),
              Positioned(
                right: 18,
                bottom: -34,
                child: Container(
                  width: 82,
                  height: 82,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.055),
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$greeting Dr ${me.nom}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'SpaceGrotesk',
                      fontSize: 30,
                      height: 1.08,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.7,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        isNight
                            ? Icons.dark_mode_rounded
                            : Icons.light_mode_rounded,
                        color: Colors.white.withOpacity(0.86),
                        size: 18,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          'On est le $dateLabel, il est $timeLabel',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.90),
                            fontSize: 13.5,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 17),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.13),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.14),
                      ),
                    ),
                    child: Row(
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
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Prochaine garde à venir',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontFamily: 'SpaceGrotesk',
                fontWeight: FontWeight.w900,
                color: AppColors.ink,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          next == null
              ? 'Aucune garde validée à venir pour le moment.'
              : 'Voici votre prochaine garde programmée.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.inkSoft,
                fontWeight: FontWeight.w500,
              ),
        ),
        const SizedBox(height: 14),
        _NextGuardCard(
          entry: next,
          onTap: onOpenPlanning,
        ),
        const SizedBox(height: 28),
        const DailyNewsSection(),
      ],
    );
  }
}
"""

text = replace_class(text, "_DashboardView", dashboard)
home.write_text(text)

news = Path("lib/screens/daily_news_section.dart")
news.write_text(r"""import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';

class DailyNewsSection extends StatefulWidget {
  const DailyNewsSection({super.key});

  @override
  State<DailyNewsSection> createState() => _DailyNewsSectionState();
}

class _DailyNewsSectionState extends State<DailyNewsSection> {
  late Future<List<_DailyNewsItem>> _future;

  static const _profiles = <_NewsProfile>[
    _NewsProfile('AMI UM6', 'https://www.instagram.com/ami_um6/'),
    _NewsProfile('UM6SS', 'https://www.instagram.com/um6ss/'),
    _NewsProfile(
      'HUIM6 Bouskoura',
      'https://www.instagram.com/huim6bouskoura/',
    ),
    _NewsProfile('HUIM6 Rabat', 'https://www.instagram.com/huim6rabat/'),
    _NewsProfile(
      'Hôpital Cheikh Khalifa',
      'https://www.instagram.com/hopital.cheikh.khalifa/',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _future = _loadNews();
  }

  Future<List<_DailyNewsItem>> _loadNews() async {
    final response = await Supabase.instance.client
        .from('daily_news_posts')
        .select(
          'external_id,source_key,username,display_name,caption,media_type,media_url,cached_media_url,thumbnail_url,permalink,posted_at',
        )
        .order('posted_at', ascending: false)
        .limit(24);

    final rows = List<Map<String, dynamic>>.from(response as List);
    final all = rows.map(_DailyNewsItem.fromMap).toList();
    if (all.isEmpty) return all;

    final now = DateTime.now();
    final today = all.where((item) {
      final local = item.postedAt.toLocal();
      return local.year == now.year &&
          local.month == now.month &&
          local.day == now.day;
    }).toList();

    return (today.isNotEmpty ? today : all).take(8).toList();
  }

  void _reload() {
    setState(() => _future = _loadNews());
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_DailyNewsItem>>(
      future: _future,
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <_DailyNewsItem>[];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 39,
                  height: 39,
                  decoration: BoxDecoration(
                    color: AppColors.brandSoft,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(
                    Icons.newspaper_rounded,
                    color: AppColors.brand,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Actualités du jour',
                        style: TextStyle(
                          fontFamily: 'SpaceGrotesk',
                          color: AppColors.ink,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.35,
                        ),
                      ),
                      SizedBox(height: 1),
                      Text(
                        'Vie universitaire et hospitalière',
                        style: TextStyle(
                          color: AppColors.inkSoft,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: snapshot.connectionState == ConnectionState.waiting
                      ? null
                      : _reload,
                  tooltip: 'Actualiser',
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: 13),
            if (snapshot.connectionState == ConnectionState.waiting &&
                items.isEmpty)
              const _NewsLoading()
            else if (items.isNotEmpty)
              SizedBox(
                height: 256,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) => _NewsCard(
                    item: items[index],
                    onTap: () => _open(items[index].permalink),
                  ),
                ),
              )
            else
              _NewsEmptyState(
                profiles: _profiles,
                onOpen: _open,
                hasError: snapshot.hasError,
              ),
          ],
        );
      },
    );
  }
}

class _NewsCard extends StatelessWidget {
  final _DailyNewsItem item;
  final VoidCallback onTap;

  const _NewsCard({
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = item.cachedMediaUrl ?? item.thumbnailUrl ?? item.mediaUrl;
    final time = _relativeDate(item.postedAt.toLocal());

    return SizedBox(
      width: 238,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Ink(
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.line),
              boxShadow: [
                BoxShadow(
                  color: AppColors.navy.withOpacity(0.055),
                  blurRadius: 15,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 126,
                    width: double.infinity,
                    child: imageUrl == null || imageUrl.isEmpty
                        ? Container(
                            color: AppColors.brandSoft,
                            child: const Icon(
                              Icons.photo_camera_back_rounded,
                              size: 38,
                              color: AppColors.brand,
                            ),
                          )
                        : Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: AppColors.brandSoft,
                              child: const Icon(
                                Icons.image_not_supported_outlined,
                                color: AppColors.brand,
                              ),
                            ),
                          ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.camera_alt_rounded,
                                size: 14,
                                color: AppColors.danger,
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  item.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.ink,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              Text(
                                time,
                                style: const TextStyle(
                                  color: AppColors.inkFaint,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: Text(
                              _cleanCaption(item.caption),
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.inkSoft,
                                fontSize: 11.5,
                                height: 1.35,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(height: 5),
                          const Row(
                            children: [
                              Text(
                                'Voir sur Instagram',
                                style: TextStyle(
                                  color: AppColors.brand,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              SizedBox(width: 3),
                              Icon(
                                Icons.open_in_new_rounded,
                                size: 12,
                                color: AppColors.brand,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _cleanCaption(String? caption) {
    final value = (caption ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    return value.isEmpty ? 'Nouvelle publication.' : value;
  }

  static String _relativeDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 60) return '${diff.inMinutes.clamp(1, 59)} min';
    if (diff.inHours < 24) return '${diff.inHours} h';
    if (diff.inDays == 1) return 'Hier';
    return DateFormat('d MMM', 'fr_FR').format(date);
  }
}

class _NewsLoading extends StatelessWidget {
  const _NewsLoading();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 176,
      child: Row(
        children: List.generate(
          2,
          (_) => Expanded(
            child: Container(
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppColors.line),
              ),
              child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NewsEmptyState extends StatelessWidget {
  final List<_NewsProfile> profiles;
  final Future<void> Function(String url) onOpen;
  final bool hasError;

  const _NewsEmptyState({
    required this.profiles,
    required this.onOpen,
    required this.hasError,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hasError
                ? 'Impossible d’actualiser le flux pour le moment.'
                : 'Le flux Instagram se synchronise.',
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Vous pouvez déjà accéder aux sources officielles :',
            style: TextStyle(
              color: AppColors.inkSoft,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final profile in profiles)
                ActionChip(
                  avatar: const Icon(
                    Icons.camera_alt_rounded,
                    size: 14,
                    color: AppColors.danger,
                  ),
                  label: Text(profile.name),
                  onPressed: () => onOpen(profile.url),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DailyNewsItem {
  final String id;
  final String displayName;
  final String? caption;
  final String? mediaUrl;
  final String? cachedMediaUrl;
  final String? thumbnailUrl;
  final String permalink;
  final DateTime postedAt;

  const _DailyNewsItem({
    required this.id,
    required this.displayName,
    required this.caption,
    required this.mediaUrl,
    required this.cachedMediaUrl,
    required this.thumbnailUrl,
    required this.permalink,
    required this.postedAt,
  });

  factory _DailyNewsItem.fromMap(Map<String, dynamic> map) {
    return _DailyNewsItem(
      id: map['external_id']?.toString() ?? '',
      displayName: map['display_name']?.toString() ?? 'Actualité',
      caption: map['caption']?.toString(),
      mediaUrl: map['media_url']?.toString(),
      cachedMediaUrl: map['cached_media_url']?.toString(),
      thumbnailUrl: map['thumbnail_url']?.toString(),
      permalink: map['permalink']?.toString() ?? '',
      postedAt: DateTime.tryParse(map['posted_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class _NewsProfile {
  final String name;
  final String url;

  const _NewsProfile(this.name, this.url);
}
""")

print("GardeFlow V11.6.25: accueil jour/nuit + compteur mensuel + actualités Instagram")
