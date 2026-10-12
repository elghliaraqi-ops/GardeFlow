import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// These links come from the original SAGES video pages, never generated IDs.
({String title, String url})? surgicalVideo(String name) {
  final n = name.toLowerCase();
  final lap =
      n.contains('laparosc') || n.contains('cœlio') || n.contains('coelio');
  if (n.contains('tapp'))
    return (
      title: 'Cure inguinale TAPP · SAGES',
      url: 'https://www.youtube.com/watch?v=h7pLrMoxoOs',
    );
  if (!lap) return null;
  if (n.contains('cholécyst') || n.contains('cholecyst'))
    return (
      title: 'Cholécystectomie laparoscopique avec cholangiographie · SAGES',
      url: 'https://www.youtube.com/watch?v=KtVh1YI__xU',
    );
  if (n.contains('appendic'))
    return (
      title: 'Appendicectomie laparoscopique · SAGES',
      url: 'https://www.youtube.com/watch?v=Blpd8qJPoKU',
    );
  if (n.contains('antérieure') ||
      n.contains('anterieure') ||
      n.contains('mésorect') ||
      n.contains('mesorect'))
    return (
      title: 'Résection antérieure basse laparoscopique · SAGES',
      url: 'https://www.youtube.com/watch?v=cL3jeyaXGQI',
    );
  return null;
}

class PracticeSurgicalTechniques extends StatelessWidget {
  const PracticeSurgicalTechniques({super.key, required this.techniques});
  final List<Map<String, dynamic>> techniques;
  static String value(dynamic v) => v?.toString() ?? '';
  Future<void> _open(BuildContext context, Uri uri) async {
    try {
      final ok = await launchUrl(
        uri,
        mode: LaunchMode.platformDefault,
        webOnlyWindowName: '_blank',
      );
      if (!ok && context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible d’ouvrir la vidéo.')),
        );
    } catch (_) {
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible d’ouvrir la vidéo.')),
        );
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: techniques.map((t) {
      final name = value(t['name']);
      final steps = t['steps'] is List ? t['steps'] as List : const [];
      final video = surgicalVideo(name);
      return Container(
        margin: const EdgeInsets.only(top: 12, bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF132F36),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              name,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: Color(0xFF8EE8C4),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Indications',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            Text(value(t['indications']), style: const TextStyle(height: 1.45)),
            const SizedBox(height: 10),
            const Text(
              'Principales étapes opératoires',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            ...steps.asMap().entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${e.key + 1}. ${value(e.value)}',
                  style: const TextStyle(height: 1.45),
                ),
              ),
            ),
            if (video != null)
              TextButton.icon(
                onPressed: () => _open(context, Uri.parse(video.url)),
                icon: const Icon(Icons.play_circle_outline),
                label: Text('Voir la vidéo : ${video.title}'),
              ),
            TextButton.icon(
              onPressed: () => _open(
                context,
                Uri.https('www.youtube.com', '/results', {
                  'search_query': '$name technique opératoire chirurgie SAGES',
                }),
              ),
              icon: const Icon(Icons.video_library_outlined),
              label: const Text('Rechercher une démonstration sur YouTube'),
            ),
          ],
        ),
      );
    }).toList(),
  );
}
