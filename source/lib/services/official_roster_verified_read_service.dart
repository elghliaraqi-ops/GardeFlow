import 'dart:typed_data';

import '../models/app_user.dart';
import '../models/official_roster_guard.dart';
import '../models/shared_resource.dart';
import 'official_roster_identity_service.dart';
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
    Map<String, String> identityLinks = const <String, String>{},
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
          identityLinks: identityLinks,
        );
        results.add(verified);
        continue;
      }

      // Historical R4/R5 archives can still be used as coverage fallback.
      // New R6 publications always prefer the account-independent verified
      // extraction when it exists.
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
    if (invalid.isNotEmpty && identical(results.first, invalid.first)) {
      return invalid.first;
    }

    return OfficialRosterImportService.mergeNewestFirst(results);
  }

  static OfficialRosterParseResult fromExtraction({
    required Map<String, dynamic> extraction,
    required String hospital,
    required List<AppUser> profiles,
    Map<String, String> identityLinks = const <String, String>{},
  }) {
    final validationErrors = <String>[];
    final confidence = (extraction['confidence'] as num?)?.toDouble() ?? 0.0;
    final status = extraction['status']?.toString().toLowerCase() ?? 'red';

    if (extraction['verified'] != true || status == 'red') {
      validationErrors.add(
        'La vérification indépendante A/B/C du PDF n’a pas été validée.',
      );
    }
    if (confidence < 0.90) {
      validationErrors.add(
        'Confiance de lecture insuffisante (' +
            (confidence * 100).round().toString() +
            ' %).',
      );
    }

    final serverErrors = extraction['validation_errors'];
    if (serverErrors is List) {
      for (final error in serverErrors) {
        final text = error.toString().trim();
        if (text.isNotEmpty) validationErrors.add(text);
      }
    }

    final candidateProfiles = profiles
        .where(
          (profile) =>
              profile.accountStatus == AccountStatus.active &&
              profile.hospital == hospital,
        )
        .toList(growable: false);

    final coverageShifts = <String, Set<String>>{};
    final rawAssignments = <OfficialRosterAssignment>[];
    final unmatched = <Map<String, dynamic>>[];
    final disciplinaryMarks = <OfficialRosterDisciplinaryMark>[];
    final rawOfficialGuards = <OfficialRosterGuard>[];

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

      final redNames = row['red_names'] is List
          ? (row['red_names'] as List)
              .map(
                (value) =>
                    OfficialRosterIdentityService.normalizeConservative(
                  value.toString(),
                ),
              )
              .where((value) => value.isNotEmpty)
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

      final rawDoctors = row['doctors'];
      if (rawDoctors is! List) {
        final legacyNames = row['names'] is List
            ? (row['names'] as List)
                .map((value) => value.toString().trim())
                .where((value) => value.isNotEmpty)
                .toList(growable: false)
            : const <String>[];
        for (final name in legacyNames) {
          unmatched.add({
            'date': dateStr,
            'shift_id': shiftId,
            'text': name,
            'reason': 'identity_components_missing',
          });
        }
        if (legacyNames.isNotEmpty) {
          validationErrors.add(
            'Identité R6 incomplète ' + dateStr + ' ' + shiftId +
                ' : prénom et nom séparés requis.',
          );
        }
        continue;
      }

      for (final rawDoctor in rawDoctors) {
        if (rawDoctor is! Map) continue;
        final doctor = Map<String, dynamic>.from(rawDoctor);
        final firstName = doctor['first_name']?.toString().trim() ?? '';
        final lastName = doctor['last_name']?.toString().trim() ?? '';
        final fullName = doctor['full_name']?.toString().trim() ??
            (firstName + ' ' + lastName).trim();
        final doctorConfidence =
            ((doctor['confidence'] as num?)?.toDouble() ?? 0.0)
                .clamp(0.0, 1.0);
        final guardConfidence =
            doctorConfidence < confidence ? doctorConfidence : confidence;
        final identityKey = OfficialRosterIdentityService.identityKey(
          firstName: firstName,
          lastName: lastName,
        );
        final persistentProfileId = identityLinks[identityKey];

        final resolution = OfficialRosterIdentityService.resolve(
          firstName: firstName,
          lastName: lastName,
          profiles: candidateProfiles,
          persistentProfileId: persistentProfileId,
        );

        final suggestions = resolution.suggestions
            .map(
              (candidate) => <String, dynamic>{
                'profile_id': candidate.profile.id,
                'name': candidate.profile.fullName,
                'score': candidate.score,
                'exact': candidate.exact,
              },
            )
            .toList(growable: false);

        OfficialDoctorMatchStatus matchStatus;
        if (resolution.matched) {
          matchStatus = OfficialDoctorMatchStatus.matched;
        } else if (resolution.ambiguous || suggestions.length > 1) {
          matchStatus = OfficialDoctorMatchStatus.ambiguous;
        } else if (suggestions.isNotEmpty) {
          matchStatus = OfficialDoctorMatchStatus.manualReview;
        } else {
          matchStatus = OfficialDoctorMatchStatus.unregistered;
        }

        final normalizedFull =
            OfficialRosterIdentityService.normalizeConservative(fullName);
        final isRed = redNames.contains(normalizedFull);

        final reviewStatus = status == 'orange'
            ? OfficialRosterReviewStatus.orange
            : status == 'green'
                ? OfficialRosterReviewStatus.green
                : OfficialRosterReviewStatus.red;

        final guard = OfficialRosterGuard(
          dateStr: dateStr,
          shiftId: shiftId,
          hospital: hospital,
          identity: OfficialRosterDoctorIdentity(
            firstName: firstName,
            lastName: lastName,
            fullName: fullName,
          ),
          confidence: guardConfidence,
          reviewStatus: reviewStatus,
          pageNumber: (row['page_number'] as num?)?.toInt(),
          zone: row['zone']?.toString(),
          isDisciplinary: isRed,
          matchedProfileId: resolution.profileId,
          matchStatus: matchStatus,
        );
        rawOfficialGuards.add(guard);

        if (firstName.isEmpty || lastName.isEmpty) {
          validationErrors.add(
            'Prénom/nom incomplet ' + dateStr + ' ' + shiftId +
                ' : ' + fullName,
          );
        }
        if (guardConfidence < 0.90) {
          validationErrors.add(
            'Confiance insuffisante ' + dateStr + ' ' + shiftId +
                ' : ' + fullName,
          );
        }

        if (resolution.matched && guardConfidence >= 0.90) {
          rawAssignments.add(
            OfficialRosterAssignment(
              profileId: resolution.profileId!,
              dateStr: dateStr,
              shiftId: shiftId,
              isDisciplinary: isRed,
            ),
          );
        } else {
          unmatched.add({
            'date': dateStr,
            'shift_id': shiftId,
            'text': fullName,
            'first_name': firstName,
            'last_name': lastName,
            'full_name': fullName,
            'confidence': guardConfidence,
            'page_number': (row['page_number'] as num?)?.toInt(),
            'zone': row['zone']?.toString(),
            'reason': matchStatus == OfficialDoctorMatchStatus.ambiguous
                ? 'ambiguous_identity'
                : matchStatus == OfficialDoctorMatchStatus.manualReview
                    ? 'potential_identity_requires_admin'
                    : 'doctor_not_registered',
            'candidates': suggestions,
          });
        }
      }
    }

    validationErrors.addAll(_validateCoverage(coverageShifts));

    return OfficialRosterParseResult(
      assignments: _coalesceAssignments(rawAssignments),
      unmatchedCells: unmatched,
      disciplinaryMarks: disciplinaryMarks,
      detectedRows: coverageShifts.length,
      detectedCells: detectedCells,
      correctedDates: 0,
      coveredDates: coverageShifts.keys.toList()..sort(),
      validationErrors: [...validationErrors.toSet()],
      officialGuards: _coalesceOfficialGuards(rawOfficialGuards),
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
      final shiftId = _coalescedShift(entry.value);
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

  static List<OfficialRosterGuard> _coalesceOfficialGuards(
    List<OfficialRosterGuard> input,
  ) {
    final byKey = <String, List<OfficialRosterGuard>>{};
    for (final guard in input) {
      final identity = OfficialRosterIdentityService.identityKey(
        firstName: guard.identity.firstName,
        lastName: guard.identity.lastName,
      );
      final key = identity + '|' + guard.dateStr;
      byKey.putIfAbsent(key, () => <OfficialRosterGuard>[]).add(guard);
    }

    final output = <OfficialRosterGuard>[];
    for (final values in byKey.values) {
      if (values.isEmpty) continue;
      final first = values.first;
      final shifts = values.map((guard) => guard.shiftId).toSet();
      var confidence = first.confidence;
      var disciplinary = false;
      for (final guard in values) {
        if (guard.confidence < confidence) confidence = guard.confidence;
        disciplinary = disciplinary || guard.isDisciplinary;
      }
      output.add(
        OfficialRosterGuard(
          dateStr: first.dateStr,
          shiftId: _coalescedShift(shifts),
          hospital: first.hospital,
          identity: first.identity,
          confidence: confidence,
          reviewStatus: first.reviewStatus,
          pageNumber: first.pageNumber,
          zone: values.map((guard) => guard.zone).whereType<String>().join(' / '),
          isDisciplinary: disciplinary,
          matchedProfileId: first.matchedProfileId,
          matchStatus: first.matchStatus,
        ),
      );
    }

    output.sort((a, b) {
      final byDate = a.dateStr.compareTo(b.dateStr);
      if (byDate != 0) return byDate;
      return a.displayName.compareTo(b.displayName);
    });
    return output;
  }

  static String _coalescedShift(Set<String> shifts) {
    if (shifts.contains('urg-24h') ||
        (shifts.contains('urg-jour') && shifts.contains('urg-nuit'))) {
      return 'urg-24h';
    }
    if (shifts.contains('urg-jour')) return 'urg-jour';
    return 'urg-nuit';
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

  static String _dateKey(DateTime date) {
    return date.year.toString().padLeft(4, '0') +
        '-' +
        date.month.toString().padLeft(2, '0') +
        '-' +
        date.day.toString().padLeft(2, '0');
  }
}
