import 'dart:typed_data';

import '../data/intern_promotions.dart';
import '../models/app_user.dart';
import '../models/shared_resource.dart';
import 'official_roster_import_service.dart';

class OfficialRosterVerifiedReadService {
  OfficialRosterVerifiedReadService._();

  static Future<OfficialRosterParseResult> readVersionHistory({
    required List<SharedResource> versionsNewestFirst,
    required Future<Uint8List> Function(String storagePath) loadBytes,
    required Future<Map<String, dynamic>?> Function(SharedResource resource)
        loadVerified,
    required String hospital,
    required List<AppUser> profiles,
    Map<String, Uint8List> suppliedBytes = const <String, Uint8List>{},
  }) async {
    final ordered = [...versionsNewestFirst]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final seen = <String>{};
    final results = <OfficialRosterParseResult>[];

    for (final version in ordered) {
      final key = version.storagePath +
          '|' +
          version.updatedAt.toUtc().toIso8601String();
      if (!seen.add(key)) continue;

      OfficialRosterParseResult? local;
      try {
        final bytes =
            suppliedBytes[version.storagePath] ??
            await loadBytes(version.storagePath);
        local = await OfficialRosterImportService.parse(
          bytes: bytes,
          displayName: version.displayName,
          hospital: hospital,
          profiles: profiles,
          resourceUpdatedAt: version.updatedAt,
        );
      } catch (_) {
        local = null;
      }

      Map<String, dynamic>? payload;
      try {
        payload = await loadVerified(version);
      } catch (_) {
        payload = null;
      }

      if (payload != null) {
        final verified = fromExtraction(
          extraction: payload,
          hospital: hospital,
          profiles: profiles,
        );
        if (!verified.isComplete || verified.detectedRows == 0) {
          results.add(verified);
          continue;
        }
        if (local != null &&
            local.isComplete &&
            local.detectedRows > 0 &&
            !sameCoreAssignments(local, verified)) {
          results.add(
            OfficialRosterParseResult(
              assignments: verified.assignments,
              unmatchedCells: verified.unmatchedCells,
              disciplinaryMarks: verified.disciplinaryMarks,
              detectedRows: verified.detectedRows,
              detectedCells: verified.detectedCells,
              correctedDates: verified.correctedDates,
              coveredDates: verified.coveredDates,
              validationErrors: [
                ...verified.validationErrors,
                'Les lectures géométrique et visuelle ne concordent pas.',
              ],
            ),
          );
          continue;
        }
        results.add(verified);
        continue;
      }

      if (local != null) results.add(local);
    }

    if (results.isEmpty) {
      return const OfficialRosterParseResult(
        assignments: <OfficialRosterAssignment>[],
        unmatchedCells: <Map<String, dynamic>>[],
        disciplinaryMarks: <OfficialRosterDisciplinaryMark>[],
        detectedRows: 0,
        detectedCells: 0,
        correctedDates: 0,
        coveredDates: <String>[],
        validationErrors: <String>[
          'Aucune version exploitable du planning officiel.',
        ],
      );
    }

    final invalid = results.where((result) => !result.isComplete).toList();
    if (invalid.isNotEmpty && results.first == invalid.first) {
      return invalid.first;
    }

    return OfficialRosterImportService.mergeNewestFirst(results);
  }

  static OfficialRosterParseResult fromExtraction({
    required Map<String, dynamic> extraction,
    required String hospital,
    required List<AppUser> profiles,
  }) {
    final validationErrors = <String>[];
    final confidence = (extraction['confidence'] as num?)?.toDouble() ?? 0.0;
    if (extraction['verified'] != true) {
      validationErrors.add(
        'La double lecture visuelle du PDF n’a pas été validée.',
      );
    }
    if (confidence < 0.90) {
      validationErrors.add(
        'Confiance de lecture insuffisante (' +
            (confidence * 100).round().toString() +
            ' %).',
      );
    }

    final candidateProfiles = profiles
        .where(
          (p) =>
              p.accountStatus == AccountStatus.active &&
              p.hospital == hospital,
        )
        .toList(growable: false);

    final coverageShifts = <String, Set<String>>{};
    final rawAssignments = <OfficialRosterAssignment>[];
    final unmatched = <Map<String, dynamic>>[];
    final disciplinaryMarks = <OfficialRosterDisciplinaryMark>[];

    final rawRows = extraction['rows'];
    final rows = rawRows is List ? rawRows : const <dynamic>[];
    var detectedCells = 0;

    for (final raw in rows) {
      if (raw is! Map) continue;
      final row = Map<String, dynamic>.from(raw);
      final dateStr = row['date']?.toString().trim() ?? '';
      final shiftId = row['shift']?.toString().trim() ?? '';
      final parsedDate = DateTime.tryParse(dateStr);
      final validDate =
          RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dateStr) &&
              parsedDate != null &&
              _dateKey(parsedDate) == dateStr;
      if (!validDate) {
        validationErrors.add('Date vérifiée invalide : ' + dateStr);
        continue;
      }
      if (shiftId != 'urg-jour' &&
          shiftId != 'urg-nuit' &&
          shiftId != 'urg-24h') {
        validationErrors.add(
          'Créneau vérifié invalide ' + dateStr + ' : ' + shiftId,
        );
        continue;
      }

      detectedCells++;
      coverageShifts.putIfAbsent(dateStr, () => <String>{}).add(shiftId);

      final names = row['names'] is List
          ? (row['names'] as List)
              .map(
                (e) => e
                    .toString()
                    .replaceAll(RegExp(r'\s+'), ' ')
                    .trim(),
              )
              .where((e) => e.isNotEmpty)
              .toList(growable: false)
          : const <String>[];
      final redNames = row['red_names'] is List
          ? (row['red_names'] as List)
              .map((e) => _normalizeName(e.toString()))
              .where((e) => e.isNotEmpty)
              .toSet()
          : <String>{};

      if (redNames.isNotEmpty) {
        disciplinaryMarks.add(
          OfficialRosterDisciplinaryMark(
            dateStr: dateStr,
            shiftId: shiftId,
            redText: redNames.join(' '),
          ),
        );
      }

      for (final name in names) {
        final matched = _matchProfiles(name, candidateProfiles);
        if (matched.length != 1) {
          unmatched.add({
            'date': dateStr,
            'shift_id': shiftId,
            'text': name,
            'reason': matched.isEmpty
                ? 'verified_no_match'
                : 'verified_ambiguous_match',
          });
          continue;
        }

        final normalizedName = _normalizeName(name);
        final isRed = redNames.any(
          (red) =>
              red == normalizedName ||
              _approximatelyContains(red, normalizedName) ||
              _approximatelyContains(normalizedName, red),
        );
        rawAssignments.add(
          OfficialRosterAssignment(
            profileId: matched.single.id,
            dateStr: dateStr,
            shiftId: shiftId,
            isDisciplinary: isRed,
          ),
        );
      }
    }

    validationErrors.addAll(_validateCoverage(coverageShifts));
    final warnings = extraction['warnings'];
    if (warnings is List) {
      for (final warning in warnings.take(6)) {
        final text = warning.toString().trim();
        if (text.isNotEmpty && text.toLowerCase().contains('ambigu')) {
          validationErrors.add('Vérification visuelle : ' + text);
        }
      }
    }

    return OfficialRosterParseResult(
      assignments: _coalesceAssignments(rawAssignments),
      unmatchedCells: unmatched,
      disciplinaryMarks: disciplinaryMarks,
      detectedRows: coverageShifts.length,
      detectedCells: detectedCells,
      correctedDates: 0,
      coveredDates: coverageShifts.keys.toList()..sort(),
      validationErrors: validationErrors,
    );
  }

  static bool sameCoreAssignments(
    OfficialRosterParseResult a,
    OfficialRosterParseResult b,
  ) {
    final datesA = a.coveredDates.toSet();
    final datesB = b.coveredDates.toSet();
    if (datesA.length != datesB.length || !datesA.containsAll(datesB)) {
      return false;
    }

    Set<String> keys(OfficialRosterParseResult value) {
      return value.assignments
          .map(
            (assignment) =>
                assignment.profileId +
                '|' +
                assignment.dateStr +
                '|' +
                assignment.shiftId,
          )
          .toSet();
    }

    final aKeys = keys(a);
    final bKeys = keys(b);
    return aKeys.length == bKeys.length && aKeys.containsAll(bKeys);
  }

  static List<OfficialRosterAssignment> _coalesceAssignments(
    List<OfficialRosterAssignment> input,
  ) {
    final byDoctorDate = <String, Set<String>>{};
    final disciplinaryByDoctorDate = <String, bool>{};

    for (final assignment in input) {
      final key = assignment.profileId + '|' + assignment.dateStr;
      byDoctorDate.putIfAbsent(key, () => <String>{}).add(assignment.shiftId);
      disciplinaryByDoctorDate[key] =
          (disciplinaryByDoctorDate[key] ?? false) ||
              assignment.isDisciplinary;
    }

    final output = <OfficialRosterAssignment>[];
    for (final entry in byDoctorDate.entries) {
      final separator = entry.key.indexOf('|');
      if (separator <= 0) continue;
      final profileId = entry.key.substring(0, separator);
      final dateStr = entry.key.substring(separator + 1);
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
      output.add(
        OfficialRosterAssignment(
          profileId: profileId,
          dateStr: dateStr,
          shiftId: shiftId,
          isDisciplinary: disciplinaryByDoctorDate[entry.key] ?? false,
        ),
      );
    }

    output.sort((a, b) {
      final byDate = a.dateStr.compareTo(b.dateStr);
      return byDate != 0 ? byDate : a.profileId.compareTo(b.profileId);
    });
    return output;
  }

  static List<String> _validateCoverage(
    Map<String, Set<String>> coverageShifts,
  ) {
    if (coverageShifts.isEmpty) {
      return const <String>['Aucune date exploitable détectée.'];
    }

    final dates = coverageShifts.keys.map(DateTime.parse).toList()..sort();
    final errors = <String>[];
    final keys = coverageShifts.keys.toSet();
    var cursor = dates.first;
    final last = dates.last;

    while (!cursor.isAfter(last)) {
      final key = _dateKey(cursor);
      if (!keys.contains(key)) {
        errors.add('Date absente du tableau : ' + key);
      }
      cursor = cursor.add(const Duration(days: 1));
    }

    for (final key in coverageShifts.keys.toList()..sort()) {
      final shifts = coverageShifts[key] ?? const <String>{};
      final valid24h = shifts.length == 1 && shifts.contains('urg-24h');
      final validSplit = shifts.length == 2 &&
          shifts.contains('urg-jour') &&
          shifts.contains('urg-nuit');
      if (!valid24h && !validSplit) {
        final labels = shifts.toList()..sort();
        errors.add(
          'Ligne incomplète ' +
              key +
              ' : ' +
              (labels.isEmpty ? 'aucun créneau' : labels.join(' + ')),
        );
      }
    }

    return errors;
  }

  static List<AppUser> _matchProfiles(
    String cellText,
    List<AppUser> profiles,
  ) {
    final normalizedCell = _normalizeName(cellText);
    if (normalizedCell.isEmpty) return const <AppUser>[];
    final padded = ' ' + normalizedCell + ' ';
    final matches = <AppUser>[];

    for (final profile in profiles) {
      final variants = <String>{
        _normalizeName(profile.prenom + ' ' + profile.nom),
        _normalizeName(profile.nom + ' ' + profile.prenom),
        ...InternPromotions.officialRosterAliasesFor(profile)
            .map(_normalizeName),
      }..removeWhere((value) => value.isEmpty);

      var found = false;
      for (final variant in variants) {
        if (padded.contains(' ' + variant + ' ') ||
            _approximatelyContains(normalizedCell, variant)) {
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

  static bool _identityFallbackMatch(String cell, AppUser profile) {
    final nom = _normalizeName(profile.nom);
    final prenom = _normalizeName(profile.prenom);
    if (nom.isEmpty || prenom.isEmpty) return false;

    final prenomTokens =
        prenom.split(' ').where((token) => token.length >= 2).toSet();
    for (final token in prenomTokens) {
      if (_approximatelyContains(cell, nom + ' ' + token) ||
          _approximatelyContains(cell, token + ' ' + nom)) {
        return true;
      }
    }
    return false;
  }

  static bool _approximatelyContains(String cell, String variant) {
    final cellTokens = cell.split(' ').where((t) => t.isNotEmpty).toList();
    final variantTokens =
        variant.split(' ').where((t) => t.isNotEmpty).toList();
    if (variantTokens.length < 2 ||
        cellTokens.length < variantTokens.length) {
      return false;
    }

    final windowLength = variantTokens.length;
    final allowedDistance = variant.length >= 18 ? 2 : 1;
    for (var i = 0; i <= cellTokens.length - windowLength; i++) {
      final window = cellTokens.sublist(i, i + windowLength).join(' ');
      final distance =
          _levenshtein(window, variant, cutoff: allowedDistance);
      if (distance <= allowedDistance) {
        final maxLen =
            window.length > variant.length ? window.length : variant.length;
        if (maxLen == 0 || 1 - distance / maxLen >= 0.90) return true;
      }
    }
    return false;
  }

  static int _levenshtein(
    String a,
    String b, {
    required int cutoff,
  }) {
    if (a == b) return 0;
    if ((a.length - b.length).abs() > cutoff) return cutoff + 1;

    var previous = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0);
      current[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final insertion = current[j - 1] + 1;
        final deletion = previous[j] + 1;
        final substitution = previous[j - 1] +
            (a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1);
        var value = insertion < deletion ? insertion : deletion;
        if (substitution < value) value = substitution;
        current[j] = value;
      }
      previous = current;
    }
    return previous[b.length];
  }

  static String _normalizeName(String input) {
    var value = input.toLowerCase();
    const replacements = <String, String>{
      'à': 'a',
      'á': 'a',
      'â': 'a',
      'ä': 'a',
      'ã': 'a',
      'å': 'a',
      'ç': 'c',
      'è': 'e',
      'é': 'e',
      'ê': 'e',
      'ë': 'e',
      'ì': 'i',
      'í': 'i',
      'î': 'i',
      'ï': 'i',
      'ñ': 'n',
      'ò': 'o',
      'ó': 'o',
      'ô': 'o',
      'ö': 'o',
      'õ': 'o',
      'œ': 'oe',
      'ù': 'u',
      'ú': 'u',
      'û': 'u',
      'ü': 'u',
      'ý': 'y',
      'ÿ': 'y',
      'æ': 'ae',
      '’': ' ',
      "'": ' ',
      '-': ' ',
      '–': ' ',
      '—': ' ',
    };

    for (final entry in replacements.entries) {
      value = value.replaceAll(entry.key, entry.value);
    }

    value = value.replaceAll(
      RegExp(r'\b(?:dr|docteur)\b', caseSensitive: false),
      ' ',
    );
    return value
        .replaceAll(RegExp(r'[^a-z0-9 ]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _dateKey(DateTime date) {
    return date.year.toString().padLeft(4, '0') +
        '-' +
        date.month.toString().padLeft(2, '0') +
        '-' +
        date.day.toString().padLeft(2, '0');
  }
}
