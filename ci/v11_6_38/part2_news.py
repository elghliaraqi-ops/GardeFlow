from pathlib import Path

news = Path("lib/screens/daily_news_section.dart")
n = news.read_text()

old_return = "    return ordered.take(12).map(_DailyNewsItem.fromMap).toList();"
if old_return not in n:
    raise SystemExit("V11.6.38 news return anchor missing")
n = n.replace(
    old_return,
    "    return ordered.take(30).map(_DailyNewsItem.fromMap).toList();",
    1,
)

old_horizontal = """            else if (items.isNotEmpty)
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
            else"""

new_horizontal = """            else if (items.isNotEmpty) ...[
              const Text(
                'EN BREF',
                style: TextStyle(
                  color: AppColors.inkFaint,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 256,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: items.take(12).length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) => _NewsCard(
                    item: items[index],
                    onTap: () => _open(items[index].permalink),
                  ),
                ),
              ),
              const SizedBox(height: 26),
              const Text(
                'Fil Instagram',
                style: TextStyle(
                  fontFamily: 'SpaceGrotesk',
                  color: AppColors.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Publications détaillées des comptes officiels.',
                style: TextStyle(
                  color: AppColors.inkSoft,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              for (final item in items.take(20)) ...[
                _NewsDetailedCard(
                  item: item,
                  onTap: () => _open(item.permalink),
                ),
                const SizedBox(height: 12),
              ],
            ]
            else"""

if old_horizontal not in n:
    raise SystemExit("V11.6.38 news horizontal block missing")
n = n.replace(old_horizontal, new_horizontal, 1)

insert_before = "class _NewsLoading extends StatelessWidget {"
detail_class = r"""class _NewsDetailedCard extends StatelessWidget {
  final _DailyNewsItem item;
  final VoidCallback onTap;

  const _NewsDetailedCard({
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = item.cachedMediaUrl ?? item.thumbnailUrl ?? item.mediaUrl;

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
            border: Border.all(
              color: item.displayName.toUpperCase().contains('AMI')
                  ? AppColors.brand.withOpacity(0.28)
                  : AppColors.line,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.navy.withOpacity(0.045),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (imageUrl != null && imageUrl.isNotEmpty)
                  SizedBox(
                    height: 185,
                    width: double.infinity,
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: AppColors.brandSoft,
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.image_not_supported_outlined,
                          color: AppColors.brand,
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(15, 14, 15, 15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.camera_alt_rounded,
                            color: AppColors.danger,
                            size: 15,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              item.displayName,
                              style: const TextStyle(
                                color: AppColors.ink,
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Text(
                            _DailyNewsSectionState._relativeDate(
                              item.postedAt.toLocal(),
                            ),
                            style: const TextStyle(
                              color: AppColors.inkFaint,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 11),
                      Text(
                        _DailyNewsSectionState._cleanCaption(item.caption),
                        maxLines: 10,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.inkSoft,
                          fontSize: 12.2,
                          height: 1.48,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Row(
                        children: [
                          Text(
                            'Voir sur Instagram',
                            style: TextStyle(
                              color: AppColors.brand,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(
                            Icons.open_in_new_rounded,
                            size: 13,
                            color: AppColors.brand,
                          ),
                        ],
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

"""
if insert_before not in n:
    raise SystemExit("V11.6.38 news loading class missing")
n = n.replace(insert_before, detail_class + insert_before, 1)

news.write_text(n)
print("V11.6.38 part 2 applied")
