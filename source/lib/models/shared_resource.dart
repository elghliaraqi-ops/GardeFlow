class SharedResource {
  final String id;
  final String kind;
  final String? slot;
  final String? service;
  final String storagePath;
  final String displayName;
  final String mimeType;
  final String? analysisStatus;
  final String? analysisMessage;
  final DateTime? analyzedAt;
  final String? analysisVersion;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SharedResource({
    required this.id,
    required this.kind,
    required this.slot,
    required this.service,
    required this.storagePath,
    required this.displayName,
    required this.mimeType,
    required this.analysisStatus,
    required this.analysisMessage,
    required this.analyzedAt,
    required this.analysisVersion,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SharedResource.fromJson(Map<String, dynamic> json) => SharedResource(
        id: json['id'].toString(),
        kind: json['kind'] as String,
        slot: json['slot'] as String?,
        service: json['service'] as String?,
        storagePath: json['storage_path'] as String,
        displayName: (json['display_name'] as String?) ?? '',
        mimeType: (json['mime_type'] as String?) ?? 'application/octet-stream',
        analysisStatus: json['analysis_status'] as String?,
        analysisMessage: json['analysis_message'] as String?,
        analyzedAt: json['analyzed_at'] == null
            ? null
            : DateTime.parse(json['analyzed_at'] as String),
        analysisVersion: json['analysis_version'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse((json['updated_at'] as String?) ?? json['created_at'] as String),
      );
}
