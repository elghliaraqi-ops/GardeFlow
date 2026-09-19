from pathlib import Path

EXPECTED = "version: 11.6.40+200"
TARGET = "version: 11.6.41+201"

pubspec = Path("pubspec.yaml")
pub = pubspec.read_text()
if EXPECTED not in pub:
    raise SystemExit("V11.6.41: base version mismatch")
pubspec.write_text(pub.replace(EXPECTED, TARGET, 1))


def replace_class(source: str, class_name: str, replacement: str) -> str:
    marker = f"class {class_name} "
    start = source.find(marker)
    if start < 0:
        raise SystemExit(f"V11.6.41: {class_name} not found")
    brace = source.find("{", start)
    if brace < 0:
        raise SystemExit(f"V11.6.41: opening brace missing for {class_name}")
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
        raise SystemExit(f"V11.6.41: closing brace missing for {class_name}")
    return source[:start] + replacement.rstrip() + source[end:]


news = Path("lib/screens/daily_news_section.dart")
n = news.read_text()

# Remove the small descriptive line under "Actualités du jour".
old_subtitle = """                      SizedBox(height: 1),
                      Text(
                        'Instagram officiel · AMI UM6 en priorité',
                        style: TextStyle(
                          color: AppColors.inkSoft,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),"""
if old_subtitle not in n:
    raise SystemExit("V11.6.41: daily-news subtitle block missing")
n = n.replace(old_subtitle, "", 1)

n = n.replace(
    "'Plus de détails sur les dernières publications Instagram'",
    "'Dernières publications des comptes officiels'",
    1,
)

# Redesign the long article cards: lighter typography, clear paragraphs,
# compact preview and an explicit Instagram continuation action.
detail_class = r"""class _NewsDetailCard extends StatelessWidget {
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
                  SizedBox(
                    width: double.infinity,
                    height: 190,
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
                            child: const Icon(
                              Icons.camera_alt_rounded,
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
                              style: const TextStyle(
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
                              style: const TextStyle(
                                color: AppColors.inkFaint,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
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
                          style: const TextStyle(
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
                        decoration: const BoxDecoration(
                          border: Border(
                            top: BorderSide(color: AppColors.line),
                          ),
                        ),
                        child: const Row(
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
}"""

n = replace_class(n, "_NewsDetailCard", detail_class)
news.write_text(n)

print("GardeFlow V11.6.41: cleaner news cards + readable article paragraphs")
