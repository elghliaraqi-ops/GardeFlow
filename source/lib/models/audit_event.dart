class AuditEvent {
  final int id;
  final String action;
  final String entityType;
  final String entityId;
  final String actorName;
  final String? subjectName;
  final String? reason;
  final DateTime createdAt;

  const AuditEvent({
    required this.id,
    required this.action,
    required this.entityType,
    required this.entityId,
    required this.actorName,
    required this.createdAt,
    this.subjectName,
    this.reason,
  });
}
