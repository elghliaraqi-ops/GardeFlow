import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';

class DailyNewsSection extends StatefulWidget {
  final Key? verticalFeedKey;

  const DailyNewsSection({super.key, this.verticalFeedKey});

  @override
  State<DailyNewsSection> createState() => _DailyNewsSectionState();
}

class _DailyNewsSectionState extends State<DailyNewsSection> {
  late Future<List<_DailyNewsItem>> _future;
  bool _refreshing = false;
  bool _isAdmin = false;
  String? _selectedCategory;

  static const _profiles = <_NewsProfile>[
    _NewsProfile('AMI UM6', 'https://www.instagram.com/ami_um6/'),
    _NewsProfile('UM6SS', 'https://www.instagram.com/um6ss/'),
    _NewsProfile('HUIM6 Bouskoura', 'https://www.instagram.com/huim6bouskoura/'),
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

  static const _sourceChoices = <_NewsSourceChoice>[
    _NewsSourceChoice('ami_um6', 'AMI UM6'),
    _NewsSourceChoice('huim6_bouskoura', 'HUIM6 Bouskoura'),
    _NewsSourceChoice('hck', 'Hôpital Cheikh Khalifa'),
    _NewsSourceChoice('huim6_rabat', 'HUIM6 Rabat'),
    _NewsSourceChoice('um6ss', 'UM6SS'),
    _NewsSourceChoice('other', 'Autres'),
  ];

  static String _categoryFor(_DailyNewsItem item) {
    final source = '${item.sourceKey} ${item.displayName}'.toLowerCase();

    if (source.contains('ami_um6') ||
        source.contains('ami um6') ||
        source.contains('amium6')) {
      return 'AMIUM6';
    }
    if (source.contains('bouskoura')) return 'HUIM6 de Bouskoura';
    if (source.contains('huick') ||
        source.contains('cheikh khalifa') ||
        source.contains('cheikh_khalifa') ||
        source.contains('hopital.cheikh.khalifa')) {
      return 'HUICK de Casablanca';
    }
    if (source.contains('rabat')) return 'HUIM6 de Rabat';
    if (source.contains('um6ss')) return 'UM6SS';
    return 'Autres';
  }

  @override
  void initState() {
    super.initState();
    _future = _loadNews();
    _loadAdminState();
  }

  Future<void> _loadAdminState() async {
    try {
      final result = await Supabase.instance.client.rpc('is_admin');
      if (!mounted) return;
      setState(() => _isAdmin = result == true);
    } catch (_) {
      // Le fil reste lisible même si le statut admin ne peut pas être chargé.
    }
  }

  Future<List<_DailyNewsItem>> _loadNews() async {
    final response = await Supabase.instance.client
        .from('daily_news_posts')
        .select(
          'external_id,source_key,username,display_name,caption,media_type,media_url,cached_media_url,thumbnail_url,permalink,posted_at',
        )
        .order('posted_at', ascending: false)
        .limit(100);

    final rows = List<Map<String, dynamic>>.from(response as List);

    // Source-agnostic by design: Instagram API, publications manuelles,
    // sites/RSS futurs et anciens éléments du cache utilisent le même flux.
    return rows.map(_DailyNewsItem.fromMap).toList(growable: false);
  }

  Future<void> _reloadCacheOnly() async {
    if (!mounted) return;
    setState(() => _future = _loadNews());
  }

  Future<void> _reload() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);

    try {
      // Instagram reste une source optionnelle. Une panne Meta ne bloque plus
      // le rechargement du cache universel daily_news_posts.
      await Supabase.instance.client.rpc('request_daily_news_refresh');
      await Future<void>.delayed(const Duration(seconds: 2));
    } catch (_) {
      // On continue immédiatement avec le cache et les publications manuelles.
    }

    if (!mounted) return;
    setState(() {
      _future = _loadNews();
      _refreshing = false;
    });
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _showPublishSheet() async {
    if (!_isAdmin) return;

    String sourceKey = _sourceChoices.first.key;
    final displayNameController = TextEditingController(
      text: _sourceChoices.first.label,
    );
    final captionController = TextEditingController();
    final permalinkController = TextEditingController();
    final mediaUrlController = TextEditingController();
    bool submitting = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> publish() async {
              final caption = captionController.text.trim();
              final permalink = permalinkController.text.trim();
              final mediaUrl = mediaUrlController.text.trim();
              final displayName = displayNameController.text.trim();
              final link = Uri.tryParse(permalink);
              final image = mediaUrl.isEmpty ? null : Uri.tryParse(mediaUrl);

              if (caption.isEmpty ||
                  link == null ||
                  !(link.scheme == 'http' || link.scheme == 'https')) {
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  const SnackBar(
                    content: Text('Ajoute un texte et un lien http(s) valide.'),
                  ),
                );
                return;
              }
              if (mediaUrl.isNotEmpty &&
                  (image == null ||
                      !(image.scheme == 'http' || image.scheme == 'https'))) {
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  const SnackBar(
                    content: Text('L’URL de l’image doit être un lien http(s).'),
                  ),
                );
                return;
              }

              setSheetState(() => submitting = true);
              try {
                await Supabase.instance.client.rpc(
                  'admin_publish_daily_news',
                  params: {
                    'p_source_key': sourceKey,
                    'p_display_name': displayName,
                    'p_caption': caption,
                    'p_permalink': permalink,
                    'p_media_url': mediaUrl.isEmpty ? null : mediaUrl,
                    'p_posted_at': DateTime.now().toUtc().toIso8601String(),
                  },
                );

                if (!mounted) return;
                Navigator.of(sheetContext).pop();
                await _reloadCacheOnly();
                if (!mounted) return;
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(content: Text('Actualité publiée.')),
                );
              } catch (_) {
                if (!mounted) return;
                setSheetState(() => submitting = false);
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  const SnackBar(
                    content: Text('Publication impossible. Vérifie les champs.'),
                  ),
                );
              }
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  18,
                  16,
                  18,
                  18 + MediaQuery.of(sheetContext).viewInsets.bottom,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Publier une actualité',
                              style: TextStyle(
                                fontFamily: 'SpaceGrotesk',
                                color: AppColors.ink,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: submitting
                                ? null
                                : () => Navigator.of(sheetContext).pop(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Fonctionne sans API Instagram : colle un lien Instagram, un site ou toute autre source publique.',
                        style: TextStyle(
                          color: AppColors.inkSoft,
                          fontSize: 12,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 18),
                      DropdownButtonFormField<String>(
                        value: sourceKey,
                        decoration: const InputDecoration(labelText: 'Catégorie'),
                        items: _sourceChoices
                            .map(
                              (choice) => DropdownMenuItem<String>(
                                value: choice.key,
                                child: Text(choice.label),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: submitting
                            ? null
                            : (value) {
                                if (value == null) return;
                                final choice = _sourceChoices.firstWhere(
                                  (item) => item.key == value,
                                );
                                setSheetState(() {
                                  sourceKey = value;
                                  displayNameController.text =
                                      value == 'other' ? '' : choice.label;
                                });
                              },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: displayNameController,
                        enabled: !submitting,
                        decoration: const InputDecoration(
                          labelText: 'Nom affiché de la source',
                          hintText: 'Ex. AMIUM6, HUIM6, UM6SS…',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: captionController,
                        enabled: !submitting,
                        minLines: 3,
                        maxLines: 7,
                        decoration: const InputDecoration(
                          labelText: 'Texte de l’actualité',
                          hintText: 'Titre, résumé ou légende…',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: permalinkController,
                        enabled: !submitting,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: 'Lien de l’actualité',
                          hintText: 'https://instagram.com/p/... ou https://...',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: mediaUrlController,
                        enabled: !submitting,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: 'URL de l’image (facultatif)',
                          hintText: 'https://…/image.jpg',
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: submitting ? null : publish,
                          icon: submitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.publish_rounded),
                          label: Text(
                            submitting ? 'Publication…' : 'Publier maintenant',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    displayNameController.dispose();
    captionController.dispose();
    permalinkController.dispose();
    mediaUrlController.dispose();
  }

  Future<void> _deleteManualNews(_DailyNewsItem item) async {
    if (!_isAdmin || !item.isManual) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer cette actualité ?'),
        content: const Text(
          'La publication manuelle sera retirée du fil pour tous les utilisateurs.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await Supabase.instance.client.rpc(
        'admin_delete_daily_news',
        params: {'p_external_id': item.id},
      );
      await _reloadCacheOnly();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Suppression impossible.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_DailyNewsItem>>(
      future: _future,
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <_DailyNewsItem>[];
        final horizontalItems = items.take(12).toList(growable: false);

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
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Actualités du jour',
                    style: TextStyle(
                      fontFamily: 'SpaceGrotesk',
                      color: AppColors.ink,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.35,
                    ),
                  ),
                ),
                if (_isAdmin)
                  IconButton(
                    onPressed: _showPublishSheet,
                    tooltip: 'Publier une actualité',
                    icon: const Icon(Icons.add_circle_outline_rounded),
                  ),
                IconButton(
                  onPressed:
                      snapshot.connectionState == ConnectionState.waiting ||
                          _refreshing
                      ? null
                      : _reload,
                  tooltip: _refreshing
                      ? 'Actualisation…'
                      : 'Actualiser les actualités',
                  icon: _refreshing
                      ? const SizedBox(
                          width: 19,
                          height: 19,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        )
                      : const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: 13),
            if (snapshot.connectionState == ConnectionState.waiting &&
                items.isEmpty)
              const _NewsLoading()
            else if (horizontalItems.isNotEmpty)
              SizedBox(
                height: 430,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: horizontalItems.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) => _NewsCard(
                    item: horizontalItems[index],
                    onTap: () => _open(horizontalItems[index].permalink),
                  ),
                ),
              )
            else
              _NewsEmptyState(
                profiles: _profiles,
                onOpen: _open,
                hasError: snapshot.hasError,
                isAdmin: _isAdmin,
                onPublish: _showPublishSheet,
              ),
            if (items.isNotEmpty) ...[
              const SizedBox(height: 28),
              Text(
                'Fil d’actualités',
                key: widget.verticalFeedKey,
                style: TextStyle(
                  fontFamily: 'SpaceGrotesk',
                  color: AppColors.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Toutes les sources, classées par publication',
                style: TextStyle(
                  color: AppColors.inkSoft,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              Builder(
                builder: (context) {
                  final availableCategories = _categoryOrder
                      .where(
                        (category) =>
                            items.any((item) => _categoryFor(item) == category),
                      )
                      .toList(growable: false);
                  if (availableCategories.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  final activeCategory =
                      _selectedCategory != null &&
                          availableCategories.contains(_selectedCategory)
                      ? _selectedCategory!
                      : availableCategories.first;
                  final visibleItems = items
                      .where((item) => _categoryFor(item) == activeCategory)
                      .toList(growable: false);

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: [
                            for (final category in availableCategories) ...[
                              OutlinedButton(
                                onPressed: () => setState(
                                  () => _selectedCategory = category,
                                ),
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: activeCategory == category
                                      ? AppColors.brand
                                      : AppColors.card,
                                  foregroundColor: activeCategory == category
                                      ? Colors.white
                                      : AppColors.ink,
                                  side: BorderSide(
                                    color: activeCategory == category
                                        ? AppColors.brandBright
                                        : AppColors.line,
                                    width: 1.2,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 11,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                child: Text(category),
                              ),
                              const SizedBox(width: 8),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      for (final item in visibleItems) ...[
                        _NewsDetailCard(
                          item: item,
                          onTap: () => _open(item.permalink),
                          onDelete: _isAdmin && item.isManual
                              ? () => _deleteManualNews(item)
                              : null,
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  );
                },
              ),
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

  const _NewsCard({required this.item, required this.onTap});

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
                    height: 286,
                    width: double.infinity,
                    child: imageUrl == null || imageUrl.isEmpty
                        ? Container(
                            color: AppColors.brandSoft,
                            child: Icon(
                              item.sourceIcon,
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
                                  item.sourceIcon,
                                  color: AppColors.brand,
                                  size: 34,
                                ),
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
                              Icon(
                                item.sourceIcon,
                                size: 14,
                                color: item.isInstagram
                                    ? AppColors.danger
                                    : AppColors.brand,
                              ),
                              const SizedBox(width: 5),
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
                          const SizedBox(height: 8),
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
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              Text(
                                item.shortActionLabel,
                                style: TextStyle(
                                  color: AppColors.brand,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(width: 3),
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
  final VoidCallback? onDelete;

  const _NewsDetailCard({
    required this.item,
    required this.onTap,
    this.onDelete,
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
                offset: const Offset(0, 7),
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
                            item.sourceIcon,
                            color: AppColors.brand,
                            size: 38,
                          ),
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
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
                              item.sourceIcon,
                              color: AppColors.brand,
                              size: 15,
                            ),
                          ),
                          const SizedBox(width: 9),
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
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
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
                          if (onDelete != null) ...[
                            const SizedBox(width: 4),
                            IconButton(
                              tooltip: 'Supprimer',
                              onPressed: onDelete,
                              icon: Icon(
                                Icons.delete_outline_rounded,
                                color: AppColors.danger,
                                size: 20,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 13),
                      Container(height: 1, color: AppColors.line),
                      const SizedBox(height: 13),
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
                          const SizedBox(height: 10),
                      ],
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.only(top: 11),
                        decoration: BoxDecoration(
                          border: Border(top: BorderSide(color: AppColors.line)),
                        ),
                        child: Row(
                          children: [
                            Text(
                              item.longActionLabel,
                              style: TextStyle(
                                color: AppColors.brand,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(width: 5),
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
  final bool isAdmin;
  final VoidCallback onPublish;

  const _NewsEmptyState({
    required this.profiles,
    required this.onOpen,
    required this.hasError,
    required this.isAdmin,
    required this.onPublish,
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
                ? 'Impossible d’actualiser les sources distantes pour le moment.'
                : 'Aucune actualité disponible pour le moment.',
            style: TextStyle(
              color: AppColors.ink,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Le fil continue de fonctionner même si l’API Instagram est indisponible.',
            style: TextStyle(
              color: AppColors.inkSoft,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (isAdmin) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onPublish,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Publier une actualité'),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final profile in profiles)
                ActionChip(
                  avatar: Icon(
                    Icons.open_in_new_rounded,
                    size: 14,
                    color: AppColors.brand,
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
  final String mediaType;
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
    required this.mediaType,
    required this.mediaUrl,
    required this.cachedMediaUrl,
    required this.thumbnailUrl,
    required this.permalink,
    required this.postedAt,
  });

  bool get isInstagram => permalink.toLowerCase().contains('instagram.com');

  bool get isManual =>
      mediaType.toUpperCase() == 'MANUAL' || id.startsWith('manual-');

  IconData get sourceIcon {
    if (isInstagram) return Icons.camera_alt_rounded;
    if (mediaType.toUpperCase() == 'WEB') return Icons.language_rounded;
    if (mediaType.toUpperCase() == 'RSS') return Icons.rss_feed_rounded;
    return Icons.article_outlined;
  }

  String get shortActionLabel =>
      isInstagram ? 'Voir sur Instagram' : 'Ouvrir la source';

  String get longActionLabel =>
      isInstagram ? 'Lire la suite sur Instagram' : 'Lire la source';

  factory _DailyNewsItem.fromMap(Map<String, dynamic> map) {
    return _DailyNewsItem(
      id: map['external_id']?.toString() ?? '',
      sourceKey: map['source_key']?.toString() ?? '',
      displayName: map['display_name']?.toString() ?? 'Actualité',
      caption: map['caption']?.toString(),
      mediaType: map['media_type']?.toString() ?? 'IMAGE',
      mediaUrl: map['media_url']?.toString(),
      cachedMediaUrl: map['cached_media_url']?.toString(),
      thumbnailUrl: map['thumbnail_url']?.toString(),
      permalink: map['permalink']?.toString() ?? '',
      postedAt:
          DateTime.tryParse(map['posted_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class _NewsProfile {
  final String name;
  final String url;

  const _NewsProfile(this.name, this.url);
}

class _NewsSourceChoice {
  final String key;
  final String label;

  const _NewsSourceChoice(this.key, this.label);
}
