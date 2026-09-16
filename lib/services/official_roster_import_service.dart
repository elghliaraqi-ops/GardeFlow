import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

import '../models/app_user.dart';

class OfficialRosterAssignment {
  final String profileId;
  final String dateStr;
  final String shiftId;

  const OfficialRosterAssignment({
    required this.profileId,
    required this.dateStr,
    required this.shiftId,
  });

  Map<String, dynamic> toJson() => {
        'profile_id': profileId,
        'date': dateStr,
        'shift_id': shiftId,
      };
}

class OfficialRosterParseResult {
  final List<OfficialRosterAssignment> assignments;
  final List<Map<String, dynamic>> unmatchedCells;
  final int detectedRows;
  final int detectedCells;
  final int correctedDates;

  const OfficialRosterParseResult({
    required this.assignments,
    required this.unmatchedCells,
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
        final fragments = text.fragments
            .where((f) => f.text.trim().isNotEmpty)
            .map((f) => _TextFragment(
                  text: f.text.trim(),
                  left: f.bounds.left,
                  right: f.bounds.right,
                  top: f.bounds.top,
                  bottom: f.bounds.bottom,
                  index: f.index,
                ))
            .toList(growable: false);
        if (fragments.isEmpty) continue;

        final dayCenters = fragments
            .where((f) => _isDayHeader(f.text))
            .map((f) => f.centerX)
            .toList();
        final nightCenters = fragments
            .where((f) => _isNightHeader(f.text))
            .map((f) => f.centerX)
            .toList();
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
            ));
          }
          if (night.isNotEmpty) {
            cells.add(_RosterCell(
              shiftId: 'urg-nuit',
              text: night.map((f) => f.text).join(' '),
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
    final rawAssignments = <OfficialRosterAssignment>[];

    for (final row in rows) {
      final resolution = _resolveDate(row.rawDate, fallbackYear, previous);
      final date = resolution.date;
      previous = date;
      if (resolution.corrected) correctedDates++;
      final dateStr = _dateKey(date);

      for (final cell in row.cells) {
        detectedCells++;
        final matched = _matchProfiles(cell.text, candidateProfiles);
        if (matched.isEmpty) {
          unmatched.add({
            'date': dateStr,
            'shift_id': cell.shiftId,
            'text': cell.text,
          });
          continue;
        }
        for (final profile in matched) {
          rawAssignments.add(OfficialRosterAssignment(
            profileId: profile.id,
            dateStr: dateStr,
            shiftId: cell.shiftId,
          ));
        }
      }
    }

    final assignments = _coalesceAssignments(rawAssignments);
    return OfficialRosterParseResult(
      assignments: assignments,
      unmatchedCells: unmatched,
      detectedRows: rows.length,
      detectedCells: detectedCells,
      correctedDates: correctedDates,
    );
  }

  static List<OfficialRosterAssignment> _coalesceAssignments(
    List<OfficialRosterAssignment> input,
  ) {
    final byDoctorDate = <String, Set<String>>{};
    for (final a in input) {
      byDoctorDate.putIfAbsent('${a.profileId}|${a.dateStr}', () => <String>{}).add(a.shiftId);
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
      ));
    }
    output.sort((a, b) {
      final d = a.dateStr.compareTo(b.dateStr);
      return d != 0 ? d : a.profileId.compareTo(b.profileId);
    });
    return output;
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
      if (found) matches.add(profile);
    }
    return matches;
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

  const _TextFragment({
    required this.text,
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
  const _RosterCell({required this.shiftId, required this.text});
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
