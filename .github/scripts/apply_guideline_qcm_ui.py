from pathlib import Path

path = Path('source/lib/screens/clinical_cases_section.dart')
text = path.read_text(encoding='utf-8')
original = text

old_import = "import 'package:flutter/material.dart';\n"
new_import = "import 'package:flutter/material.dart';\nimport 'package:url_launcher/url_launcher.dart';\n"
if "package:url_launcher/url_launcher.dart" not in text:
    if old_import not in text:
        raise SystemExit('Flutter import marker not found')
    text = text.replace(old_import, new_import, 1)

old_label = "'EXPLICATION IA',"
if old_label in text:
    text = text.replace(old_label, "'EXPLICATION + SOURCES',", 1)

old_correction = """                    Text(
                      current.correction.trim().isEmpty
                          ? 'Explication pédagogique en préparation.'
                          : current.correction,
                      style: TextStyle(
                        color: AppColors.inkSoft,
                        fontSize: 11.5,
                        height: 1.46,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
"""
new_correction = """                    _GuidelineCorrection(
                      correction: current.correction,
                    ),
"""
if old_correction in text:
    text = text.replace(old_correction, new_correction, 1)
elif '_GuidelineCorrection(' not in text:
    raise SystemExit('Correction display marker not found')

marker = "class _CaseSection extends StatelessWidget {"
helper = r'''class _GuidelineReference {
  final String kind;
  final String title;
  final String organization;
  final String year;
  final Uri url;

  const _GuidelineReference({
    required this.kind,
    required this.title,
    required this.organization,
    required this.year,
    required this.url,
  });
}

class _GuidelineCorrection extends StatelessWidget {
  final String correction;

  const _GuidelineCorrection({required this.correction});

  ({String explanation, List<_GuidelineReference> references}) _parse() {
    const marker = '\n\n§SOURCES§\n';
    final raw = correction.trim();
    final markerIndex = raw.indexOf(marker);
    if (markerIndex < 0) {
      return (
        explanation: raw,
        references: const <_GuidelineReference>[],
      );
    }

    final explanation = raw.substring(0, markerIndex).trim();
    final sourcesText = raw.substring(markerIndex + marker.length).trim();
    final references = <_GuidelineReference>[];
    for (final line in sourcesText.split('\n')) {
      final parts = line.split('|||');
      if (parts.length != 5) continue;
      final uri = Uri.tryParse(parts[4].trim());
      if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) {
        continue;
      }
      references.add(
        _GuidelineReference(
          kind: parts[0].trim(),
          title: parts[1].trim(),
          organization: parts[2].trim(),
          year: parts[3].trim(),
          url: uri,
        ),
      );
    }
    return (explanation: explanation, references: references);
  }

  String _kindLabel(String value) {
    switch (value) {
      case 'recommandation':
        return 'Recommandation';
      case 'consensus':
        return 'Consensus';
      case 'revue':
        return 'Revue';
      case 'cours':
        return 'Cours';
      default:
        return 'Source';
    }
  }

  @override
  Widget build(BuildContext context) {
    final parsed = _parse();
    final explanation = parsed.explanation.trim().isEmpty
        ? 'Explication pédagogique en préparation.'
        : parsed.explanation;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          explanation,
          style: TextStyle(
            color: AppColors.inkSoft,
            fontSize: 11.5,
            height: 1.46,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (parsed.references.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Icons.menu_book_rounded,
                size: 15,
                color: AppColors.brandBright,
              ),
              const SizedBox(width: 6),
              Text(
                'SOURCES DU COURS',
                style: TextStyle(
                  color: AppColors.brandBright,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .55,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          for (final ref in parsed.references) ...[
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => launchUrl(
                  ref.url,
                  mode: LaunchMode.externalApplication,
                ),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.paperAlt,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.line.withOpacity(.75),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_kindLabel(ref.kind)} · ${ref.organization} · ${ref.year}',
                              style: TextStyle(
                                color: AppColors.brandBright,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              ref.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.inkSoft,
                                fontSize: 10.5,
                                height: 1.3,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 7),
                      Icon(
                        Icons.open_in_new_rounded,
                        size: 15,
                        color: AppColors.inkFaint,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],
        ],
      ],
    );
  }
}

'''
if 'class _GuidelineCorrection extends StatelessWidget' not in text:
    if marker not in text:
        raise SystemExit('CaseSection insertion marker not found')
    text = text.replace(marker, helper + marker, 1)

if text == original:
    print('Guideline QCM UI patch already applied.')
else:
    path.write_text(text, encoding='utf-8')
    print('Guideline QCM UI patch applied.')
