enum ReminderStatus { upcoming, sent }
class ReminderNotification {
  final String id;
  final String ownerPhone;
  final String dateStr;
  final String label;
  final DateTime fireAt;
  ReminderStatus status;
  ReminderNotification({required this.id, required this.ownerPhone, required this.dateStr,
    required this.label, required this.fireAt, this.status = ReminderStatus.upcoming});
  Map<String, dynamic> toJson() => {'id':id,'ownerPhone':ownerPhone,'dateStr':dateStr,
    'label':label,'fireAt':fireAt.toIso8601String(),'status':status.name};
  factory ReminderNotification.fromJson(Map<String,dynamic> j) => ReminderNotification(
    id:j['id'], ownerPhone:j['ownerPhone'], dateStr:j['dateStr'], label:j['label'],
    fireAt:DateTime.parse(j['fireAt']), status:ReminderStatus.values.byName(j['status']));
}
