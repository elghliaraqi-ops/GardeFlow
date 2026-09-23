import 'package:flutter/material.dart';
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
  bool _refreshing = false;

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

  static const _categoryOrder = <String>[
    'AMIUM6',
    'HUIM6 de Bouskoura',
    'HUICK de Casablanca',
    'HUIM6 de Rabat',
    'UM6SS',
    'Autres',
  ];

  static String _categoryFor(_DailyNewsItem item) {
    final source = '${item.sourceKey} ${item.displayName}'.toLowerCase();

    if (source.contains('ami_um6') ||
        source.contains('ami um6') ||
        source.contains('amium6')) {
      return 'AMIUM6';
    }
    if (source.contains('bouskoura')) {
      return 'HUIM6 de Bouskoura';
    }
    if (source.contains('huick') ||
        source.contains('cheikh khalifa') ||
        source.contains('cheikh_khalifa') ||
        source.contains('hopital.cheikh.khalifa')) {
      return 'HUICK de Casablanca';
    }
    if (source.contains('rabat')) {
      return 'HUIM6 de Rabat';
    }
    if (source.contains('um6ss')) {
      return 'UM6SS';
    }
    return 'Autres';
  }

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
        .limit(40);

    final rows = List<Map<String, dynamic>>.from(response as List);
    final instagramRows = rows.where((row) {
      final mediaType = (row['media_type'] ?? '').toString().toUpperCase();
      final externalId = (row['external_id'] ?? '').toString();
      return mediaType != 'WEB' && !externalId.startsWith('web-');
    }).toList();

    // L'ordre du flux horizontal suit désormais strictement la date de
    // publication : aucune source n'est prioritaire.
    return instagramRows.take(12).map(_DailyNewsItem.fromMap).toList();
  }

  Future<void> _reload() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);

    try {
      // Déclenche une vraie synchronisation Instagram côté serveur.
      // La fonction SQL est sécurisée et ne révèle jamais le token Meta.
      await Supabase.instance.client.rpc('request_daily_news_refresh');

      // pg_net exécute la synchronisation en arrière-plan. On laisse le temps
      // au flux Instagram de se mettre à jour avant de relire la table.
      await Future<void>.delayed(const Duration(seconds: 4));
    } catch (_) {
      // Même si la synchronisation distante échoue momentanément,
      // on recharge le cache Instagram déjà disponible.
    }

    if (!mounted) return;
    setState(() {
      _future = _loadNews();
      _refreshing = false;
    });
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
                  child: Icon(
                    Icons.newspaper_rounded,
                    color: AppColors.brand,
                    size: 21,
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
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
                    ],
                  ),
                ),
                IconButton(
                  onPressed: snapshot.connectionState == ConnectionState.waiting ||
                          _refreshing
                      ? null
                      : _reload,
                  tooltip: _refreshing
                      ? 'Synchronisation Instagram…'
                      : 'Actualiser Instagram',
                  icon: _refreshing
                      ? SizedBox(
                          width: 19,
                          height: 19,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        )
                      : Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            SizedBox(height: 13),
            if (snapshot.connectionState == ConnectionState.waiting &&
                items.isEmpty)
              _NewsLoading()
            else if (items.isNotEmpty)
              SizedBox(
                height: 430,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: BouncingScrollPhysics(),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => SizedBox(width: 12),
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
            if (items.isNotEmpty) ...[
              SizedBox(height: 28),
              Text(
                'Fil d’actualités',
                style: TextStyle(
                  fontFamily: 'SpaceGrotesk',
                  color: AppColors.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Dernières publications classées par source',
                style: TextStyle(
                  color: AppColors.inkSoft,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 16),
              for (final category in _categoryOrder)
                if (items.any((item) => _categoryFor(item) == category)) ...[
                  Container(
                    width: double.infinity,
                    margin: EdgeInsets.only(top: 4, bottom: 10),
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: AppColors.brandSoft,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Text(
                      category,
                      style: TextStyle(
                        fontFamily: 'SpaceGrotesk',
                        color: AppColors.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  for (final item in items.where(
                    (item) => _categoryFor(item) == category,
                  )) ...[
                    _NewsDetailCard(
                      item: item,
                      onTap: () => _open(item.permalink),
                    ),
                    SizedBox(height: 12),
                  ],
                  SizedBox(height: 8),
                ],
            ],
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
      width: 286,
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
                  offset: Offset(0, 7),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 286,
                    width: double.infinity,
                    child: imageUrl == null || imageUrl.isEmpty
                        ? Container(
                            color: AppColors.brandSoft,
                            child: Icon(
                              Icons.photo_camera_back_rounded,
                              size: 38,
                              color: AppColors.brand,
                            ),
                          )
                        : Container(
                            color: AppColors.paperAlt,
                            alignment: Alignment.center,
                            child: Image.network(
                              imageUrl,
                              width: double.infinity,
                              height: double.infinity,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => Container(
                                color: AppColors.brandSoft,
                                alignment: Alignment.center,
                                child: Icon(
                                  Icons.image_not_supported_outlined,
                                  color: AppColors.brand,
                                ),
                              ),
                            ),
                          ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(13, 11, 13, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.camera_alt_rounded,
                                size: 14,
                                color: AppColors.danger,
                              ),
                              SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  item.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppColors.ink,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              Text(
                                time,
                                style: TextStyle(
                                  color: AppColors.inkFaint,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 8),
                          Expanded(
                            child: Text(
                              _cleanCaption(item.caption),
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.inkSoft,
                                fontSize: 11.5,
                                height: 1.35,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          SizedBox(height: 5),
                          Row(
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
    final value = (caption ?? '')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&nbsp;', ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
    return value.isEmpty ? 'Nouvelle actualité.' : value;
  }

  static String _relativeDate(DateTime date) {
    final now = DateTime.now();
    if (date.isAfter(now)) {
      return 'À venir · ${DateFormat('d MMM', 'fr_FR').format(date)}';
    }
    final diff = now.difference(date);
    if (diff.inMinutes < 60) return '${diff.inMinutes.clamp(1, 59)} min';
    if (diff.inHours < 24) return '${diff.inHours} h';
    if (diff.inDays == 1) return 'Hier';
    return DateFormat('d MMM', 'fr_FR').format(date);
  }
}

class _NewsDetailCard extends StatelessWidget {
  final _DailyNewsItem item;
  final VoidCallback onTap;

  const _NewsDetailCard({
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = item.cachedMediaUrl ?? item.thumbnailUrl ?? item.mediaUrl;
    final caption = _normaliseCaption(item.caption);
    final paragraphs = _paragraphs(caption);
    final sourceLength = caption.replaceAll(RegExp(r'\s+'), ' ').trim().length;
    final shownLength = paragraphs.join(' ').length;
    final truncated = sourceLength > shownLength + 8;
    final time = _NewsCard._relativeDate(item.postedAt.toLocal());

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.line),
            boxShadow: [
              BoxShadow(
                color: AppColors.navy.withOpacity(0.045),
                blurRadius: 16,
                offset: Offset(0, 7),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (imageUrl != null && imageUrl.isNotEmpty)
                  AspectRatio(
                    aspectRatio: 1,
                    child: Container(
                      color: AppColors.paperAlt,
                      alignment: Alignment.center,
                      child: Image.network(
                        imageUrl,
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Container(
                          color: AppColors.brandSoft,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            color: AppColors.brand,
                          ),
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: AppColors.brandSoft,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.camera_alt_rounded,
                              color: AppColors.brand,
                              size: 15,
                            ),
                          ),
                          SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              item.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.ink,
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          SizedBox(width: 8),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.paperAlt,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              time,
                              style: TextStyle(
                                color: AppColors.inkFaint,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 13),
                      Container(height: 1, color: AppColors.line),
                      SizedBox(height: 13),
                      for (var i = 0; i < paragraphs.length; i++) ...[
                        Text(
                          i == paragraphs.length - 1 && truncated
                              ? '${paragraphs[i]}…'
                              : paragraphs[i],
                          style: TextStyle(
                            color: AppColors.inkSoft,
                            fontSize: 13.2,
                            height: 1.55,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (i != paragraphs.length - 1)
                          SizedBox(height: 10),
                      ],
                      SizedBox(height: 14),
                      Container(
                        padding: EdgeInsets.only(top: 11),
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(color: AppColors.line),
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(
                              'Lire la suite sur Instagram',
                              style: TextStyle(
                                color: AppColors.brand,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(width: 5),
                            Icon(
                              Icons.arrow_outward_rounded,
                              size: 14,
                              color: AppColors.brand,
                            ),
                          ],
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

  static String _normaliseCaption(String? caption) {
    final value = (caption ?? '')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .trim();
    return value.isEmpty ? 'Nouvelle publication.' : value;
  }

  static List<String> _paragraphs(String caption) {
    final explicit = caption
        .split(RegExp(r'\n+'))
        .map((line) => line.trim().replaceAll(RegExp(r'[ \t]+'), ' '))
        .where((line) => line.isNotEmpty)
        .toList();

    final result = <String>[];
    for (final block in explicit) {
      if (result.length >= 4) break;
      if (block.length <= 250) {
        result.add(block);
        continue;
      }

      final words = block.split(RegExp(r'\s+'));
      var current = '';
      for (final word in words) {
        if (word.isEmpty) continue;
        final candidate = current.isEmpty ? word : '$current $word';
        if (candidate.length > 250 && current.isNotEmpty) {
          result.add(current);
          if (result.length >= 4) break;
          current = word;
        } else {
          current = candidate;
        }
      }
      if (result.length < 4 && current.isNotEmpty) result.add(current);
    }

    if (result.isEmpty) return const ['Nouvelle publication.'];
    return result.take(4).toList();
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
              margin: EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppColors.line),
              ),
              child: Center(
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
      padding: EdgeInsets.all(15),
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
                : 'Les publications Instagram officielles arrivent ici.',
            style: TextStyle(
              color: AppColors.ink,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 5),
          Text(
            'Accès direct aux comptes Instagram officiels :',
            style: TextStyle(
              color: AppColors.inkSoft,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final profile in profiles)
                ActionChip(
                  avatar: Icon(
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
  final String sourceKey;
  final String displayName;
  final String? caption;
  final String? mediaUrl;
  final String? cachedMediaUrl;
  final String? thumbnailUrl;
  final String permalink;
  final DateTime postedAt;

  const _DailyNewsItem({
    required this.id,
    required this.sourceKey,
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
      sourceKey: map['source_key']?.toString() ?? '',
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
