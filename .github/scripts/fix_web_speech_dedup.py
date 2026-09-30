from pathlib import Path

path = Path('source/lib/screens/practice_screen.dart')
text = path.read_text(encoding='utf-8')
original = text

if "package:flutter/foundation.dart" not in text:
    needle = "import 'package:flutter/material.dart';\n"
    replacement = "import 'package:flutter/foundation.dart';\nimport 'package:flutter/material.dart';\n"
    if needle not in text:
        raise SystemExit('material import anchor not found')
    text = text.replace(needle, replacement, 1)

helper_anchor = "  Future<void> _toggleDictation(\n"
helper = r'''  String _normalizeSpeechTranscript(String raw) {
    final cleaned = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (!kIsWeb || cleaned.isEmpty) return cleaned;

    String keyOf(String token) => token
        .toLowerCase()
        .replaceAll(RegExp(r'^[\s.,;:!?…]+|[\s.,;:!?…]+$'), '');

    var tokens = cleaned.split(' ');

    // Chrome/Web Speech peut répéter le même mot dans un résultat final.
    // On ne déduplique ce comportement que sur le Web afin de ne pas toucher
    // aux moteurs natifs Android/iOS.
    final singleDeduped = <String>[];
    for (final token in tokens) {
      if (singleDeduped.isNotEmpty &&
          keyOf(singleDeduped.last).isNotEmpty &&
          keyOf(singleDeduped.last) == keyOf(token)) {
        continue;
      }
      singleDeduped.add(token);
    }
    tokens = singleDeduped;

    // Certains navigateurs répètent un segment entier (2 à 12 mots). On
    // supprime uniquement les blocs immédiatement adjacents et identiques.
    var maxBlock = tokens.length ~/ 2;
    if (maxBlock > 12) maxBlock = 12;
    for (var block = maxBlock; block >= 2; block--) {
      var index = 0;
      while (index + (block * 2) <= tokens.length) {
        var identicalBlocks = true;
        for (var offset = 0; offset < block; offset++) {
          if (keyOf(tokens[index + offset]) !=
              keyOf(tokens[index + block + offset])) {
            identicalBlocks = false;
            break;
          }
        }
        if (identicalBlocks) {
          tokens.removeRange(index + block, index + (block * 2));
        } else {
          index++;
        }
      }
    }

    return tokens.join(' ').trim();
  }

'''
if "String _normalizeSpeechTranscript(String raw)" not in text:
    if helper_anchor not in text:
        raise SystemExit('toggle dictation anchor not found')
    text = text.replace(helper_anchor, helper + helper_anchor, 1)

old_partial = "        partialResults: true,\n"
new_partial = "        partialResults: !kIsWeb,\n"
if old_partial in text:
    text = text.replace(old_partial, new_partial, 1)
elif new_partial not in text:
    raise SystemExit('partialResults anchor not found')

old_pause = "        pauseFor: const Duration(seconds: 4),\n"
new_pause = "        pauseFor: Duration(seconds: kIsWeb ? 2 : 4),\n"
if old_pause in text:
    text = text.replace(old_pause, new_pause, 1)
elif new_pause not in text:
    raise SystemExit('pauseFor anchor not found')

old_words = "          final words = result.recognizedWords.trim();\n"
new_words = "          final words = _normalizeSpeechTranscript(result.recognizedWords);\n"
if old_words in text:
    text = text.replace(old_words, new_words, 1)
elif new_words not in text:
    raise SystemExit('recognizedWords anchor not found')

if text == original:
    raise SystemExit('patch produced no changes')

path.write_text(text, encoding='utf-8')
