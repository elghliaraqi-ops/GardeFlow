enum LeaveRequestStatus { pendingAdmin, approved, rejectedAdmin, cancelled }

class LeaveRequest {
  final String id;
  final String startDateStr;
  final String endDateStr;
  final String ownerId;
  final String ownerPhone;
  final String ownerName;
  LeaveRequestStatus status;
  final DateTime createdAt;
  DateTime? reviewedAt;

  LeaveRequest({
    required this.id,
    required this.startDateStr,
    required this.endDateStr,
    required this.ownerId,
    required this.ownerPhone,
    required this.ownerName,
    this.status = LeaveRequestStatus.pendingAdmin,
    DateTime? createdAt,
    this.reviewedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  // Compatibilité avec les écrans et anciennes sauvegardes mono-date.
  String get dateStr => startDateStr;
  bool get isSingleDay => startDateStr == endDateStr;

  bool includesDate(String dateStr) =>
      dateStr.compareTo(startDateStr) >= 0 && dateStr.compareTo(endDateStr) <= 0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'startDateStr': startDateStr,
        'endDateStr': endDateStr,
        'ownerId': ownerId,
        'ownerPhone': ownerPhone,
        'ownerName': ownerName,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'reviewedAt': reviewedAt?.toIso8601String(),
      };

  factory LeaveRequest.fromJson(Map<String, dynamic> j) {
    final legacyDate = j['dateStr'] as String?;
    return LeaveRequest(
      id: j['id'] as String,
      startDateStr: (j['startDateStr'] as String?) ?? legacyDate ?? '',
      endDateStr: (j['endDateStr'] as String?) ?? legacyDate ?? '',
      ownerId: (j['ownerId'] as String?) ?? (j['ownerPhone'] as String? ?? ''),
      ownerPhone: j['ownerPhone'] as String,
      ownerName: j['ownerName'] as String,
      status: LeaveRequestStatus.values.byName((j['status'] as String?) ?? 'pendingAdmin'),
      createdAt: DateTime.parse(j['createdAt'] as String),
      reviewedAt: j['reviewedAt'] == null ? null : DateTime.parse(j['reviewedAt'] as String),
    );
  }
}
