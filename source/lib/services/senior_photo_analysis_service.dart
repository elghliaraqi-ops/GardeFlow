import 'dart:typed_data';

import '../data/services.dart';
import '../models/shared_resource.dart';
import 'senior_photo_ocr_stub.dart'
    if (dart.library.io) 'senior_photo_ocr_mobile.dart' as ocr;
import 'supabase_backend_service.dart';

class SeniorPhotoAnalysisSummary {
  final int total;
  final int completed;
  final int partial;
  final int failed;
  final int assignments;

  const SeniorPhotoAnalysisSummary({
    required this.total,
    required this.completed,
    required this.partial,
    required this.failed,
    required this.assignments,
  });
}

class SeniorPhotoAnalysisOutcome {
  final String status;
  final int assignments;
  final String? message;

  const SeniorPhotoAnalysisOutcome({
    required this.status,
    required this.assignments,
    this.message,
  });
}

class SeniorPhotoAnalysisService {
  SeniorPhotoAnalysisService._();

  static final SeniorPhotoAnalysisService instance =
      SeniorPhotoAnalysisService._();

  final SupabaseBackendService _backend = SupabaseBackendService.instance;

  bool get supported => ocr.seniorPhotoOcrSupported;

  Future<SeniorPhotoAnalysisSummary> processPendingPhotos({
    void Function(int done, int total)? onProgress,
  }) async {
    if (!supported) {
      return const SeniorPhotoAnalysisSummary(
        total: 0,
        completed: 0,
        partial: 0,
        failed: 0,
        assignments: 0,
      );
    }

    final photos = await _backend.fetchPendingAstreintePhotos();
    var completed = 0;
    var partial = 0;
    var failed = 0;
    var assignments = 0;

    for (var i = 0; i < photos.length; i++) {
      final outcome = await analyzeResource(photos[i]);
      assignments += outcome.assignments;
      switch (outcome.status) {
        case 'completed':
          completed++;
          break;
        case 'partial':
          partial++;
          break;
        default:
          failed++;
      }
      onProgress?.call(i + 1, photos.length);
    }

    return SeniorPhotoAnalysisSummary(
      total: photos.length,
      completed: completed,
      partial: partial,
      failed: failed,
      assignments: assignments,
    );
  }

  Future<SeniorPhotoAnalysisOutcome> analyzeResource(
    SharedResource resource,
  ) async {
    if (!supported) {
      return const SeniorPhotoAnalysisOutcome(
        status: 'error',
        assignments: 0,
        message: 'OCR mobile indisponible sur cette plateforme.',
      );
    }

    await _backend.markAstreintePhotoAnalysis(
      resourceId: resource.id,
      status: 'processing',
      message: null,
    );

    try {
      final Uint8List bytes =
          await _backend.downloadSharedResource(resource.storagePath);
      final lines = await ocr.recognizeSeniorPhoto(
        bytes,
        fileName: resource.displayName,
      );
      final parsed = _parse(resource, lines);

      final hasAssignments = parsed.assignments.isNotEmpty;
      final incompletePhone =
          parsed.assignments.any((row) => (row['phone'] as String?)?.isEmpty ?? true);
      final unclassified = parsed.service == 'À classer';

      final status = !hasAssignments
          ? 'partial'
          : (incompletePhone || unclassified ? 'partial' : 'completed');

      final message = !hasAssignments
          ? 'Texte reconnu, mais aucune ligne date + médecin n’a été identifiée.'
          : [
              '${parsed.assignments.length} astreinte(s) détectée(s)',
              if (unclassified) 'service à classer',
              if (incompletePhone) 'certains numéros sont absents',
            ].join(' · ');

      final inserted = await _backend.replaceSeniorOnCallPhotoAnalysis(
        resource: resource,
        assignments: parsed.assignments,
        inferredService:
            parsed.service == 'À classer' ? null : parsed.service,
        status: status,
        message: message,
      );

      return SeniorPhotoAnalysisOutcome(
        status: status,
        assignments: inserted,
        message: message,
      );
    } catch (e) {
      final message = 'Analyse impossible : $e';
      await _backend.markAstreintePhotoAnalysis(
        resourceId: resource.id,
        status: 'error',
        message: message,
      );
      return SeniorPhotoAnalysisOutcome(
        status: 'error',
        assignments: 0,
        message: message,
      );
    }
  }

  _ParsedSeniorPhoto _parse(
    SharedResource resource,
    List<Map<String, dynamic>> rawLines,
  ) {
    final rows = _groupRows(rawLines);
    final allText = rows.map((row) => row.text).join('\n');
    final service = _inferService(resource.service, allText);

    final context = _documentDateContext(
      allText,
      fallback: resource.createdAt,
    );

    final assignments = <Map<String, dynamic>>[];
    DateTime? currentDate;
    Map<String, dynamic>? lastAssignment;

    for (final row in rows) {
      final explicitDate = _extractDate(
        row.text,
        month: context.month,
        year: context.year,
      );
      if (explicitDate != null) {
        currentDate = explicitDate;
      }

      final phones = _extractPhones(row.text);
      final name = _extractDoctorName(row.text, service: service);

      if (name != null && currentDate != null) {
        final phone = phones.isNotEmpty ? phones.first : '';
        final confidence = _confidenceFor(
          text: row.text,
          explicitDate: explicitDate != null,
          hasPhone: phone.isNotEmpty,
          hasTitle: _hasDoctorTitle(row.text),
        );
        final item = <String, dynamic>{
          'date': _dateKey(currentDate),
          'name': name,
          'phone': phone,
          'confidence': confidence,
        };

        final duplicate = assignments.any(
          (existing) =>
              existing['date'] == item['date'] &&
              _normalize(existing['name'].toString()) ==
                  _normalize(item['name'].toString()),
        );
        if (!duplicate) {
          assignments.add(item);
          lastAssignment = item;
        }
        continue;
      }

      if (phones.isNotEmpty &&
          lastAssignment != null &&
          (lastAssignment['phone'] as String?)?.isEmpty == true) {
        lastAssignment['phone'] = phones.first;
      }
    }

    return _ParsedSeniorPhoto(
      service: service,
      assignments: assignments,
    );
  }

  List<_OcrRow> _groupRows(List<Map<String, dynamic>> lines) {
    final normalized = lines
        .map((raw) => _OcrLine(
              text: (raw['text'] as String?)?.trim() ?? '',
              left: (raw['left'] as num?)?.toDouble() ?? 0,
              top: (raw['top'] as num?)?.toDouble() ?? 0,
              right: (raw['right'] as num?)?.toDouble() ?? 0,
              bottom: (raw['bottom'] as num?)?.toDouble() ?? 0,
            ))
        .where((line) => line.text.isNotEmpty)
        .toList()
      ..sort((a, b) {
        final d = a.centerY.compareTo(b.centerY);
        if (d != 0 && (a.centerY - b.centerY).abs() > 10) return d;
        return a.left.compareTo(b.left);
      });

    final result = <_OcrRow>[];
    for (final line in normalized) {
      _OcrRow? target;
      for (var i = result.length - 1; i >= 0 && i >= result.length - 4; i--) {
        final candidate = result[i];
        final tolerance = (candidate.averageHeight + line.height) * 0.42;
        if ((candidate.centerY - line.centerY).abs() <=
            tolerance.clamp(8, 24)) {
          target = candidate;
          break;
        }
      }

      if (target == null) {
        result.add(_OcrRow(<_OcrLine>[line]));
      } else {
        target.lines.add(line);
        target.lines.sort((a, b) => a.left.compareTo(b.left));
      }
    }

    result.sort((a, b) => a.centerY.compareTo(b.centerY));
    return result;
  }

  _DateContext _documentDateContext(
    String text, {
    required DateTime fallback,
  }) {
    final normalized = _normalize(text);
    var month = fallback.month;
    var year = fallback.year;

    final yearMatch = RegExp(r'\b(20\d{2})\b').firstMatch(normalized);
    if (yearMatch != null) {
      year = int.tryParse(yearMatch.group(1)!) ?? year;
    }

    const months = <String, int>{
      'janvier': 1,
      'fevrier': 2,
      'mars': 3,
      'avril': 4,
      'mai': 5,
      'juin': 6,
      'juillet': 7,
      'aout': 8,
      'septembre': 9,
      'octobre': 10,
      'novembre': 11,
      'decembre': 12,
    };
    for (final entry in months.entries) {
      if (normalized.contains(entry.key)) {
        month = entry.value;
        break;
      }
    }

    return _DateContext(month: month, year: year);
  }

  DateTime? _extractDate(
    String text, {
    required int month,
    required int year,
  }) {
    final slash = RegExp(
      r'\b([0-3]?\d)[\/\.\-]([01]?\d)(?:[\/\.\-](20\d{2}|\d{2}))?\b',
    ).firstMatch(text);
    if (slash != null) {
      final day = int.tryParse(slash.group(1)!);
      final parsedMonth = int.tryParse(slash.group(2)!);
      var parsedYear = year;
      final rawYear = slash.group(3);
      if (rawYear != null) {
        final value = int.tryParse(rawYear);
        if (value != null) {
          parsedYear = value < 100 ? 2000 + value : value;
        }
      }
      return _safeDate(parsedYear, parsedMonth, day);
    }

    final normalized = _normalize(text);
    final weekday = RegExp(
      r'\b(?:lun(?:di)?|mar(?:di)?|mer(?:credi)?|jeu(?:di)?|ven(?:dredi)?|sam(?:edi)?|dim(?:anche)?)\s*([0-3]?\d)\b',
    ).firstMatch(normalized);
    if (weekday != null) {
      return _safeDate(
        year,
        month,
        int.tryParse(weekday.group(1)!),
      );
    }

    final leading = RegExp(r'^\s*([0-3]?\d)\s+(?=[A-Za-zÀ-ÿ])')
        .firstMatch(text);
    if (leading != null) {
      final day = int.tryParse(leading.group(1)!);
      if (day != null && day >= 1 && day <= 31) {
        return _safeDate(year, month, day);
      }
    }

    return null;
  }

  DateTime? _safeDate(int year, int? month, int? day) {
    if (month == null ||
        day == null ||
        month < 1 ||
        month > 12 ||
        day < 1 ||
        day > 31) {
      return null;
    }
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }

  List<String> _extractPhones(String text) {
    final compact = text.replaceAll(RegExp(r'[\s.()\-]'), '');
    final matches = RegExp(r'(?:\+212|00212|212|0)[5-7]\d{8}')
        .allMatches(compact);
    final values = <String>[];
    for (final match in matches) {
      var value = match.group(0) ?? '';
      if (value.startsWith('00212')) {
        value = '+212${value.substring(5)}';
      } else if (value.startsWith('212')) {
        value = '+$value';
      } else if (value.startsWith('0') && value.length == 10) {
        value = '+212${value.substring(1)}';
      }
      if (value.isNotEmpty && !values.contains(value)) {
        values.add(value);
      }
    }
    return values;
  }

  String? _extractDoctorName(
    String text, {
    required String service,
  }) {
    var cleaned = text;

    cleaned = cleaned.replaceAll(
      RegExp(r'(?:\+212|00212|212|0)[\s.()\-]*[5-7](?:[\s.()\-]*\d){8}'),
      ' ',
    );
    cleaned = cleaned.replaceAll(
      RegExp(r'\b[0-3]?\d[\/\.\-][01]?\d(?:[\/\.\-](?:20)?\d{2})?\b'),
      ' ',
    );
    cleaned = cleaned.replaceAll(
      RegExp(
        r'\b(?:lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche|lun|mar|mer|jeu|ven|sam|dim)\b',
        caseSensitive: false,
      ),
      ' ',
    );
    cleaned = cleaned.replaceAll(RegExp(r'^\s*[0-3]?\d\s+'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();

    final titled = RegExp(
      r'\b(pr(?:of(?:esseur)?)?|dr|docteur)\.?\s*[:\-]?\s*(.+)',
      caseSensitive: false,
    ).firstMatch(cleaned);

    String? title;
    String candidate;
    if (titled != null) {
      title = titled.group(1);
      candidate = titled.group(2) ?? '';
    } else {
      candidate = cleaned;
    }

    candidate = candidate
        .split(RegExp(r'[|;,]'))
        .first
        .replaceAll(RegExp(r'\b(?:astreinte|garde|senior|service|tel|telephone|portable|jour|nuit|24h)\b',
            caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (candidate.isEmpty) return null;

    final normalizedCandidate = _normalize(candidate);
    final normalizedService = _normalize(service);
    if (normalizedCandidate == normalizedService ||
        normalizedCandidate.contains('hopital') ||
        normalizedCandidate.contains('programme') ||
        normalizedCandidate.contains('planning') ||
        normalizedCandidate.contains('astreinte')) {
      return null;
    }

    final words = candidate
        .split(RegExp(r'\s+'))
        .where((word) => RegExp(r'[A-Za-zÀ-ÿ]').hasMatch(word))
        .toList();

    if (title == null) {
      if (words.length < 2 || words.length > 5) return null;
      final letters = candidate.replaceAll(RegExp(r'[^A-Za-zÀ-ÿ]'), '');
      if (letters.length < 5) return null;

      final hasLikelyNameCase = words.any((word) {
        if (word.length < 2) return false;
        final first = word.substring(0, 1);
        return first == first.toUpperCase();
      });
      if (!hasLikelyNameCase) return null;
    } else if (words.isEmpty || words.length > 6) {
      return null;
    }

    final titleLabel = title == null
        ? ''
        : _normalize(title).startsWith('pr')
            ? 'Pr '
            : 'Dr ';
    return '$titleLabel$candidate'.trim();
  }

  bool _hasDoctorTitle(String text) => RegExp(
        r'\b(?:pr(?:of(?:esseur)?)?|dr|docteur)\b',
        caseSensitive: false,
      ).hasMatch(text);

  double _confidenceFor({
    required String text,
    required bool explicitDate,
    required bool hasPhone,
    required bool hasTitle,
  }) {
    var score = 0.62;
    if (explicitDate) score += 0.13;
    if (hasTitle) score += 0.12;
    if (hasPhone) score += 0.10;
    if (text.length > 8) score += 0.03;
    return score.clamp(0.0, 0.99);
  }

  String _inferService(String? current, String fullText) {
    final existing = current?.trim();
    if (existing != null &&
        existing.isNotEmpty &&
        _normalize(existing) != _normalize('À classer')) {
      return existing;
    }

    final normalizedText = _normalize(fullText);
    final exact = kServices.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final service in exact) {
      final normalizedService = _normalize(service);
      if (normalizedService.length >= 5 &&
          normalizedText.contains(normalizedService)) {
        return service;
      }
    }

    const aliases = <String, String>{
      'chir visc': 'Chirurgie viscérale et digestive',
      'viscerale': 'Chirurgie viscérale et digestive',
      'digestive': 'Chirurgie viscérale et digestive',
      'traumatologie': 'Orthopédie – Traumatologie',
      'orthopedie': 'Orthopédie – Traumatologie',
      'gynecologie': 'Gynécologie – Obstétrique',
      'obstetrique': 'Gynécologie – Obstétrique',
      'radiologie': 'Imagerie médicale',
      'imagerie': 'Imagerie médicale',
      'anesthesie': 'Anesthésie',
      'reanimation': 'Réanimation Adulte / Polyvalente',
      'urologie': 'Urologie',
      'cardiologie': 'Cardiologie',
      'neurochirurgie': 'Neurochirurgie',
      'neurologie': 'Neurologie',
      'pneumologie': 'Pneumologie',
      'nephrologie': 'Néphrologie',
      'oncologie': 'Oncologie médicale',
      'hematologie': 'Hématologie',
      'dermatologie': 'Dermatologie',
      'ophtalmologie': 'Ophtalmologie',
      'psychiatrie': 'Psychiatrie',
      'rhumatologie': 'Rhumatologie',
      'maxillo': 'Chirurgie maxillo-faciale',
      'orl': 'ORL (Oto-Rhino-Laryngologie)',
      'pediatrie': 'Pédiatrie',
      'urgences': 'Urgences',
    };
    for (final entry in aliases.entries) {
      if (normalizedText.contains(entry.key)) {
        return entry.value;
      }
    }
    return 'À classer';
  }

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[àáâäãå]'), 'a')
      .replaceAll(RegExp(r'[ç]'), 'c')
      .replaceAll(RegExp(r'[èéêë]'), 'e')
      .replaceAll(RegExp(r'[ìíîï]'), 'i')
      .replaceAll(RegExp(r'[òóôöõ]'), 'o')
      .replaceAll(RegExp(r'[ùúûü]'), 'u')
      .replaceAll(RegExp(r'[ÿ]'), 'y')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();

  String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

class _ParsedSeniorPhoto {
  final String service;
  final List<Map<String, dynamic>> assignments;

  const _ParsedSeniorPhoto({
    required this.service,
    required this.assignments,
  });
}

class _DateContext {
  final int month;
  final int year;

  const _DateContext({
    required this.month,
    required this.year,
  });
}

class _OcrLine {
  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;

  const _OcrLine({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  double get height => (bottom - top).abs().clamp(1, double.infinity);
  double get centerY => (top + bottom) / 2;
}

class _OcrRow {
  final List<_OcrLine> lines;

  _OcrRow(this.lines);

  String get text => lines.map((line) => line.text).join(' ').trim();

  double get centerY {
    if (lines.isEmpty) return 0;
    return lines.map((line) => line.centerY).reduce((a, b) => a + b) /
        lines.length;
  }

  double get averageHeight {
    if (lines.isEmpty) return 10;
    return lines.map((line) => line.height).reduce((a, b) => a + b) /
        lines.length;
  }
}
