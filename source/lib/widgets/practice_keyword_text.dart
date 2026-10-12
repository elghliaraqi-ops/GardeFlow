import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// One renderer for stored and future clinical cases, course chapters, explanations and questions. No AI regeneration.
class PracticeKeywordText extends StatefulWidget {
  const PracticeKeywordText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  @override
  State<PracticeKeywordText> createState() => _PracticeKeywordTextState();
}

class _PracticeKeywordTextState extends State<PracticeKeywordText> {
  final List<TapGestureRecognizer> _taps = [];
  static final _terms = RegExp(
    r'\*\*([^*]+)\*\*|(?<![A-Za-zÀ-ÖØ-öø-ÿŒœ0-9_])(?:douleur thoracique|douleur abdominale|dyspnée|toux|vomissement[A-Za-zÀ-ÖØ-öø-ÿŒœ]*|nausée[A-Za-zÀ-ÖØ-öø-ÿŒœ]*|diarrhée|constipation|prurit|syncope|convulsion[A-Za-zÀ-ÖØ-öø-ÿŒœ]*|paresthésie[A-Za-zÀ-ÖØ-öø-ÿŒœ]*|parésie|paralysie|céphalée[A-Za-zÀ-ÖØ-öø-ÿŒœ]*|vertige|hypertension|hypoxie|SpO2|séquence[A-Za-zÀ-ÖØ-öø-ÿŒœ]*|axial[A-Za-zÀ-ÖØ-öø-ÿŒœ]*|coronal[A-Za-zÀ-ÖØ-öø-ÿŒœ]*|sagittal[A-Za-zÀ-ÖØ-öø-ÿŒœ]*|cerveau|cérébral[A-Za-zÀ-ÖØ-öø-ÿŒœ]*|moelle|rachis|ganglion[A-Za-zÀ-ÖØ-öø-ÿŒœ]*|aorte|bassin|œsophage|oesophage|décubitus dorsal|Trendelenburg|proclive|trocart[A-Za-zÀ-ÖØ-öø-ÿŒœ]*|agrafage|ligature|héparine|morphine|paracétamol|insuline|amoxicilline|ceftriaxone|gentamicine|corticoïde[A-Za-zÀ-ÖØ-öø-ÿŒœ]*|vasopresseur[A-Za-zÀ-ÖØ-öø-ÿŒœ]*|fosse iliaque droite|défense abdominale|choc septique|voie biliaire principale|prise de contraste|liquide libre|pneumopéritoine|tachycardie|hypotension|fièvre|ictère|péritonite|appendic[A-Za-zÀ-ÖØ-öø-ÿŒœ]*|chol[ée]cyst[A-Za-zÀ-ÖØ-öø-ÿŒœ]*|angiochol[A-Za-zÀ-ÖØ-öø-ÿŒœ]*|pancr[ée]at[A-Za-zÀ-ÖØ-öø-ÿŒœ]*|occlusion|hernie|ischémie|hémorrag[A-Za-zÀ-ÖØ-öø-ÿŒœ]*|abcès|fistule|anastomos[A-Za-zÀ-ÖØ-öø-ÿŒœ]*|cholédoque|diverticul[A-Za-zÀ-ÖØ-öø-ÿŒœ]*|adénopath[A-Za-zÀ-ÖØ-öø-ÿŒœ]*|sténose|perforation|nécrose|sepsis|lactate|créatinine|lipase|bilirubine|Hinchey|Bosniak|Tokyo|Balthazar|Hartmann|Whipple|Billroth|Nissen|Toupet|Heller|Kocher|Pringle|Lichtenstein|Bassini|Shouldice|Stoppa|Graham|TDM|IRM|CRP|SOFA|ASA|TAPP|TEP|DPC|RGO|CHC|NFS|DFG|GCS|NYHA|SAOS|HBP|ECG|EEG|CVS|critical view of safety|angioscanner|angiographie|échocardiographie|scintigraphie|ADC|DWI|T1|T2|STIR|FLAIR|imagerie|échographie|scanner|radiographie|diffusion|restriction|rehaussement|contraste|hypersignal|hyposignal|hyperdensité|hypodensité|réticulation[A-Za-zÀ-ÖØ-öø-ÿŒœ]*|bronchectasie[A-Za-zÀ-ÖØ-öø-ÿŒœ]*|fibrose|rayon de miel|verre dépoli|condensation|atélectasie|infiltration|collection|épanchement|calcification[A-Za-zÀ-ÖØ-öø-ÿŒœ]*|nodule[A-Za-zÀ-ÖØ-öø-ÿŒœ]*|tumeur[A-Za-zÀ-ÖØ-öø-ÿŒœ]*|cancer[A-Za-zÀ-ÖØ-öø-ÿŒœ]*|métastase[A-Za-zÀ-ÖØ-öø-ÿŒœ]*|ostéolyse|gastrite|œsophagite|oesophagite|colite|entérite|hépatite|pneumonie|bronchite|bronchiolite|méningite|encéphalite|myocardite|péricardite|endocardite|arthrite|cystite|prostatite|urétrite|pyélonéphrite|néphrite|sinusite|thyroïdite|dermatite|cellulite|spondylodiscite|ostéomyélite|thrombose|embolie|athérosclérose|stéatose|cirrhose|scoliose|cyphose|glucose|glycémie|hémoglobine|plaquettes|leucocytes|neutrophiles|albumine|troponine|D-dimères|adénome|adénocarcinome|carcinome|cholestase|lithiase|fibrome|kyste[A-Za-zÀ-ÖØ-öø-ÿŒœ]*|polype[A-Za-zÀ-ÖØ-öø-ÿŒœ]*|foie|rate|pancréas|duodénum|côlon|colon|rectum|iléon|jéjunum|péritoine|mésentère|mésorectum|vésicule|prostate|vessie|uretère[A-Za-zÀ-ÖØ-öø-ÿŒœ]*|rein[A-Za-zÀ-ÖØ-öø-ÿŒœ]*|cortex|parenchyme|capsule|ligament[A-Za-zÀ-ÖØ-öø-ÿŒœ]*|nerf[A-Za-zÀ-ÖØ-öø-ÿŒœ]*|veine[A-Za-zÀ-ÖØ-öø-ÿŒœ]*|artère[A-Za-zÀ-ÖØ-öø-ÿŒœ]*|pédicule|hilum|sphincter[A-Za-zÀ-ÖØ-öø-ÿŒœ]*|scutum|osselet[A-Za-zÀ-ÖØ-öø-ÿŒœ]*|cochlée|vestibule|mastoïde[A-Za-zÀ-ÖØ-öø-ÿŒœ]*|épitympan[A-Za-zÀ-ÖØ-öø-ÿŒœ]*|tympan|labyrinthe|dissection|résection|suture|drainage|stomie|réanimation|antibiothérapie|hémostase|curage|anesthésie|triade de Charcot|triangle de Calot|vue critique de sécurité|[A-Za-zÀ-ÖØ-öø-ÿŒœ\u0300-\u036f]+(?:ectomie|tomie|scopie|plastie|plasie|mégalie|pathie|algie|urie|émie|ectomy|otomy|oscopy|plasty|plasia|megaly|pathy|algia|uria|emia|itis|osis))(?![A-Za-zÀ-ÖØ-öø-ÿŒœ0-9_])',
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
    return Text.rich(
      TextSpan(children: spans),
      style: widget.style,
      textAlign: widget.textAlign,
      maxLines: widget.maxLines,
      overflow: widget.overflow,
    );
  }
}
