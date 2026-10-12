import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// One renderer for stored and future clinical questions. No AI regeneration.
class PracticeKeywordText extends StatefulWidget {
  const PracticeKeywordText(this.text, {super.key, this.style});
  final String text;
  final TextStyle? style;
  @override
  State<PracticeKeywordText> createState() => _PracticeKeywordTextState();
}

class _PracticeKeywordTextState extends State<PracticeKeywordText> {
  final List<TapGestureRecognizer> _taps = [];
  static final _terms = RegExp(
    r'\*\*([^*]+)\*\*|\b(?:douleur abdominale|fosse iliaque droite|défense abdominale|choc septique|voie biliaire principale|prise de contraste|liquide libre|pneumopéritoine|tachycardie|hypotension|fièvre|ictère|péritonite|appendic\w*|cholécyst\w*|angiochol\w*|pancréat\w*|occlusion|hernie|ischémie|hémorrag\w*|abcès|fistule|anastomos\w*|colectom\w*|gastrectom\w*|hépatectom\w*|laparoscop\w*|laparotom\w*|cœlioscop\w*|cholédoque|diverticul\w*|adénopath\w*|sténose|perforation|nécrose|sepsis|lactate|créatinine|lipase|bilirubine|Hinchey|Bosniak|Tokyo|Balthazar|TDM|IRM|CRP|SOFA|ASA|TAPP|TEP|RGO|CHC)\b',
    caseSensitive: false,
    unicode: true,
  );
  void _clear() {
    for (final tap in _taps) {
      tap.dispose();
    }
    _taps.clear();
  }

  Future<void> _search(String term) async {
    final uri = Uri.https('www.google.com', '/search', {'q': '$term médecine'});
    try {
      final opened = await launchUrl(
        uri,
        mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.inAppBrowserView,
        webOnlyWindowName: '_blank',
      );
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Impossible d’ouvrir la recherche Google.'),
          ),
        );
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Impossible d’ouvrir la recherche Google.'),
          ),
        );
    }
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _clear();
    final spans = <InlineSpan>[];
    var end = 0;
    for (final match in _terms.allMatches(widget.text)) {
      if (match.start > end)
        spans.add(TextSpan(text: widget.text.substring(end, match.start)));
      final term = match.group(1) ?? match.group(0)!;
      final tap = TapGestureRecognizer()
        ..onTap = () {
          _search(term);
        };
      _taps.add(tap);
      spans.add(
        TextSpan(
          text: term,
          recognizer: tap,
          mouseCursor: SystemMouseCursors.click,
          style: const TextStyle(
            decoration: TextDecoration.underline,
            decorationStyle: TextDecorationStyle.solid,
          ),
        ),
      );
      end = match.end;
    }
    spans.add(TextSpan(text: widget.text.substring(end)));
    return Text.rich(TextSpan(children: spans), style: widget.style);
  }
}
