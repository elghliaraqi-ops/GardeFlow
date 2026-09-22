class SharedResource {
  final String id;
  final String kind;
  final String? slot;
  final String? service;
  final String storagePath;
  final String displayName;
  final String mimeType;
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
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse((json['updated_at'] as String?) ?? json['created_at'] as String),
      );
}
