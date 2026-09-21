class PlanningEntry {
  final String id;
  String dateStr;
  String shiftId;
  String ownerId;
  String ownerPhone;
  String ownerName;
  String? leaveRequestId;
  bool isDisciplinary;
  final DateTime createdAt;

  PlanningEntry({
    required this.id,
    required this.dateStr,
    required this.shiftId,
    required this.ownerId,
    required this.ownerPhone,
    required this.ownerName,
    this.leaveRequestId,
    this.isDisciplinary = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'dateStr': dateStr,
        'shiftId': shiftId,
        'ownerId': ownerId,
        'ownerPhone': ownerPhone,
        'ownerName': ownerName,
        'leaveRequestId': leaveRequestId,
        'isDisciplinary': isDisciplinary,
        'createdAt': createdAt.toIso8601String(),
      };

  factory PlanningEntry.fromJson(Map<String, dynamic> j) => PlanningEntry(
        id: j['id'] as String,
        dateStr: j['dateStr'] as String,
        shiftId: j['shiftId'] as String,
        ownerId: (j['ownerId'] as String?) ?? (j['ownerPhone'] as String? ?? ''),
        ownerPhone: j['ownerPhone'] as String,
        ownerName: j['ownerName'] as String,
        leaveRequestId: j['leaveRequestId'] as String?,
        isDisciplinary: j['isDisciplinary'] as bool? ?? false,
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
}
