from pathlib import Path

state = Path("lib/state/app_state.dart")
s = state.read_text()

anchor = "  final Set<String> _dismissedNotificationKeys=<String>{};"
if anchor not in s:
    raise SystemExit("V11.6.38 notification set anchor missing")

s = s.replace(
    anchor,
    anchor + "\n"
    "  final Set<String> _dismissedReminderKeys=<String>{};\n"
    "  String _reminderDismissKey(String owner,String date,String shiftId,DateTime fire)=>"
    "'$owner|$date|$shiftId|\${fire.millisecondsSinceEpoch}';",
    1,
)

old_append = """        final fire=first.add(Duration(minutes:_reminderRepeatMinutes*repeat));
        if(!fire.isBefore(start))continue;
        final suffix=repeat==0?reminderDelayLabel(delay):'répétition $repeat';"""
new_append = """        final fire=first.add(Duration(minutes:_reminderRepeatMinutes*repeat));
        if(!fire.isBefore(start))continue;
        if(_dismissedReminderKeys.contains(_reminderDismissKey(owner,date,shiftId,fire)))continue;
        final suffix=repeat==0?reminderDelayLabel(delay):'répétition $repeat';"""
if old_append not in s:
    raise SystemExit("V11.6.38 reminder generation anchor missing")
s = s.replace(old_append, new_append, 1)

old_clear = "  void clearSentReminders(){final me=currentUser;if(me==null)return;_refreshReminderStatuses();_reminders.removeWhere((r)=>r.ownerPhone==me.phone&&r.status==ReminderStatus.sent);_persist();notifyListeners();}"
new_clear = """  void clearSentReminders(){
    final me=currentUser;if(me==null)return;
    _refreshReminderStatuses();
    final sent=_reminders.where((r)=>r.ownerPhone==me.phone&&r.status==ReminderStatus.sent).toList();
    for(final r in sent){
      final e=_planning.where((e)=>e.ownerPhone==me.phone&&e.dateStr==r.dateStr).firstOrNull;
      if(e!=null)_dismissedReminderKeys.add(_reminderDismissKey(me.phone,r.dateStr,e.shiftId,r.fireAt));
    }
    _reminders.removeWhere((r)=>r.ownerPhone==me.phone&&r.status==ReminderStatus.sent);
    _persist();
    notifyListeners();
  }"""
if old_clear not in s:
    raise SystemExit("V11.6.38 clearSentReminders anchor missing")
s = s.replace(old_clear, new_clear, 1)

old_clean = """    _refreshReminderStatuses();
    _reminders.removeWhere((r)=>r.ownerPhone==me.phone&&r.status==ReminderStatus.sent);
    for(final e in _exchanges){"""
new_clean = """    _refreshReminderStatuses();
    final sent=_reminders.where((r)=>r.ownerPhone==me.phone&&r.status==ReminderStatus.sent).toList();
    for(final r in sent){
      final e=_planning.where((e)=>e.ownerPhone==me.phone&&e.dateStr==r.dateStr).firstOrNull;
      if(e!=null)_dismissedReminderKeys.add(_reminderDismissKey(me.phone,r.dateStr,e.shiftId,r.fireAt));
    }
    _reminders.removeWhere((r)=>r.ownerPhone==me.phone&&r.status==ReminderStatus.sent);
    for(final e in _exchanges){"""
if old_clean not in s:
    raise SystemExit("V11.6.38 clearReadAndPastNotifications anchor missing")
s = s.replace(old_clean, new_clean, 1)

old_json = "'dismissedNotifications':_dismissedNotificationKeys.toList(),'delayMinutes'"
new_json = "'dismissedNotifications':_dismissedNotificationKeys.toList(),'dismissedReminders':_dismissedReminderKeys.toList(),'delayMinutes'"
if old_json not in s:
    raise SystemExit("V11.6.38 state persistence anchor missing")
s = s.replace(old_json, new_json, 1)

old_restore = """    try{_dismissedNotificationKeys.addAll((j['dismissedNotifications'] as List? ?? []).map((e)=>e.toString()));}catch(_){}"""
new_restore = """    try{_dismissedNotificationKeys.addAll((j['dismissedNotifications'] as List? ?? []).map((e)=>e.toString()));}catch(_){}
    try{_dismissedReminderKeys.addAll((j['dismissedReminders'] as List? ?? []).map((e)=>e.toString()));}catch(_){}"""
if old_restore not in s:
    raise SystemExit("V11.6.38 state restore anchor missing")
s = s.replace(old_restore, new_restore, 1)

state.write_text(s)
print("V11.6.38 part 4 applied")
