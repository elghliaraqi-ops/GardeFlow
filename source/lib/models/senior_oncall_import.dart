class SeniorOnCallImport {
  final String id;
  final String resourceId;
  final String hospital;
  final String status;
  final String detectedService;
  final int? detectedMonth;
  final int? detectedYear;
  final double confidence;
  final String analysisEngine;
  final List<Map<String, dynamic>> draftRows;
  final List<String> warnings;
  final DateTime updatedAt;

  const SeniorOnCallImport({
    required this.id,
    required this.resourceId,
    required this.hospital,
    required this.status,
    required this.detectedService,
    required this.detectedMonth,
    required this.detectedYear,
    required this.confidence,
    required this.analysisEngine,
    required this.draftRows,
    required this.warnings,
    required this.updatedAt,
  });

  factory SeniorOnCallImport.fromJson(Map<String, dynamic> json) {
    final rawRows = json['draft_rows'];
    final rawWarnings = json['warnings'];
    return SeniorOnCallImport(
      id: json['id'].toString(),
      resourceId: json['resource_id'].toString(),
      hospital: (json['hospital'] as String?) ?? '',
      status: (json['status'] as String?) ?? 'draft',
      detectedService: (json['detected_service'] as String?) ?? '',
      detectedMonth: (json['detected_month'] as num?)?.toInt(),
      detectedYear: (json['detected_year'] as num?)?.toInt(),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      analysisEngine: (json['analysis_engine'] as String?) ?? '',
      draftRows: rawRows is List
          ? rawRows
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList(growable: false)
          : const <Map<String, dynamic>>[],
      warnings: rawWarnings is List
          ? rawWarnings.map((e) => e.toString()).toList(growable: false)
          : const <String>[],
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}
