enum ExchangeStatus { pendingB, pendingAdmin, approved, declinedB, rejectedAdmin, cancelled }
enum ShiftRequestType { transfer, exchange }

class ExchangeRequest {
  final String id;
  final ShiftRequestType type;

  final String planningEntryId;
  final String dateStr;
  final String shiftId;

  final String? targetPlanningEntryId;
  final String? targetDateStr;
  final String? targetShiftId;

  final String fromId;
  final String fromPhone;
  final String fromName;
  final String toId;
  final String toPhone;
  final String toName;
  ExchangeStatus status;
  final DateTime createdAt;

  ExchangeRequest({
    required this.id,
    this.type = ShiftRequestType.transfer,
    required this.planningEntryId,
    required this.dateStr,
    required this.shiftId,
    this.targetPlanningEntryId,
    this.targetDateStr,
    this.targetShiftId,
    required this.fromId,
    required this.fromPhone,
    required this.fromName,
    required this.toId,
    required this.toPhone,
    required this.toName,
    this.status = ExchangeStatus.pendingB,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isTransfer => type == ShiftRequestType.transfer;
  bool get isExchange => type == ShiftRequestType.exchange;

  /// Un échange purement SERVICE (Jour / Nuit / 24H des deux côtés)
  /// devient définitif dès que le destinataire l'accepte.
  /// Les transferts et tout échange impliquant les Urgences gardent
  /// la validation administrateur.
  bool get isServiceExchange =>
      isExchange &&
      shiftId.startsWith('service-') &&
      (targetShiftId?.startsWith('service-') ?? false);

  Map<String,dynamic> toJson()=>{
    'id':id,'type':type.name,
    'planningEntryId':planningEntryId,'dateStr':dateStr,'shiftId':shiftId,
    'targetPlanningEntryId':targetPlanningEntryId,'targetDateStr':targetDateStr,'targetShiftId':targetShiftId,
    'fromId':fromId,'fromPhone':fromPhone,'fromName':fromName,
    'toId':toId,'toPhone':toPhone,'toName':toName,
    'status':status.name,'createdAt':createdAt.toIso8601String()
  };

  factory ExchangeRequest.fromJson(Map<String,dynamic> j)=>ExchangeRequest(
    id:j['id'],
    type: ShiftRequestType.values.where((e)=>e.name==j['type']).firstOrNull ?? ShiftRequestType.transfer,
    planningEntryId:j['planningEntryId'],dateStr:j['dateStr'],shiftId:j['shiftId'],
    targetPlanningEntryId:j['targetPlanningEntryId'],targetDateStr:j['targetDateStr'],targetShiftId:j['targetShiftId'],
    fromId:(j['fromId'] as String?) ?? (j['fromPhone'] as String? ?? ''),
    fromPhone:j['fromPhone'],fromName:j['fromName'],
    toId:(j['toId'] as String?) ?? (j['toPhone'] as String? ?? ''),
    toPhone:j['toPhone'],toName:j['toName'],
    status:ExchangeStatus.values.byName(j['status']),createdAt:DateTime.parse(j['createdAt']));
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
