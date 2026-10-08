import 'official_roster_identity_service.dart';

class OfficialRosterLocalCell {
  final String date;
  final String shift;
  final String text;
  final String redText;
  final int? pageNumber;
  final String? zone;

  const OfficialRosterLocalCell({
    required this.date,
    required this.shift,
    required this.text,
    this.redText = '',
    this.pageNumber,
    this.zone,
  });

  String get key => '$date|$shift';

  Map<String, dynamic> toJson() => {
        'date': date,
        'shift': shift,
        'text': text,
        'red_text': redText,
        'page_number': pageNumber,
        'zone': zone,
      };
}

class OfficialRosterVisualDoctor {
  final String firstName;
  final String lastName;
  final String fullName;
  final double confidence;

  const OfficialRosterVisualDoctor({
    required this.firstName,
    required this.lastName,
    required this.fullName,
    required this.confidence,
  });

  String get effectiveFullName =>
      fullName.trim().isNotEmpty ? fullName.trim() : '$firstName $lastName'.trim();

  Map<String, dynamic> toJson() => {
        'first_name': firstName,
        'last_name': lastName,
        'full_name': effectiveFullName,
        'confidence': confidence,
      };

  factory OfficialRosterVisualDoctor.fromJson(Map<String, dynamic> json) {
    return OfficialRosterVisualDoctor(
      firstName: (json['first_name'] ?? '').toString().trim(),
      lastName: (json['last_name'] ?? '').toString().trim(),
      fullName: (json['full_name'] ?? '').toString().trim(),
      confidence: ((json['confidence'] as num?)?.toDouble() ?? 0)
          .clamp(0.0, 1.0).toDouble(),
    );
  }
}

class OfficialRosterVisualRow {
  final String date;
  final String shift;
  final List<OfficialRosterVisualDoctor> doctors;
  final List<String> redNames;
  final int? pageNumber;
  final String? zone;

  const OfficialRosterVisualRow({
    required this.date,
    required this.shift,
    required this.doctors,
    this.redNames = const [],
    this.pageNumber,
    this.zone,
  });

  String get key => '$date|$shift';

  Map<String, dynamic> toJson() => {
        'date': date,
        'shift': shift,
        'doctors': doctors.map((doctor) => doctor.toJson()).toList(),
        'names': doctors.map((doctor) => doctor.effectiveFullName).toList(),
        'red_names': redNames,
        'page_number': pageNumber,
        'zone': zone,
      };

  factory OfficialRosterVisualRow.fromJson(Map<String, dynamic> json) {
    final rawDoctors = json['doctors'];
    final doctors = rawDoctors is List
        ? rawDoctors
            .whereType<Map>()
            .map(
              (raw) => OfficialRosterVisualDoctor.fromJson(
                Map<String, dynamic>.from(raw),
              ),
            )
            .toList(growable: false)
        : <OfficialRosterVisualDoctor>[];

    // Backward compatibility with R5 cached reads.
    final compatibleDoctors = doctors.isNotEmpty
        ? doctors
        : (json['names'] is List
            ? (json['names'] as List)
                .map(
                  (name) => OfficialRosterVisualDoctor(
                    firstName: '',
                    lastName: '',
                    fullName: name.toString().trim(),
                    confidence: 0.90,
                  ),
                )
                .where((doctor) => doctor.fullName.isNotEmpty)
                .toList(growable: false)
            : <OfficialRosterVisualDoctor>[]);

    return OfficialRosterVisualRow(
      date: (json['date'] ?? '').toString().trim(),
      shift: (json['shift'] ?? '').toString().trim(),
      doctors: compatibleDoctors,
      redNames: json['red_names'] is List
          ? (json['red_names'] as List)
              .map((value) => value.toString().trim())
              .where((value) => value.isNotEmpty)
              .toList(growable: false)
          : const [],
      pageNumber: (json['page_number'] as num?)?.toInt(),
      zone: json['zone']?.toString(),
    );
  }
}

class OfficialRosterVisualRead {
  final double confidence;
  final List<OfficialRosterVisualRow> rows;
  final List<String> validationErrors;

  const OfficialRosterVisualRead({
    required this.confidence,
    required this.rows,
    this.validationErrors = const [],
  });
}

class OfficialRosterConflict {
  final String code;
  final String? date;
  final String? shift;
  final String message;
  final Map<String, dynamic> a;
  final Map<String, dynamic> b;
  final Map<String, dynamic>? c;

  const OfficialRosterConflict({
    required this.code,
    required this.message,
    this.date,
    this.shift,
    this.a = const {},
    this.b = const {},
    this.c,
  });

  Map<String, dynamic> toJson() => {
        'code': code,
        'date': date,
        'shift': shift,
        'message': message,
        'a': a,
        'b': b,
        if (c != null) 'c': c,
      };
}

enum OfficialRosterConsensusStatus { green, orange, red }

class OfficialRosterConsensusDecision {
  final OfficialRosterConsensusStatus status;
  final bool requiresC;
  final List<OfficialRosterVisualRow> chosenRows;
  final List<OfficialRosterConflict> conflicts;
  final List<String> validationErrors;
  final double confidence;

  const OfficialRosterConsensusDecision({
    required this.status,
    required this.requiresC,
    required this.chosenRows,
    required this.conflicts,
    required this.validationErrors,
    required this.confidence,
  });

  bool get publishable =>
      status != OfficialRosterConsensusStatus.red &&
      !requiresC &&
      validationErrors.isEmpty;
}

class OfficialRosterConsensusService {
  OfficialRosterConsensusService._();

  static const double minimumConfidence = 0.90;

  static OfficialRosterConsensusDecision evaluate({
    required List<OfficialRosterLocalCell> localA,
    required OfficialRosterVisualRead visualB,
    OfficialRosterVisualRead? visualC,
  }) {
    final aErrors = validateCoverage(
      localA.map((cell) => MapEntry(cell.date, cell.shift)),
    );
    final bErrors = <String>[
      ...visualB.validationErrors,
      ...validateCoverage(
        visualB.rows.map((row) => MapEntry(row.date, row.shift)),
      ),
      ..._visualIdentityErrors(visualB),
    ];

    final abConflicts = compareLocalAndVisual(localA, visualB.rows);
    final bConfidenceOk = _readConfidenceOk(visualB);

    if (aErrors.isEmpty &&
        bErrors.isEmpty &&
        abConflicts.isEmpty &&
        bConfidenceOk) {
      return OfficialRosterConsensusDecision(
        status: OfficialRosterConsensusStatus.green,
        requiresC: false,
        chosenRows: visualB.rows,
        conflicts: const [],
        validationErrors: const [],
        confidence: _minimumGuardConfidence(visualB),
      );
    }

    if (visualC == null) {
      return OfficialRosterConsensusDecision(
        status: OfficialRosterConsensusStatus.red,
        requiresC: true,
        chosenRows: visualB.rows,
        conflicts: abConflicts,
        validationErrors: [...aErrors, ...bErrors],
        confidence: _minimumGuardConfidence(visualB),
      );
    }

    final cErrors = <String>[
      ...visualC.validationErrors,
      ...validateCoverage(
        visualC.rows.map((row) => MapEntry(row.date, row.shift)),
      ),
      ..._visualIdentityErrors(visualC),
    ];
    final cConfidenceOk = _readConfidenceOk(visualC);
    final bcSame = canonicalVisual(visualB.rows) == canonicalVisual(visualC.rows);
    final acConflicts = compareLocalAndVisual(localA, visualC.rows);

    if (aErrors.isEmpty &&
        cErrors.isEmpty &&
        cConfidenceOk &&
        acConflicts.isEmpty) {
      return OfficialRosterConsensusDecision(
        status: OfficialRosterConsensusStatus.orange,
        requiresC: false,
        chosenRows: visualC.rows,
        conflicts: _mergeConflicts(abConflicts, acConflicts),
        validationErrors: const [],
        confidence: _minimumGuardConfidence(visualC),
      );
    }

    if (aErrors.isEmpty &&
        bErrors.isEmpty &&
        cErrors.isEmpty &&
        bConfidenceOk &&
        cConfidenceOk &&
        bcSame) {
      return OfficialRosterConsensusDecision(
        status: OfficialRosterConsensusStatus.orange,
        requiresC: false,
        chosenRows: visualC.rows,
        conflicts: abConflicts,
        validationErrors: const [],
        confidence: _minimum(
          _minimumGuardConfidence(visualB),
          _minimumGuardConfidence(visualC),
        ),
      );
    }

    return OfficialRosterConsensusDecision(
      status: OfficialRosterConsensusStatus.red,
      requiresC: false,
      chosenRows: const [],
      conflicts: _mergeConflicts(
        abConflicts,
        compareVisualReads(visualB.rows, visualC.rows),
      ),
      validationErrors: [...aErrors, ...bErrors, ...cErrors],
      confidence: _minimum(
        _minimumGuardConfidence(visualB),
        _minimumGuardConfidence(visualC),
      ),
    );
  }

  static List<String> validateCoverage(Iterable<MapEntry<String, String>> rows) {
    final byDate = <String, Set<String>>{};
    final errors = <String>[];
    for (final row in rows) {
      final date = row.key.trim();
      final shift = row.value.trim();
      final parsed = DateTime.tryParse(date);
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
          parsed == null) {
        errors.add('Date invalide : $date');
        continue;
      }
      if (shift != 'urg-jour' &&
          shift != 'urg-nuit' &&
          shift != 'urg-24h') {
        errors.add('Créneau invalide $date : $shift');
        continue;
      }
      byDate.putIfAbsent(date, () => <String>{}).add(shift);
    }
    if (byDate.isEmpty) {
      errors.add('Aucune date exploitable détectée.');
      return errors;
    }

    final dates = byDate.keys.map(DateTime.parse).toList()..sort();
    var cursor = dates.first;
    final last = dates.last;
    while (!cursor.isAfter(last)) {
      final key =
          '${cursor.year.toString().padLeft(4, '0')}-'
          '${cursor.month.toString().padLeft(2, '0')}-'
          '${cursor.day.toString().padLeft(2, '0')}';
      if (!byDate.containsKey(key)) {
        errors.add('Date absente du tableau : $key');
      }
      cursor = cursor.add(const Duration(days: 1));
    }

    for (final entry in byDate.entries) {
      final shifts = entry.value;
      final valid24 = shifts.length == 1 && shifts.contains('urg-24h');
      final validSplit = shifts.length == 2 &&
          shifts.contains('urg-jour') &&
          shifts.contains('urg-nuit');
      if (!valid24 && !validSplit) {
        errors.add(
          'Ligne incomplète ${entry.key} : ${shifts.toList()..sort()}',
        );
      }
    }
    return errors;
  }

  static List<OfficialRosterConflict> compareLocalAndVisual(
    List<OfficialRosterLocalCell> local,
    List<OfficialRosterVisualRow> visual,
  ) {
    final localByKey = {for (final cell in local) cell.key: cell};
    final visualByKey = {for (final row in visual) row.key: row};
    final keys = {...localByKey.keys, ...visualByKey.keys}.toList()..sort();
    final conflicts = <OfficialRosterConflict>[];

    for (final key in keys) {
      final a = localByKey[key];
      final b = visualByKey[key];
      final parts = key.split('|');
      final date = parts.isNotEmpty ? parts.first : null;
      final shift = parts.length > 1 ? parts[1] : null;
      if (a == null || b == null) {
        conflicts.add(
          OfficialRosterConflict(
            code: 'missing_cell',
            date: date,
            shift: shift,
            message: a == null
                ? 'Cellule présente en B mais absente en A.'
                : 'Cellule présente en A mais absente en B.',
            a: a?.toJson() ?? const {},
            b: b?.toJson() ?? const {},
          ),
        );
        continue;
      }

      final localTokens = _tokenBag(a.text);
      final visualTokens = _tokenBag(
        b.doctors.map((doctor) => doctor.effectiveFullName).join(' '),
      );
      if (!_sameBag(localTokens, visualTokens)) {
        conflicts.add(
          OfficialRosterConflict(
            code: 'identity_mismatch',
            date: date,
            shift: shift,
            message: 'Le contenu nominatif de la cellule diffère entre A et B.',
            a: a.toJson(),
            b: b.toJson(),
          ),
        );
      }

      if (a.redText.trim().isNotEmpty || b.redNames.isNotEmpty) {
        if (!_sameBag(
          _tokenBag(a.redText),
          _tokenBag(b.redNames.join(' ')),
        )) {
          conflicts.add(
            OfficialRosterConflict(
              code: 'disciplinary_mismatch',
              date: date,
              shift: shift,
              message: 'Le marquage disciplinaire diffère entre A et B.',
              a: a.toJson(),
              b: b.toJson(),
            ),
          );
        }
      }
    }
    return conflicts;
  }

  static List<OfficialRosterConflict> compareVisualReads(
    List<OfficialRosterVisualRow> b,
    List<OfficialRosterVisualRow> c,
  ) {
    if (canonicalVisual(b) == canonicalVisual(c)) return const [];
    final bByKey = {for (final row in b) row.key: row};
    final cByKey = {for (final row in c) row.key: row};
    final keys = {...bByKey.keys, ...cByKey.keys}.toList()..sort();
    final conflicts = <OfficialRosterConflict>[];
    for (final key in keys) {
      final bRow = bByKey[key];
      final cRow = cByKey[key];
      if (bRow == null || cRow == null ||
          _canonicalRow(bRow) != _canonicalRow(cRow)) {
        final parts = key.split('|');
        conflicts.add(
          OfficialRosterConflict(
            code: 'b_c_mismatch',
            date: parts.isNotEmpty ? parts.first : null,
            shift: parts.length > 1 ? parts[1] : null,
            message: 'Les lectures B et C ne concordent pas.',
            b: bRow?.toJson() ?? const {},
            c: cRow?.toJson(),
          ),
        );
      }
    }
    return conflicts;
  }

  static String canonicalVisual(List<OfficialRosterVisualRow> rows) {
    final values = rows.map(_canonicalRow).toList()..sort();
    return values.join('\n');
  }

  static String _canonicalRow(OfficialRosterVisualRow row) {
    final doctors = row.doctors
        .map(
          (doctor) =>
              '${OfficialRosterIdentityService.normalizeConservative(doctor.firstName)}|'
              '${OfficialRosterIdentityService.normalizeConservative(doctor.lastName)}|'
              '${OfficialRosterIdentityService.normalizeConservative(doctor.effectiveFullName)}',
        )
        .toList()
      ..sort();
    final red = row.redNames
        .map(OfficialRosterIdentityService.normalizeConservative)
        .toList()
      ..sort();
    return '${row.key}|${doctors.join(',')}|red:${red.join(',')}';
  }

  static List<String> _visualIdentityErrors(OfficialRosterVisualRead read) {
    final errors = <String>[];
    for (final row in read.rows) {
      for (final doctor in row.doctors) {
        if (OfficialRosterIdentityService
                .normalizeConservative(doctor.firstName)
                .isEmpty ||
            OfficialRosterIdentityService
                .normalizeConservative(doctor.lastName)
                .isEmpty) {
          errors.add(
            'Identité incomplète ${row.date} ${row.shift} : '
            '${doctor.effectiveFullName}',
          );
        }
        if (doctor.confidence < minimumConfidence) {
          errors.add(
            'Confiance nominative faible ${row.date} ${row.shift} : '
            '${doctor.effectiveFullName}',
          );
        }
      }
    }
    return errors;
  }

  static bool _readConfidenceOk(OfficialRosterVisualRead read) {
    return read.confidence >= minimumConfidence &&
        read.rows.every(
          (row) =>
              row.doctors.every(
                (doctor) => doctor.confidence >= minimumConfidence,
              ),
        );
  }

  static double _minimumGuardConfidence(OfficialRosterVisualRead read) {
    var value = read.confidence.clamp(0.0, 1.0).toDouble();
    for (final row in read.rows) {
      for (final doctor in row.doctors) {
        if (doctor.confidence < value) value = doctor.confidence;
      }
    }
    return value;
  }

  static Map<String, int> _tokenBag(String value) {
    final normalized =
        OfficialRosterIdentityService.normalizeConservative(value);
    final bag = <String, int>{};
    for (final token in normalized.split(' ')) {
      if (token.isEmpty) continue;
      bag[token] = (bag[token] ?? 0) + 1;
    }
    return bag;
  }

  static bool _sameBag(Map<String, int> a, Map<String, int> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  static List<OfficialRosterConflict> _mergeConflicts(
    List<OfficialRosterConflict> a,
    List<OfficialRosterConflict> b,
  ) {
    final output = <OfficialRosterConflict>[];
    final seen = <String>{};
    for (final conflict in [...a, ...b]) {
      final key =
          '${conflict.code}|${conflict.date ?? ''}|${conflict.shift ?? ''}';
      if (seen.add(key)) output.add(conflict);
    }
    return output;
  }

  static double _minimum(double a, double b) => a < b ? a : b;
}
