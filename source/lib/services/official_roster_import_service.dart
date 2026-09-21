import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

import '../models/app_user.dart';

class OfficialRosterAssignment {
  final String profileId;
  final String dateStr;
  final String shiftId;
  final bool isDisciplinary;

  const OfficialRosterAssignment({
    required this.profileId,
    required this.dateStr,
    required this.shiftId,
    this.isDisciplinary = false,
  });

  Map<String, dynamic> toJson() => {
        'profile_id': profileId,
        'date': dateStr,
        'shift_id': shiftId,
        'is_disciplinary': isDisciplinary,
        'parser_revision': 'v11.6.52-r1',
      };
}


class OfficialRosterDisciplinaryMark {
  final String dateStr;
  final String shiftId;
  final String redText;

  const OfficialRosterDisciplinaryMark({
    required this.dateStr,
    required this.shiftId,
    required this.redText,
  });

  Map<String, dynamic> toJson() => {
        'date': dateStr,
        'shift_id': shiftId,
        'red_text': redText,
        'parser_revision': 'v11.6.52-r1',
      };
}

class OfficialRosterParseResult {
  final List<OfficialRosterAssignment> assignments;
  final List<Map<String, dynamic>> unmatchedCells;
  final List<OfficialRosterDisciplinaryMark> disciplinaryMarks;
  final int detectedRows;
  final int detectedCells;
  final int correctedDates;

  const OfficialRosterParseResult({
    required this.assignments,
    required this.unmatchedCells,
    required this.disciplinaryMarks,
    required this.detectedRows,
    required this.detectedCells,
    required this.correctedDates,
  });
}

/// Lit les tableaux de garde Urgences directement depuis le PDF structuré.
///
/// Le format attendu correspond aux plannings officiels actuellement utilisés :
/// - une colonne date ;
/// - une zone 08h-20h ;
/// - une zone 20h-08h ;
/// - une cellule fusionnée centrée sur les deux zones pour une garde 24H.
///
/// Aucune OCR n'est utilisée : pdfrx expose le texte et ses coordonnées PDF.
class OfficialRosterImportService {
  OfficialRosterImportService._();

  static final RegExp _datePattern = RegExp(
    r'\b([0-3]?\d)[/.\-]([01]?\d)(?:[/.\-](20\d{2}|\d{2}))?\b',
    caseSensitive: false,
  );

  static Future<OfficialRosterParseResult> parse({
    required Uint8List bytes,
    required String displayName,
    required String hospital,
    required List<AppUser> profiles,
    DateTime? resourceUpdatedAt,
  }) async {
    final candidateProfiles = profiles
        .where((p) => p.accountStatus == AccountStatus.active && p.hospital == hospital)
        .toList(growable: false);

    final document = await PdfDocument.openData(
      bytes,
      sourceName: displayName,
      useProgressiveLoading: false,
    );

    final rows = <_RosterRow>[];
    try {
      for (var pageIndex = 0; pageIndex < document.pages.length; pageIndex++) {
        final page = document.pages[pageIndex];
        final text = await page.loadStructuredText();

        // Les gardes disciplinaires sont écrites en rouge sur le planning PDF.
        // pdfrx expose les coordonnées de chaque caractère mais pas directement
        // sa couleur : on rend donc la page une seule fois et on échantillonne
        // les pixels BGRA dans les rectangles de caractères.
        PdfImage? rendered;
        try {
          final scale = (page.width > 1100 || page.height > 1100) ? 1.5 : 2.0;
          rendered = await page.render(
            width: (page.width * scale).round(),
            height: (page.height * scale).round(),
          );

          final fragments = text.fragments
              .where((f) => f.text.trim().isNotEmpty)
              .map((f) => _TextFragment(
                    text: f.text.trim(),
                    redText: rendered == null
                        ? ''
                        : _extractRedText(
                            rendered,
                            f.text,
                            f.charRects,
                            page.width,
                            page.height,
                            fallbackBounds: f.bounds,
                          ),
                    left: f.bounds.left,
                    right: f.bounds.right,
                    top: f.bounds.top,
                    bottom: f.bounds.bottom,
                    index: f.index,
                  ))
              .toList(growable: false);
          if (fragments.isEmpty) continue;

        // Certains PDF (notamment HUICK) exposent parfois « 08H - 20H »
        // ou « 20H - 08H » en plusieurs fragments structurés. On accepte les
        // deux formes afin que la lecture automatique reste multi-hôpitaux.
        final dayCenters = _headerCenters(fragments, day: true);
        final nightCenters = _headerCenters(fragments, day: false);
        if (dayCenters.isEmpty || nightCenters.isEmpty) continue;

        final dayCenter = _median(dayCenters);
        final nightCenter = _median(nightCenters);
        if (nightCenter <= dayCenter) continue;
        final midpoint = (dayCenter + nightCenter) / 2;
        final separation = nightCenter - dayCenter;

        for (final dateFragment in fragments) {
          final dateMatch = _datePattern.firstMatch(dateFragment.text);
          if (dateMatch == null) continue;

          final tolerance = (dateFragment.height * 0.70).clamp(3.5, 6.0).toDouble();
          final rowFragments = fragments.where((f) {
            if (identical(f, dateFragment)) return false;
            if ((f.centerY - dateFragment.centerY).abs() > tolerance) return false;
            if (f.left <= dateFragment.right + 2) return false;
            if (_isDayHeader(f.text) || _isNightHeader(f.text)) return false;
            if (_datePattern.hasMatch(f.text)) return false;
            return true;
          }).toList()
            ..sort((a, b) => a.left.compareTo(b.left));

          if (rowFragments.isEmpty) continue;

          final left = rowFragments.map((f) => f.left).reduce((a, b) => a < b ? a : b);
          final right = rowFragments.map((f) => f.right).reduce((a, b) => a > b ? a : b);
          final rowCenter = (left + right) / 2;
          final rowWidth = right - left;
          final isMerged24h =
              (rowCenter - midpoint).abs() <= separation * 0.22 && rowWidth <= separation * 0.90;

          final rawDate = _RawDate.fromMatch(dateMatch);
          if (isMerged24h) {
            rows.add(_RosterRow(
              pageIndex: pageIndex,
              orderIndex: dateFragment.index,
              rawDate: rawDate,
              cells: [
                _RosterCell(
                  shiftId: 'urg-24h',
                  text: rowFragments.map((f) => f.text).join(' '),
                  fragments: rowFragments,
                ),
              ],
            ));
            continue;
          }

          final day = rowFragments.where((f) => f.centerX < midpoint).toList();
          final night = rowFragments.where((f) => f.centerX >= midpoint).toList();
          final cells = <_RosterCell>[];
          if (day.isNotEmpty) {
            cells.add(_RosterCell(
              shiftId: 'urg-jour',
              text: day.map((f) => f.text).join(' '),
              fragments: day,
            ));
          }
          if (night.isNotEmpty) {
            cells.add(_RosterCell(
              shiftId: 'urg-nuit',
              text: night.map((f) => f.text).join(' '),
              fragments: night,
            ));
          }
          if (cells.isNotEmpty) {
            rows.add(_RosterRow(
              pageIndex: pageIndex,
              orderIndex: dateFragment.index,
              rawDate: rawDate,
              cells: cells,
            ));
          }
        }
        } finally {
          rendered?.dispose();
        }
      }
    } finally {
      await document.dispose();
    }

    rows.sort((a, b) {
      final p = a.pageIndex.compareTo(b.pageIndex);
      return p != 0 ? p : a.orderIndex.compareTo(b.orderIndex);
    });

    final fallbackYear = _inferYear(displayName, rows, resourceUpdatedAt);
    DateTime? previous;
    var correctedDates = 0;
    var detectedCells = 0;
    final unmatched = <Map<String, dynamic>>[];
    final disciplinaryMarks = <OfficialRosterDisciplinaryMark>[];
    final rawAssignments = <OfficialRosterAssignment>[];

    for (final row in rows) {
      final resolution = _resolveDate(row.rawDate, fallbackYear, previous);
      final date = resolution.date;
      previous = date;
      if (resolution.corrected) correctedDates++;
      final dateStr = _dateKey(date);

      for (final cell in row.cells) {
        detectedCells++;

        final redText = _cellRedText(cell);
        if (redText.isNotEmpty) {
          disciplinaryMarks.add(
            OfficialRosterDisciplinaryMark(
              dateStr: dateStr,
              shiftId: cell.shiftId,
              redText: redText,
            ),
          );
        }

        final matched = _matchProfiles(cell.text, candidateProfiles);
        if (matched.length != 1) {
          unmatched.add({
            'date': dateStr,
            'shift_id': cell.shiftId,
            'text': cell.text,
            'reason': matched.isEmpty ? 'no_match' : 'ambiguous_match',
            if (matched.length > 1)
              'candidate_profile_ids': matched.map((p) => p.id).toList(),
          });
          continue;
        }
        final profile = matched.single;
        rawAssignments.add(OfficialRosterAssignment(
          profileId: profile.id,
          dateStr: dateStr,
          shiftId: cell.shiftId,
          isDisciplinary: _profileMarkedRed(profile, cell.fragments),
        ));
      }
    }

    final assignments = _coalesceAssignments(rawAssignments);
    return OfficialRosterParseResult(
      assignments: assignments,
      unmatchedCells: unmatched,
      disciplinaryMarks: disciplinaryMarks,
      detectedRows: rows.length,
      detectedCells: detectedCells,
      correctedDates: correctedDates,
    );
  }

  static List<OfficialRosterAssignment> _coalesceAssignments(
    List<OfficialRosterAssignment> input,
  ) {
    final byDoctorDate = <String, Set<String>>{};
    final disciplinaryByDoctorDate = <String, bool>{};
    for (final a in input) {
      final key = '${a.profileId}|${a.dateStr}';
      byDoctorDate.putIfAbsent(key, () => <String>{}).add(a.shiftId);
      disciplinaryByDoctorDate[key] =
          (disciplinaryByDoctorDate[key] ?? false) || a.isDisciplinary;
    }

    final output = <OfficialRosterAssignment>[];
    for (final entry in byDoctorDate.entries) {
      final split = entry.key.split('|');
      final shifts = entry.value;
      String shiftId;
      if (shifts.contains('urg-24h') ||
          (shifts.contains('urg-jour') && shifts.contains('urg-nuit'))) {
        shiftId = 'urg-24h';
      } else if (shifts.contains('urg-jour')) {
        shiftId = 'urg-jour';
      } else {
        shiftId = 'urg-nuit';
      }
      output.add(OfficialRosterAssignment(
        profileId: split[0],
        dateStr: split[1],
        shiftId: shiftId,
        isDisciplinary: disciplinaryByDoctorDate[entry.key] ?? false,
      ));
    }
    output.sort((a, b) {
      final d = a.dateStr.compareTo(b.dateStr);
      return d != 0 ? d : a.profileId.compareTo(b.profileId);
    });
    return output;
  }

  static String _cellRedText(_RosterCell cell) {
    return cell.fragments
        .map((f) => f.redText)
        .where((value) => value.trim().isNotEmpty)
        .join(' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool _profileMarkedRed(
    AppUser profile,
    List<_TextFragment> fragments,
  ) {
    final red = _normalizeName(
      fragments
          .map((f) => f.redText)
          .where((value) => value.trim().isNotEmpty)
          .join(' '),
    );
    if (red.isEmpty) return false;

    final padded = ' $red ';
    final variants = <String>{
      _normalizeName('${profile.prenom} ${profile.nom}'),
      _normalizeName('${profile.nom} ${profile.prenom}'),
    }..removeWhere((v) => v.isEmpty);

    for (final variant in variants) {
      if (padded.contains(' $variant ') || _approximatelyContains(red, variant)) {
        return true;
      }
    }

    // Cas des comptes avec plusieurs prénoms alors que le PDF n'en affiche
    // qu'un : on exige toujours le nom + au moins un prénom rouge.
    final nom = _normalizeName(profile.nom);
    final prenomTokens = _normalizeName(profile.prenom)
        .split(' ')
        .where((t) => t.length >= 2);
    if (nom.isEmpty || !padded.contains(' $nom ')) return false;
    return prenomTokens.any((token) => padded.contains(' $token '));
  }

  static String _extractRedText(
    PdfImage image,
    String text,
    List<dynamic> charRects,
    double pageWidth,
    double pageHeight, {
    required dynamic fallbackBounds,
  }) {
    if (text.isEmpty) return '';
    if (charRects.isEmpty) {
      return _rectLooksRed(
        image,
        fallbackBounds,
        pageWidth,
        pageHeight,
        minRatio: 0.55,
      )
          ? text
          : '';
    }

    final output = StringBuffer();
    final limit = text.length < charRects.length ? text.length : charRects.length;
    for (var i = 0; i < limit; i++) {
      final char = text.substring(i, i + 1);
      if (char.trim().isEmpty) {
        output.write(' ');
        continue;
      }
      output.write(
        _rectLooksRed(image, charRects[i], pageWidth, pageHeight)
            ? char
            : ' ',
      );
    }

    final extracted = output.toString();

    // Sur certains PDF, pdfrx expose des rectangles caractère par caractère
    // imprécis alors que le rectangle du fragment est correct. Si aucun
    // caractère rouge n'a été identifié, on accepte le fragment entier
    // uniquement lorsqu'il est très majoritairement rouge. Ce seuil élevé
    // évite de marquer les autres médecins d'une cellule mixte.
    if (extracted.replaceAll(' ', '').isEmpty &&
        _rectLooksRed(
          image,
          fallbackBounds,
          pageWidth,
          pageHeight,
          minRatio: 0.55,
        )) {
      return text;
    }

    return extracted;
  }

  static bool _rectLooksRed(
    PdfImage image,
    dynamic rect,
    double pageWidth,
    double pageHeight, {
    double minRatio = 0.08,
  }) {
    final left = (rect.left as num).toDouble();
    final right = (rect.right as num).toDouble();
    final top = (rect.top as num).toDouble();
    final bottom = (rect.bottom as num).toDouble();

    final minX = left < right ? left : right;
    final maxX = left > right ? left : right;
    final minY = top < bottom ? top : bottom;
    final maxY = top > bottom ? top : bottom;
    if (maxX <= minX || maxY <= minY || pageWidth <= 0 || pageHeight <= 0) {
      return false;
    }

    bool sample(double y0Page, double y1Page) {
      final xScale = image.width / pageWidth;
      final yScale = image.height / pageHeight;
      var x0 = (minX * xScale).floor() - 1;
      var x1 = (maxX * xScale).ceil() + 1;
      var y0 = (y0Page * yScale).floor() - 1;
      var y1 = (y1Page * yScale).ceil() + 1;
      if (x0 < 0) x0 = 0;
      if (y0 < 0) y0 = 0;
      if (x1 >= image.width) x1 = image.width - 1;
      if (y1 >= image.height) y1 = image.height - 1;
      if (x1 < x0 || y1 < y0) return false;

      var redPixels = 0;
      var inkPixels = 0;
      final pixels = image.pixels;
      for (var y = y0; y <= y1; y++) {
        for (var x = x0; x <= x1; x++) {
          final offset = (y * image.width + x) * 4;
          if (offset + 3 >= pixels.length) continue;
          final b = pixels[offset];
          final g = pixels[offset + 1];
          final r = pixels[offset + 2];
          final a = pixels[offset + 3];
          if (a < 20) continue;
          if (r < 170 || g < 170 || b < 170) inkPixels++;
          if (r >= 145 && r >= g + 35 && r >= b + 35) redPixels++;
        }
      }
      if (redPixels < 2 || inkPixels == 0) return false;
      return redPixels / inkPixels >= minRatio;
    }

    // PdfRect utilise le repère PDF : origine en bas à gauche, axe Y vers le haut.
    // PdfImage est un bitmap : origine en haut à gauche. Il faut donc inverser Y.
    final imageTop = pageHeight - maxY;
    final imageBottom = pageHeight - minY;
    return sample(imageTop, imageBottom);
  }

  static List<AppUser> _matchProfiles(String cellText, List<AppUser> profiles) {
    final normalizedCell = _normalizeName(cellText);
    if (normalizedCell.isEmpty) return const <AppUser>[];
    final padded = ' $normalizedCell ';
    final matches = <AppUser>[];

    for (final profile in profiles) {
      final variants = <String>{
        _normalizeName('${profile.prenom} ${profile.nom}'),
        _normalizeName('${profile.nom} ${profile.prenom}'),
      }..removeWhere((v) => v.isEmpty);

      var found = false;
      for (final variant in variants) {
        if (padded.contains(' $variant ')) {
          found = true;
          break;
        }
        if (_approximatelyContains(normalizedCell, variant)) {
          found = true;
          break;
        }
      }
      if (!found && _identityFallbackMatch(normalizedCell, profile)) {
        found = true;
      }
      if (found) matches.add(profile);
    }
    return matches;
  }

  /// Tolérance contrôlée pour les annuaires où le compte contient plusieurs
  /// prénoms alors que le PDF n'en affiche qu'un. Le nom complet doit rester
  /// contigu, ce qui évite de mélanger deux médecins présents dans la même cellule.
  static bool _identityFallbackMatch(String cell, AppUser profile) {
    final nom = _normalizeName(profile.nom);
    final prenom = _normalizeName(profile.prenom);
    if (nom.isEmpty || prenom.isEmpty) return false;

    final prenomTokens = prenom
        .split(' ')
        .where((t) => t.length >= 2)
        .toSet();
    for (final token in prenomTokens) {
      final forward = '$nom $token';
      final reverse = '$token $nom';
      if (_approximatelyContains(cell, forward) || _approximatelyContains(cell, reverse)) {
        return true;
      }
    }
    return false;
  }

  static bool _approximatelyContains(String cell, String variant) {
    final cellTokens = cell.split(' ').where((t) => t.isNotEmpty).toList();
    final variantTokens = variant.split(' ').where((t) => t.isNotEmpty).toList();
    if (variantTokens.length < 2 || cellTokens.length < variantTokens.length) return false;

    final windowLength = variantTokens.length;
    final allowedDistance = variant.length >= 18 ? 2 : 1;
    for (var i = 0; i <= cellTokens.length - windowLength; i++) {
      final window = cellTokens.sublist(i, i + windowLength).join(' ');
      final distance = _levenshtein(window, variant, cutoff: allowedDistance);
      if (distance <= allowedDistance) {
        final maxLen = window.length > variant.length ? window.length : variant.length;
        if (maxLen == 0 || 1 - distance / maxLen >= 0.90) return true;
      }
    }
    return false;
  }

  static int _levenshtein(String a, String b, {required int cutoff}) {
    if (a == b) return 0;
    if ((a.length - b.length).abs() > cutoff) return cutoff + 1;
    var previous = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0);
      current[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final insertion = current[j - 1] + 1;
        final deletion = previous[j] + 1;
        final substitution = previous[j - 1] + (a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1);
        var value = insertion < deletion ? insertion : deletion;
        if (substitution < value) value = substitution;
        current[j] = value;
      }
      previous = current;
    }
    return previous[b.length];
  }

  static _ResolvedDate _resolveDate(_RawDate raw, int fallbackYear, DateTime? previous) {
    var year = raw.year ?? fallbackYear;
    if (raw.year == null && previous != null) {
      final candidates = <DateTime>[
        DateTime(previous.year - 1, raw.month, raw.day),
        DateTime(previous.year, raw.month, raw.day),
        DateTime(previous.year + 1, raw.month, raw.day),
      ];
      final expected = previous.add(const Duration(days: 1));
      candidates.sort((a, b) =>
          a.difference(expected).inDays.abs().compareTo(b.difference(expected).inDays.abs()));
      year = candidates.first.year;
    }

    var date = DateTime(year, raw.month, raw.day);
    var corrected = false;
    if (previous != null) {
      final expected = previous.add(const Duration(days: 1));
      final distance = date.difference(expected).inDays.abs();
      // Correction très conservatrice d'une coquille de mois évidente :
      // ex. 27/08, 28/09, 29/08 devient 27/08, 28/08, 29/08.
      if (raw.day == expected.day && distance >= 20) {
        date = expected;
        corrected = true;
      }
    }
    return _ResolvedDate(date, corrected);
  }

  static int _inferYear(String displayName, List<_RosterRow> rows, DateTime? updatedAt) {
    final fromName = RegExp(r'\b(20\d{2})\b').firstMatch(displayName);
    if (fromName != null) return int.parse(fromName.group(1)!);
    for (final row in rows) {
      if (row.rawDate.year != null) return row.rawDate.year!;
    }
    return (updatedAt ?? DateTime.now()).year;
  }

  static String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static List<double> _headerCenters(List<_TextFragment> fragments, {required bool day}) {
    bool matchesTarget(String text) {
      final isDay = _isDayHeader(text);
      final isNight = _isNightHeader(text);
      // Un groupe contenant les deux intitulés à la fois est trop large et ne
      // doit pas être utilisé comme centre de colonne.
      return day ? (isDay && !isNight) : (isNight && !isDay);
    }

    final direct = fragments
        .where((f) => matchesTarget(f.text))
        .map((f) => f.centerX)
        .toList();
    if (direct.isNotEmpty) return direct;

    final sorted = [...fragments]
      ..sort((a, b) {
        final y = a.centerY.compareTo(b.centerY);
        return y != 0 ? y : a.left.compareTo(b.left);
      });
    final centers = <double>[];

    for (var i = 0; i < sorted.length; i++) {
      final base = sorted[i];
      var combined = '';
      var left = base.left;
      var right = base.right;
      for (var j = i; j < sorted.length && j < i + 4; j++) {
        final current = sorted[j];
        if (j > i) {
          final verticalTolerance = (base.height * 0.9).clamp(2.5, 6.0).toDouble();
          if ((current.centerY - base.centerY).abs() > verticalTolerance) break;
          final gapLimit = (base.height * 4.0).clamp(16.0, 34.0).toDouble();
          if (current.left - right > gapLimit) break;
        }
        combined = combined.isEmpty ? current.text : '$combined ${current.text}';
        if (current.left < left) left = current.left;
        if (current.right > right) right = current.right;
        if (matchesTarget(combined)) {
          centers.add((left + right) / 2);
          break;
        }
      }
    }

    centers.sort();
    final deduped = <double>[];
    for (final center in centers) {
      if (deduped.isEmpty || (deduped.last - center).abs() > 2.0) {
        deduped.add(center);
      }
    }
    return deduped;
  }

  static bool _isDayHeader(String text) {
    final compact = _normalizeHeader(text).replaceAll(' ', '');
    return compact.contains('08h20h') || compact.contains('8h20h');
  }

  static bool _isNightHeader(String text) {
    final compact = _normalizeHeader(text).replaceAll(' ', '');
    return compact.contains('20h08h') || compact.contains('20h8h');
  }

  static String _normalizeHeader(String input) => input
      .toLowerCase()
      .replaceAll('–', '-')
      .replaceAll('—', '-')
      .replaceAll('-', ' ')
      .replaceAll(RegExp(r'[^a-z0-9h ]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String _normalizeName(String input) {
    var s = input.toLowerCase();
    const replacements = <String, String>{
      'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a',
      'ç': 'c',
      'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
      'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
      'ñ': 'n',
      'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'œ': 'oe',
      'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
      'ý': 'y', 'ÿ': 'y', 'æ': 'ae',
      '’': ' ', "'": ' ', '-': ' ', '–': ' ', '—': ' ',
    };
    for (final e in replacements.entries) {
      s = s.replaceAll(e.key, e.value);
    }
    s = s.replaceAll(RegExp(r'\b(?:dr|docteur)\b', caseSensitive: false), ' ');
    return s
        .replaceAll(RegExp(r'[^a-z0-9 ]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static double _median(List<double> values) {
    final sorted = [...values]..sort();
    final m = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[m];
    return (sorted[m - 1] + sorted[m]) / 2;
  }
}

class _TextFragment {
  final String text;
  final double left;
  final double right;
  final double top;
  final double bottom;
  final int index;
  final String redText;

  const _TextFragment({
    required this.text,
    this.redText = '',
    required this.left,
    required this.right,
    required this.top,
    required this.bottom,
    required this.index,
  });

  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;
  double get height => (top - bottom).abs();
}

class _RawDate {
  final int day;
  final int month;
  final int? year;

  const _RawDate(this.day, this.month, this.year);

  factory _RawDate.fromMatch(RegExpMatch match) {
    final rawYear = match.group(3);
    int? year;
    if (rawYear != null) {
      year = int.parse(rawYear);
      if (year < 100) year += 2000;
    }
    return _RawDate(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      year,
    );
  }
}

class _ResolvedDate {
  final DateTime date;
  final bool corrected;
  const _ResolvedDate(this.date, this.corrected);
}

class _RosterCell {
  final String shiftId;
  final String text;
  final List<_TextFragment> fragments;
  const _RosterCell({
    required this.shiftId,
    required this.text,
    required this.fragments,
  });
}

class _RosterRow {
  final int pageIndex;
  final int orderIndex;
  final _RawDate rawDate;
  final List<_RosterCell> cells;

  const _RosterRow({
    required this.pageIndex,
    required this.orderIndex,
    required this.rawDate,
    required this.cells,
  });
}
