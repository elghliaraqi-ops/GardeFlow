import '../services/supabase_backend_service.dart';

/// Private, owner-scoped saved radiology report drafts. The server applies
/// Row Level Security as the authoritative authorization boundary.
class RadiologyReportArchiveService {
  RadiologyReportArchiveService._();
  static final RadiologyReportArchiveService instance =
      RadiologyReportArchiveService._();

  final SupabaseBackendService _backend = SupabaseBackendService.instance;

  String _userId() {
    if (!_backend.enabled) throw StateError('Service non configuré.');
    final uid = _backend.client.auth.currentUser?.id;
    if (uid == null) throw StateError('Connexion requise pour accéder aux CR.');
    return uid;
  }

  /// Saves one generated report or an edited version of the same report.
  /// Previous comparisons, QCM answers and patient identifiers are excluded.
  Future<String> save({
    String? id,
    required String examType,
    required String region,
    required String indication,
    required DateTime? examDate,
    required String reportText,
  }) async {
    final uid = _userId();
    if (examType.trim().isEmpty || region.trim().isEmpty ||
        indication.trim().isEmpty || reportText.trim().isEmpty) {
      throw StateError('Examen, région, indication et CR obligatoires.');
    }
    final payload = <String, dynamic>{
      'exam_type': examType.trim(),
      'region': region.trim(),
      'indication': indication.trim(),
      'exam_date': examDate == null
          ? null
          : '${examDate.year.toString().padLeft(4, '0')}-'
              '${examDate.month.toString().padLeft(2, '0')}-'
              '${examDate.day.toString().padLeft(2, '0')}',
      'report_text': reportText,
    };
    if (id == null) {
      final result = await _backend.client
          .from('radiology_reports')
          .insert({'owner_id': uid, ...payload})
          .select('id')
          .single();
      return result['id'] as String;
    }
    final result = await _backend.client
        .from('radiology_reports')
        .update(payload)
        .eq('owner_id', uid)
        .eq('id', id)
        .select('id')
        .maybeSingle();
    if (result == null) {
      throw StateError('CR introuvable ou accès non autorisé.');
    }
    return result['id'] as String;
  }

  /// Search is performed by PostgREST against the database, not only locally
  /// against a few recent records. A page is bounded to keep mobile use fast.
  Future<List<Map<String, dynamic>>> search({
    String? examType,
    String? indicationContains,
    DateTime? startDate,
    DateTime? endDate,
    bool byExamDate = false,
    int offset = 0,
    int pageSize = 40,
  }) async {
    final uid = _userId();
    var query = _backend.client
        .from('radiology_reports')
        .select('id, exam_type, region, indication, exam_date, report_text, '
            'created_at, updated_at')
        .eq('owner_id', uid);
    if (examType != null && examType.isNotEmpty) {
      query = query.eq('exam_type', examType);
    }
    final term = indicationContains?.trim() ?? '';
    if (term.isNotEmpty) {
      // Escape LIKE wildcards: user input is a literal substring, not a pattern.
      final escaped = term.replaceAll('\\', '\\\\')
          .replaceAll('%', '\\%').replaceAll('_', '\\_');
      query = query.ilike('indication', '%$escaped%');
    }
    final dateColumn = byExamDate ? 'exam_date' : 'created_at';
    if (startDate != null) {
      final date = DateTime(startDate.year, startDate.month, startDate.day);
      query = query.gte(dateColumn, byExamDate
          ? _dateOnly(date) : date.toUtc().toIso8601String());
    }
    if (endDate != null) {
      final next = DateTime(endDate.year, endDate.month, endDate.day + 1);
      if (byExamDate) {
        query = query.lte(dateColumn, _dateOnly(endDate));
      } else {
        query = query.lt(dateColumn, next.toUtc().toIso8601String());
      }
    }
    final rows = await query
        .order('created_at', ascending: false)
        .range(offset, offset + pageSize - 1);
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
