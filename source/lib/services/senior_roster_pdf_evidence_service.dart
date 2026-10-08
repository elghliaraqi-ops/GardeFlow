import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

/// Complément géométrique à l'analyse visuelle des PDF d'astreintes séniors.
///
/// pdfrx n'est pas un OCR : un PDF scanné sans texte exploitable continue
/// vers l'analyse visuelle. Aucune garde n'est créée ici.
class SeniorRosterPdfEvidence {
  final String resourceId;
  final String resourceUpdatedAt;
  final int pageCount;
  final int pagesRead;
  final int extractedFragments;
  final String structuredText;
  final bool truncated;

  const SeniorRosterPdfEvidence({
    required this.resourceId,
    required this.resourceUpdatedAt,
    required this.pageCount,
    required this.pagesRead,
    required this.extractedFragments,
    required this.structuredText,
    required this.truncated,
  });

  bool get hasSelectableText => extractedFragments > 0;

  Map<String, dynamic> toJson() => {
        'sourceResourceId': resourceId,
        'sourceUpdatedAt': resourceUpdatedAt,
        'pageCount': pageCount,
        'pagesRead': pagesRead,
        'extractedFragments': extractedFragments,
        'structuredText': structuredText,
        'truncated': truncated,
        'extractor': 'pdfrx-2.6.5',
      };
}

class SeniorRosterPdfEvidenceService {
  SeniorRosterPdfEvidenceService._();

  static const maxPages = 30;
  static const maxChars = 36000;

  static Future<SeniorRosterPdfEvidence> extract({
    required Uint8List bytes,
    required String resourceId,
    required DateTime resourceUpdatedAt,
    required String displayName,
  }) async {
    final document = await PdfDocument.openData(
      bytes,
      sourceName: displayName,
      useProgressiveLoading: false,
    );
    final buffer = StringBuffer();
    var truncated = false;
    var read = 0;
    var usedChars = 0;
    var extractedFragments = 0;

    try {
      final pageCount = document.pages.length;
      for (var i = 0; i < pageCount; i++) {
        if (i >= maxPages || usedChars >= maxChars) {
          truncated = true;
          break;
        }
        final page = document.pages[i];
        // L'ordre de lecture visuel (ligne/colonne) peut différer de l'ordre
        // interne du PDF : joindre les coordonnées aux fragments extraits.
        final fragments = [...(await page.loadStructuredText()).fragments]
          ..sort((a, b) {
            final dy = (a.bounds.top - b.bounds.top).abs();
            if (dy < 4) return a.bounds.left.compareTo(b.bounds.left);
            return a.bounds.top.compareTo(b.bounds.top);
          });
        read++;
        final heading = '=== PAGE ${i + 1} / $pageCount ===\n';
        if (usedChars + heading.length > maxChars) {
          truncated = true;
          break;
        }
        buffer.write(heading);
        usedChars += heading.length;
        for (final fragment in fragments) {
          final clean = fragment.text.replaceAll(RegExp(r'\s+'), ' ').trim();
          if (clean.isEmpty) continue;
          final left = fragment.bounds.left.toStringAsFixed(1);
          final top = fragment.bounds.top.toStringAsFixed(1);
          final entry = 'x=$left y=$top | $clean\n';
          if (usedChars + entry.length > maxChars) {
            truncated = true;
            break;
          }
          buffer.write(entry);
          usedChars += entry.length;
          extractedFragments++;
        }
        if (truncated) break;
      }
      return SeniorRosterPdfEvidence(
        resourceId: resourceId,
        resourceUpdatedAt: resourceUpdatedAt.toUtc().toIso8601String(),
        pageCount: pageCount,
        pagesRead: read,
        extractedFragments: extractedFragments,
        structuredText: buffer.toString(),
        truncated: truncated,
      );
    } finally {
      await document.dispose();
    }
  }
}
