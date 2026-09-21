import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';

import '../config/business_rules.dart';
import '../data/seed_data.dart';
import '../data/hospitals.dart';
import '../models/app_user.dart';
import '../models/directory_contact.dart';
import '../models/exchange_request.dart';
import '../models/leave_request.dart';
import '../models/planning_entry.dart';
import '../models/planning_month.dart';
import '../models/password_reset_request.dart';
import '../models/reminder_notification.dart';
import '../models/shift_type.dart';
import '../services/local_storage_service.dart';
import '../services/notification_service.dart';
import '../services/official_roster_import_service.dart';
import '../services/password_service.dart';
import '../services/push_notification_service.dart';
import '../services/supabase_backend_service.dart';

class AstreintePhoto {
  final String id;
  final String ownerPhone;
  final Uint8List bytes;
  final String name;
  final DateTime createdAt;
  AstreintePhoto({required this.id, required this.ownerPhone, required this.bytes,
    required this.name, DateTime? createdAt}) : createdAt = createdAt ?? DateTime.now();
  Map<String,dynamic> toJson()=>{'id':id,'ownerPhone':ownerPhone,'bytes':base64Encode(bytes),
    'name':name,'createdAt':createdAt.toIso8601String()};
  factory AstreintePhoto.fromJson(Map<String,dynamic> j)=>AstreintePhoto(
    id:j['id'],ownerPhone:j['ownerPhone'],bytes:base64Decode(j['bytes']),name:j['name'],
    createdAt:DateTime.parse(j['createdAt']));
}

/// État global persistant de l'application.
/// La V5 sauvegarde localement comptes, planning, rappels, échanges, réglages
/// et photos sur Web/Android/iOS/desktop via SharedPreferences.
class AppState extends ChangeNotifier {
  AppState._();

  StreamSubscription? _planningRealtime;
  StreamSubscription? _planningMonthRealtime;
  StreamSubscription? _exchangeRealtime;
  StreamSubscription? _leaveRealtime;
  StreamSubscription? _profileRealtime;
  StreamSubscription? _directoryRealtime;
  StreamSubscription? _passwordResetRealtime;
  Timer? _realtimeReloadTimer;
  bool _realtimeNeedsOfficialSync = false;
  int _sessionEpoch = 0;

  static Future<AppState> load() async {
    final state = AppState._();
    final saved = await LocalStorageService.loadState();
    if (saved == null) {
      state._users.add(buildSeedAdmin());
      state._rebuildDirectory();
      await state._persistNow();
    } else {
      state._restore(saved);
      if (!state._users.any((u) => u.role == UserRole.admin)) {
        state._users.add(buildSeedAdmin());
      }
      state._rebuildDirectory();
    }
    final backend = SupabaseBackendService.instance;
    if (backend.enabled && backend.client.auth.currentUser != null) {
      try {
        final profile=await backend.fetchMyProfile();
        if(profile.accountStatus!=AccountStatus.active){
          await backend.signOut();
          state.currentUser=null;
          await LocalStorageService.savePushActiveUserId(null);
          await LocalStorageService.savePushEnabled(false);
        }else{
          state._sessionEpoch++;
          state.currentUser=profile;
          await LocalStorageService.savePushActiveUserId(profile.id);
          state._applyReminderPrefsForCurrentUser();
          await state._reloadFromBackend();
          await state._syncMyOfficialRosterIfNeeded();
          state._startRealtime();
        }
      } catch (_) {
        state.currentUser = null;
        await LocalStorageService.savePushActiveUserId(null);
        await LocalStorageService.savePushEnabled(false);
      }
    } else {
      final sessionPhone = await LocalStorageService.loadSessionPhone();
      if (sessionPhone != null) {
        state.currentUser = state._users.where((u) => u.phone == sessionPhone).firstOrNull;
        if (state.currentUser != null) state._sessionEpoch++;
        state._applyReminderPrefsForCurrentUser();
      }
    }
    state._applyReminderPrefsForCurrentUser();
    state._refreshReminderStatuses();
    await state._activateNativeRemindersForCurrentUser();
    if (state.currentUser != null && state.backendEnabled && state._notificationsOn) {
      unawaited(PushNotificationService.instance.activateForSignedInUser());
    }
    return state;
  }

  String _appearanceTheme = 'green';

  String get appearanceTheme => _appearanceTheme;

  // Compatibility for screens/helpers that still only need to know whether
  // light or dark foregrounds are required. Green, red and black are dark.
  bool get darkMode => _appearanceTheme != 'white';

  Future<void> setAppearanceTheme(String value) async {
    const allowed = <String>{'green', 'red', 'white', 'black'};
    final next = allowed.contains(value) ? value : 'green';
    if (_appearanceTheme == next) return;
    _appearanceTheme = next;
    await _persistNow();
    notifyListeners();
  }

  // Legacy API kept temporarily so old call sites cannot break.
  Future<void> setDarkMode(bool enabled) =>
      setAppearanceTheme(enabled ? 'black' : 'white');

  bool get backendEnabled => SupabaseBackendService.instance.enabled;
  String get backendModeLabel => backendEnabled ? 'Supabase connecté' : 'Mode local';

  void _firePush(String kind, String resourceId) {
    if (!backendEnabled) return;
    unawaited(
      SupabaseBackendService.instance
          .triggerPush(kind, resourceId)
          .catchError((Object e) { debugPrint('Envoi push impossible: $e'); }),
    );
  }

  String? _officialPlanningSlotForHospital(String hospital) {
    if (hospital == kHospitalBouskoura) return 'hm6_bouskoura';
    if (hospital == kHospitalRabat) return 'hm6_rabat';
    if (hospital == kHospitalCasa) return 'hck_casa';
    return null;
  }

  /// V11.6.5 : synchronise un profil actif avec le dernier PDF Urgences de
  /// son établissement, y compris si le compte a été créé après l'upload du PDF.
  ///
  /// Le parsing utilise tous les profils visibles du même établissement : cela
  /// évite de prendre les noms des autres médecins pour des cellules illisibles
  /// et permet de retirer proprement une ancienne garde disparue d'un PDF remplacé.
  Future<bool> _syncOfficialRosterForProfile(AppUser profile) async {
    if (!backendEnabled || profile.accountStatus != AccountStatus.active) return false;
    final slot = _officialPlanningSlotForHospital(profile.hospital);
    if (slot == null) return false;

    final backend = SupabaseBackendService.instance;
    final resources = await backend.fetchOfficialPlanningPdfs();
    final resource = resources.where((r) => r.slot == slot).firstOrNull;
    if (resource == null) return false;

    final alreadyCurrent = await backend.officialRosterProfileSyncIsCurrent(
      resource: resource,
      profileId: profile.id,
    );
    if (alreadyCurrent) return false;

    final visibleProfiles = _users.isEmpty
        ? await backend.fetchVisibleProfiles()
        : List<AppUser>.from(_users);
    if (!visibleProfiles.any((u) => u.id == profile.id)) {
      visibleProfiles.add(profile);
    }

    final bytes = await backend.downloadSharedResource(resource.storagePath);
    final parsed = await OfficialRosterImportService.parse(
      bytes: bytes,
      displayName: resource.displayName,
      hospital: profile.hospital,
      profiles: visibleProfiles,
      resourceUpdatedAt: resource.updatedAt,
    );
    if (parsed.detectedRows == 0) {
      throw StateError(
        'Le planning officiel ${resource.displayName} ne contient aucune ligne Urgences reconnue.',
      );
    }

    final myAssignments = parsed.assignments
        .where((a) => a.profileId == profile.id)
        .map((a) => a.toJson())
        .toList(growable: false);
    if (myAssignments.isEmpty) {
      throw StateError(
        'Le PDF ${resource.displayName} est lisible mais le nom de ${profile.prenom} ${profile.nom} n’y a pas été reconnu. La synchronisation sera retentée automatiquement.',
      );
    }

    final result = await backend.importOfficialEmergencyRosterForProfile(
      resource: resource,
      profileId: profile.id,
      assignments: myAssignments,
      unmatchedCells: parsed.unmatchedCells,
    );

    await backend.applyCurrentDisciplinaryRulesForMe();

    final inserted = (result['inserted'] as num?)?.toInt() ?? 0;
    final updated = (result['updated'] as num?)?.toInt() ?? 0;
    final removed = (result['removed'] as num?)?.toInt() ?? 0;
    return inserted + updated + removed > 0;
  }

  Future<void> forceSyncMyOfficialRoster() async {
    final me = currentUser;
    if (!backendEnabled || me == null || me.accountStatus != AccountStatus.active) {
      return;
    }

    final slot = _officialPlanningSlotForHospital(me.hospital);
    if (slot == null) {
      throw StateError('Aucun planning officiel configuré pour votre établissement.');
    }

    final backend = SupabaseBackendService.instance;
    final resources = await backend.fetchOfficialPlanningPdfs();
    final resource = resources.where((r) => r.slot == slot).firstOrNull;
    if (resource == null) {
      throw StateError('Aucun PDF officiel publié pour votre établissement.');
    }

    await backend.resetMyOfficialRosterProfileSync(resource: resource);
    await _syncOfficialRosterForProfile(me);
    await backend.applyCurrentDisciplinaryRulesForMe();
    await _reloadFromBackend();
  }

  Future<void> _syncMyOfficialRosterIfNeeded() async {
    final me = currentUser;
    if (!backendEnabled || me == null || me.accountStatus != AccountStatus.active) return;
    try {
      final changed = await _syncOfficialRosterForProfile(me);
      final disciplinary = await SupabaseBackendService.instance.applyCurrentDisciplinaryRulesForMe();
      final disciplinaryChanged =
          ((disciplinary['inserted'] as num?)?.toInt() ?? 0) > 0 ||
          ((disciplinary['updated'] as num?)?.toInt() ?? 0) > 0;
      if (changed || disciplinaryChanged) await _reloadFromBackend();
    } catch (e) {
      // Le planning officiel ne doit jamais empêcher l'utilisateur de se connecter.
      // Une prochaine connexion/actualisation retentera la synchronisation.
      debugPrint('Synchronisation automatique du planning officiel impossible: $e');
    }
  }

  Future<void> _reloadAndSyncMyOfficialRoster() async {
    await _reloadFromBackend();
    await _syncMyOfficialRosterIfNeeded();
  }

  Future<void> _reloadFromBackend() async {
    final sessionUser = currentUser;
    if (!backendEnabled || sessionUser == null) return;
    final expectedEpoch = _sessionEpoch;
    final expectedUserId = sessionUser.id;
    final backend = SupabaseBackendService.instance;

    // Start independent requests together instead of serializing the whole home refresh.
    final profilesFuture = backend.fetchVisibleProfiles();
    final planningFuture = backend.fetchPlanning();
    final planningMonthsFuture = backend.fetchPlanningMonths();
    final exchangesFuture = backend.fetchExchanges();
    final leavesFuture = backend.fetchLeaveRequests();
    final directoryFuture = backend.fetchManualDirectoryContacts();
    final passwordResetFuture = sessionUser.role == UserRole.admin
        ? backend.fetchPasswordResetRequests()
        : Future<List<PasswordResetRequest>>.value(const <PasswordResetRequest>[]);

    final profiles = await profilesFuture;
    final planning = await planningFuture;
    final planningMonths = await planningMonthsFuture;
    final exchanges = await exchangesFuture;
    final leaves = await leavesFuture;
    final passwordResetRequests = await passwordResetFuture;
    List<DirectoryContact> manualDirectoryContacts = const [];
    try {
      manualDirectoryContacts = await directoryFuture;
    } catch (e) {
      debugPrint('Annuaire manuel indisponible: $e');
    }
    if (_sessionEpoch != expectedEpoch || currentUser?.id != expectedUserId) {
      // A logout or account switch occurred while network calls were running.
      return;
    }
    _users
      ..clear()
      ..addAll(profiles);
    final refreshedMe=_users.where((u)=>u.id==currentUser!.id).firstOrNull;
    if(refreshedMe!=null){
      currentUser=refreshedMe;
    }else if(!_users.any((u)=>u.phone==currentUser!.phone)){
      _users.add(currentUser!);
    }
    _planning
      ..clear()
      ..addAll(planning);
    _planningMonths
      ..clear()
      ..addAll(planningMonths);
    _exchanges
      ..clear()
      ..addAll(exchanges);
    _leaveRequests
      ..clear()
      ..addAll(leaves);
    _passwordResetRequests
      ..clear()
      ..addAll(passwordResetRequests);
    _manualDirectoryContacts
      ..clear()
      ..addAll(manualDirectoryContacts);
    _rebuildDirectory();
    await _syncCurrentUserRemindersAfterBackend();
    await _persistNow();
    notifyListeners();
  }

  Future<void> refreshBackend() => _reloadAndSyncMyOfficialRoster();

  Future<void> _syncCurrentUserRemindersAfterBackend() async {
    // Important : la superposition du PDF officiel ne déclenche rien ici.
    // Seules les gardes d'un mois définitivement validé sont éligibles.
    await rescheduleAllReminders();
  }

  void _scheduleRealtimeReload({bool syncOfficialRoster = false}) {
    _realtimeNeedsOfficialSync = _realtimeNeedsOfficialSync || syncOfficialRoster;
    _realtimeReloadTimer?.cancel();
    _realtimeReloadTimer = Timer(const Duration(milliseconds: 300), () {
      final needsOfficialSync = _realtimeNeedsOfficialSync;
      _realtimeNeedsOfficialSync = false;
      if (needsOfficialSync) {
        unawaited(_reloadAndSyncMyOfficialRoster());
      } else {
        unawaited(_reloadFromBackend());
      }
    });
  }

  void _startRealtime() {
    if (!backendEnabled || currentUser == null) return;
    _planningRealtime?.cancel();
    _planningMonthRealtime?.cancel();
    _exchangeRealtime?.cancel();
    _leaveRealtime?.cancel();
    _profileRealtime?.cancel();
    _directoryRealtime?.cancel();
    _passwordResetRealtime?.cancel();
    final client=SupabaseBackendService.instance.client;
    _planningRealtime=client.from('planning_entries').stream(primaryKey:['id']).listen((_)=>_scheduleRealtimeReload());
    _planningMonthRealtime=client.from('planning_months').stream(primaryKey:['owner_id','year','month']).listen((_)=>_scheduleRealtimeReload());
    _exchangeRealtime=client.from('exchange_requests').stream(primaryKey:['id']).listen((_)=>_scheduleRealtimeReload());
    _leaveRealtime=client.from('leave_requests').stream(primaryKey:['id']).listen((_)=>_scheduleRealtimeReload());
    _profileRealtime=client.from('profiles').stream(primaryKey:['id']).listen((_)=>_scheduleRealtimeReload(syncOfficialRoster:true));
    _directoryRealtime=client.from('directory_contacts').stream(primaryKey:['id']).listen((_)=>_scheduleRealtimeReload(), onError: (Object e)=>debugPrint('Realtime annuaire indisponible: $e'));
    if (currentUser?.role == UserRole.admin) {
      _passwordResetRealtime=client.from('password_reset_requests').stream(primaryKey:['id']).listen((_)=>_scheduleRealtimeReload());
    }
  }

  void _stopRealtime(){
    _realtimeReloadTimer?.cancel();
    _realtimeReloadTimer=null;
    _realtimeNeedsOfficialSync=false;
    _planningRealtime?.cancel();
    _planningMonthRealtime?.cancel();
    _exchangeRealtime?.cancel();
    _leaveRealtime?.cancel();
    _profileRealtime?.cancel();
    _directoryRealtime?.cancel();
    _passwordResetRealtime?.cancel();
    _planningRealtime=null;
    _planningMonthRealtime=null;
    _exchangeRealtime=null;
    _leaveRealtime=null;
    _profileRealtime=null;
    _directoryRealtime=null;
    _passwordResetRealtime=null;
  }

  DateTime _visibleMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime get visibleMonth => _visibleMonth;

  DateTime get maxPlanningMonth {
    final now = DateTime.now();
    return DateTime(now.year + 2, 12, 1);
  }

  DateTime get maxPlanningDate {
    final now = DateTime.now();
    return DateTime(now.year + 2, 12, 31);
  }

  bool get canGoToNextMonth => _visibleMonth.isBefore(maxPlanningMonth);

  void nextMonth(){
    final next=DateTime(_visibleMonth.year,_visibleMonth.month+1,1);
    if(next.isAfter(maxPlanningMonth))return;
    _visibleMonth=next;
    notifyListeners();
  }

  void previousMonth(){
    _visibleMonth=DateTime(_visibleMonth.year,_visibleMonth.month-1,1);
    notifyListeners();
  }

  static String dateKey(DateTime d)=>DateFormat('yyyy-MM-dd').format(d);

  final List<PlanningEntry> _planning=[];
  List<PlanningEntry> get planning=>List.unmodifiable(_planning);
  int _planningCounter=0;
  List<PlanningEntry> entriesForDate(String d)=>_planning.where((e)=>e.dateStr==d).toList();
  PlanningEntry? entryForUserOnDate(String d,String phone)=>_planning.where((e)=>e.dateStr==d&&e.ownerPhone==phone).firstOrNull;
  PlanningEntry? entryForUserIdOnDate(String d,String ownerId)=>_planning.where((e)=>e.dateStr==d&&e.ownerId==ownerId).firstOrNull;
  PlanningEntry? myEntryForDate(String d){
    final me=currentUser;if(me==null)return null;
    return _planning.where((e)=>e.dateStr==d&&(e.ownerId==me.id||e.ownerPhone==me.phone)).firstOrNull;
  }

  final List<PlanningMonth> _planningMonths=[];
  List<PlanningMonth> get planningMonths=>List.unmodifiable(_planningMonths);

  PlanningMonth? planningMonthForUser(String ownerId,int year,int month)=>
      _planningMonths.where((p)=>p.ownerId==ownerId&&p.year==year&&p.month==month).firstOrNull;

  PlanningMonth? myPlanningMonth(DateTime month){
    final me=currentUser;if(me==null)return null;
    return planningMonthForUser(me.id,month.year,month.month);
  }

  PlanningMonthStatus planningMonthStatusForUser(String ownerId,int year,int month)=>
      planningMonthForUser(ownerId,year,month)?.status ?? PlanningMonthStatus.draft;

  bool canEditMyPlanningMonth(DateTime month){
    final now=DateTime.now();
    final monthStart=DateTime(month.year,month.month,1);
    final currentMonthStart=DateTime(now.year,now.month,1);
    if(monthStart.isBefore(currentMonthStart) || monthStart.isAfter(maxPlanningMonth)){
      return false;
    }
    final status=myPlanningMonth(month)?.status ?? PlanningMonthStatus.draft;
    // V10.2 : le médecin verrouille lui-même son mois. Les anciens états
    // submitted/rejected de V10.1 sont donc traités comme des brouillons.
    return status!=PlanningMonthStatus.approved;
  }

  LeaveRequest? leaveRequestForEntry(PlanningEntry entry){
    final id=entry.leaveRequestId;
    if(id==null)return null;
    return _leaveRequests.where((r)=>r.id==id).firstOrNull;
  }

  bool isPlanningEntryApproved(PlanningEntry entry){
    final d=DateTime.parse(entry.dateStr);
    final me=currentUser;
    final record=planningMonthForUser(entry.ownerId,d.year,d.month);
    // En mode Supabase, un médecin non-admin ne reçoit les gardes d'un collègue
    // qu'après validation du mois grâce à la RLS. Son planning_month n'est pas
    // directement visible, donc la présence de la garde fait foi côté client.
    final peerVisibleAndOfficial=backendEnabled&&me!=null&&me.role!=UserRole.admin&&entry.ownerId!=me.id&&entry.ownerPhone!=me.phone;
    final monthApproved=record?.status==PlanningMonthStatus.approved||peerVisibleAndOfficial;
    if(!monthApproved)return false;
    if(entry.shiftId!='conge')return true;
    final leave=leaveRequestForEntry(entry);
    // Les congés historiques sans demande liée restent considérés comme acquis.
    // Une tuile Congé en attente n'est jamais exposée aux collègues par la RLS.
    return leave==null||leave.status==LeaveRequestStatus.approved||peerVisibleAndOfficial;
  }

  bool isApprovedLeaveEntry(PlanningEntry entry){
    if(entry.shiftId!='conge')return false;
    final leave=leaveRequestForEntry(entry);
    return leave?.status==LeaveRequestStatus.approved;
  }

  bool canAdminDeleteEntry(PlanningEntry entry){
    final me=currentUser;
    if(me==null||me.role!=UserRole.admin)return false;
    return entry.isDisciplinary||isPlanningEntryApproved(entry)||isApprovedLeaveEntry(entry);
  }

  bool isUserPlanningMonthApproved(String ownerId,String dateStr){
    final d=DateTime.parse(dateStr);
    final record=planningMonthForUser(ownerId,d.year,d.month);
    if(record!=null)return record.status==PlanningMonthStatus.approved;
    final me=currentUser;
    // Les planning_months des collègues sont masqués par RLS aux médecins.
    // On laisse alors le RPC serveur effectuer la vérification autoritaire.
    if(backendEnabled&&me!=null&&me.role!=UserRole.admin&&ownerId!=me.id)return true;
    return false;
  }

  int _delayMinutes=60; // compatibilité avec l'ancien stockage V11.6.6
  bool _notificationsOn=true;
  List<int> _reminderDelays=<int>[1440,120];
  int _reminderRepeatMinutes=15;
  int _reminderRepeatCount=1;
  bool _reminderVibration=true;
  String _reminderSoundMode='urgent';
  final Map<String,Map<String,dynamic>> _reminderPrefsByUser=<String,Map<String,dynamic>>{};

  List<int> get reminderDelays=>List.unmodifiable(_reminderDelays);
  int get reminderRepeatMinutes=>_reminderRepeatMinutes;
  int get reminderRepeatCount=>_reminderRepeatCount;
  bool get reminderVibration=>_reminderVibration;
  String get reminderSoundMode=>_reminderSoundMode;
  int get delayMinutes=>_reminderDelays.isNotEmpty?_reminderDelays.first:_delayMinutes;
  set delayMinutes(int v){unawaited(setReminderDelays(<int>[v]));}
  bool get notificationsOn=>_notificationsOn;
  set notificationsOn(bool v){unawaited(setNotificationsOn(v));}

  String? get _reminderOwnerKey{
    final me=currentUser;if(me==null)return null;
    return me.id.isNotEmpty?me.id:me.phone;
  }

  void _applyReminderPrefsForCurrentUser(){
    final legacyDelay=_delayMinutes;
    final legacyOn=_notificationsOn;
    _reminderDelays=<int>[1440,120];
    _reminderRepeatMinutes=15;
    _reminderRepeatCount=1;
    _reminderVibration=true;
    _reminderSoundMode='urgent';
    _notificationsOn=true;
    final key=_reminderOwnerKey;if(key==null)return;
    final p=_reminderPrefsByUser[key];
    if(p==null){
      // Migration douce de l'unique ancien réglage lors de la première ouverture.
      if(_reminderPrefsByUser.isEmpty){_reminderDelays=<int>[legacyDelay];_notificationsOn=legacyOn;}
      _delayMinutes=_reminderDelays.first;
      return;
    }
    final delays=(p['delays'] as List? ?? const <dynamic>[]).map((e)=>(e as num).toInt()).where((e)=>e>0&&e<=10080).toSet().toList()..sort((a,b)=>b.compareTo(a));
    if(delays.isNotEmpty)_reminderDelays=delays.take(3).toList();
    _reminderRepeatMinutes=((p['repeatMinutes'] as num?)?.toInt()??15).clamp(5,180);
    _reminderRepeatCount=((p['repeatCount'] as num?)?.toInt()??1).clamp(0,3);
    _reminderVibration=p['vibration'] as bool? ?? true;
    final sound=p['soundMode']?.toString()??'urgent';
    _reminderSoundMode=const <String>{'system','urgent','silent','alarm'}.contains(sound)?sound:'urgent';
    _notificationsOn=p['enabled'] as bool? ?? true;
    _delayMinutes=_reminderDelays.first;
  }

  void _storeReminderPrefsForCurrentUser(){
    final key=_reminderOwnerKey;if(key==null)return;
    _reminderPrefsByUser[key]=<String,dynamic>{
      'delays':List<int>.from(_reminderDelays),
      'repeatMinutes':_reminderRepeatMinutes,
      'repeatCount':_reminderRepeatCount,
      'vibration':_reminderVibration,
      'soundMode':_reminderSoundMode,
      'enabled':_notificationsOn,
    };
    _delayMinutes=_reminderDelays.first;
  }

  Future<void> _saveReminderPrefs() async{_storeReminderPrefsForCurrentUser();await _persistNow();notifyListeners();}

  Future<void> setReminderDelays(List<int> values) async{
    final cleaned=values.where((e)=>e>0&&e<=10080).toSet().toList()..sort((a,b)=>b.compareTo(a));
    _reminderDelays=cleaned.isEmpty?<int>[60]:cleaned.take(3).toList();
    await _saveReminderPrefs();
  }
  Future<void> setReminderRepeatMinutes(int value) async{_reminderRepeatMinutes=value.clamp(5,180);await _saveReminderPrefs();}
  Future<void> setReminderRepeatCount(int value) async{_reminderRepeatCount=value.clamp(0,3);await _saveReminderPrefs();}
  Future<void> setReminderVibration(bool value) async{_reminderVibration=value;await _saveReminderPrefs();}
  Future<void> setReminderSoundMode(String value) async{_reminderSoundMode=const <String>{'system','urgent','silent','alarm'}.contains(value)?value:'system';await _saveReminderPrefs();}
  Future<void> setNotificationsOn(bool value) async{
    _notificationsOn=value;
    if(value){
      await NotificationService.instance.requestPermission();
      if(backendEnabled&&currentUser!=null&&(kIsWeb||defaultTargetPlatform==TargetPlatform.android||defaultTargetPlatform==TargetPlatform.iOS)){
        unawaited(PushNotificationService.instance.activateForSignedInUser());
      }
    }else{
      await NotificationService.instance.cancelAll();
      if(backendEnabled&&currentUser!=null)unawaited(PushNotificationService.instance.unregisterCurrentDevice());
    }
    await _saveReminderPrefs();
  }

  String reminderDelayLabel(int minutes){
    if(minutes%1440==0)return '${minutes~/1440} j avant';
    if(minutes%60==0)return '${minutes~/60} h avant';
    return '$minutes min avant';
  }

  String? get nextReminderSummary{
    _refreshReminderStatuses();
    final me=currentUser;if(me==null)return null;
    final list=_reminders.where((r)=>r.ownerPhone==me.phone&&r.status==ReminderStatus.upcoming).toList()..sort((a,b)=>a.fireAt.compareTo(b.fireAt));
    if(list.isEmpty)return null;
    final r=list.first;
    return 'Prochain rappel : ${DateFormat('dd/MM à HH:mm','fr_FR').format(r.fireAt)} · ${r.label}';
  }

  Future<void> testGuardReminder() async{
    await NotificationService.instance.showReminderTest(soundMode:_reminderSoundMode,vibration:_reminderVibration);
  }

  final List<AppUser> _users=[];
  List<AppUser> get users=>List.unmodifiable(_users);
  AppUser? currentUser;

  final List<DirectoryContact> _manualDirectoryContacts=[];
  List<DirectoryContact> get manualDirectoryContacts=>List.unmodifiable(_manualDirectoryContacts);

  final List<DirectorySection> _directory=[];
  List<DirectorySection> get directory=>_directory;

  String _directoryPhoneKey(String value)=>value.replaceAll(RegExp(r'[^0-9]'), '');

  void _rebuildDirectory(){
    final base=buildSeedDirectory();
    // En production Supabase, les contacts fictifs de démonstration sont retirés.
    // Les médecins actifs viennent des profils et les autres catégories de la
    // table directory_contacts gérée par les administrateurs.
    if(backendEnabled){
      for(final section in base){section.contacts.clear();}
    }
    _directory..clear()..addAll(base);

    for(final u in _users.where((u)=>u.accountStatus==AccountStatus.active)){
      final id=u.grade==MedicalGrade.senior?kDirectoryCategorySeniors:kDirectoryCategoryJuniors;
      final section=_directory.where((s)=>s.id==id).firstOrNull;
      final phoneKey=_directoryPhoneKey(u.phone);
      if(section!=null&&!section.contacts.any((c)=>_directoryPhoneKey(c.phone)==phoneKey)){
        section.contacts.add(DirectoryContact(
          id:u.id,
          name:u.fullName,
          phone:u.phone,
          hospital:u.hospital,
          service:u.service,
          gradeLabel:u.gradeLabel,
          isAdmin:u.role==UserRole.admin,
          categoryId:id,
        ));
      }
    }

    for(final contact in _manualDirectoryContacts){
      final section=_directory.where((s)=>s.id==contact.categoryId).firstOrNull;
      if(section==null)continue;
      final phoneKey=_directoryPhoneKey(contact.phone);
      if(_directory.expand((s)=>s.contacts).any((c)=>c.hospital==contact.hospital&&_directoryPhoneKey(c.phone)==phoneKey))continue;
      section.contacts.add(contact);
    }

    for(final section in _directory){
      section.contacts.sort((a,b)=>a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
  }

  Future<String?> addDirectoryContact({
    required String categoryId,
    required String name,
    required String phone,
    required String hospital,
    String? service,
  }) async {
    final me=currentUser;
    if(me==null||me.role!=UserRole.admin)return 'Action réservée à l’administrateur.';
    final cleanName=name.trim();
    final cleanPhone=phone.trim();
    if(!kManualDirectoryCategoryIds.contains(categoryId))return 'Catégorie invalide.';
    if(cleanName.isEmpty)return 'Le nom / libellé est obligatoire.';
    if(_directoryPhoneKey(cleanPhone).length<4)return 'Numéro de téléphone invalide.';
    if(!kHospitals.contains(hospital))return 'Établissement invalide.';
    final duplicate=_directory.expand((s)=>s.contacts).any((c)=>c.hospital==hospital&&_directoryPhoneKey(c.phone)==_directoryPhoneKey(cleanPhone));
    if(duplicate)return 'Ce numéro existe déjà dans l’annuaire de cet établissement.';
    try{
      if(backendEnabled){
        await SupabaseBackendService.instance.addManualDirectoryContact(
          categoryId:categoryId,name:cleanName,phone:cleanPhone,hospital:hospital,service:service,
        );
        await _reloadFromBackend();
      }else{
        _manualDirectoryContacts.add(DirectoryContact(
          id:'local-directory-${DateTime.now().microsecondsSinceEpoch}',
          name:cleanName,phone:cleanPhone,hospital:hospital,
          service:(service ?? '').trim().isEmpty?null:service!.trim(),
          categoryId:categoryId,isManual:true,
        ));
        _rebuildDirectory();_persist();notifyListeners();
      }
      return null;
    }catch(e){return 'Ajout du contact impossible : $e';}
  }

  Future<String?> updateDirectoryContact({
    required String id,
    required String categoryId,
    required String name,
    required String phone,
    required String hospital,
    String? service,
  }) async {
    final me=currentUser;
    if(me==null||me.role!=UserRole.admin)return 'Action réservée à l’administrateur.';
    final existing=_manualDirectoryContacts.where((c)=>c.id==id).firstOrNull;
    if(existing==null)return 'Contact manuel introuvable.';
    final cleanName=name.trim();
    final cleanPhone=phone.trim();
    if(!kManualDirectoryCategoryIds.contains(categoryId))return 'Catégorie invalide.';
    if(cleanName.isEmpty)return 'Le nom / libellé est obligatoire.';
    if(_directoryPhoneKey(cleanPhone).length<4)return 'Numéro de téléphone invalide.';
    if(!kHospitals.contains(hospital))return 'Établissement invalide.';
    final duplicate=_directory.expand((s)=>s.contacts).any((c)=>c.id!=id&&c.hospital==hospital&&_directoryPhoneKey(c.phone)==_directoryPhoneKey(cleanPhone));
    if(duplicate)return 'Ce numéro existe déjà dans l’annuaire de cet établissement.';
    try{
      if(backendEnabled){
        await SupabaseBackendService.instance.updateManualDirectoryContact(
          id:id,categoryId:categoryId,name:cleanName,phone:cleanPhone,hospital:hospital,service:service,
        );
        await _reloadFromBackend();
      }else{
        final index=_manualDirectoryContacts.indexWhere((c)=>c.id==id);
        _manualDirectoryContacts[index]=DirectoryContact(
          id:id,name:cleanName,phone:cleanPhone,hospital:hospital,
          service:(service ?? '').trim().isEmpty?null:service!.trim(),
          categoryId:categoryId,isManual:true,
        );
        _rebuildDirectory();_persist();notifyListeners();
      }
      return null;
    }catch(e){return 'Modification du contact impossible : $e';}
  }

  Future<String?> deleteDirectoryContact(String id) async {
    final me=currentUser;
    if(me==null||me.role!=UserRole.admin)return 'Action réservée à l’administrateur.';
    if(!_manualDirectoryContacts.any((c)=>c.id==id))return 'Contact manuel introuvable.';
    try{
      if(backendEnabled){
        await SupabaseBackendService.instance.deleteManualDirectoryContact(id);
        await _reloadFromBackend();
      }else{
        _manualDirectoryContacts.removeWhere((c)=>c.id==id);
        _rebuildDirectory();_persist();notifyListeners();
      }
      return null;
    }catch(e){return 'Suppression du contact impossible : $e';}
  }

  final List<AstreintePhoto> _astreinte=[];
  List<AstreintePhoto> get astreinte {
    final me=currentUser;if(me==null)return const [];
    return List.unmodifiable(_astreinte.where((p)=>p.ownerPhone==me.phone));
  }
  Future<void> addAstreintePhoto(XFile file) async {
    final me=currentUser;if(me==null)return;
    final bytes=await file.readAsBytes();
    _astreinte.add(AstreintePhoto(id:'a${DateTime.now().microsecondsSinceEpoch}',ownerPhone:me.phone,bytes:bytes,name:file.name));
    // Évite de saturer le stockage navigateur : 8 images récentes par compte.
    final mine=_astreinte.where((p)=>p.ownerPhone==me.phone).toList()..sort((a,b)=>b.createdAt.compareTo(a.createdAt));
    if(mine.length>8){final keep=mine.take(8).map((p)=>p.id).toSet();_astreinte.removeWhere((p)=>p.ownerPhone==me.phone&&!keep.contains(p.id));}
    await _persistNow();notifyListeners();
  }
  void removeAstreintePhoto(String id){final me=currentUser;if(me==null)return;_astreinte.removeWhere((p)=>p.id==id&&p.ownerPhone==me.phone);_persist();notifyListeners();}

  final List<ReminderNotification> _reminders=[];
  List<ReminderNotification> get reminders { _refreshReminderStatuses(); final me=currentUser;if(me==null)return const [];return List.unmodifiable(_reminders.where((r)=>r.ownerPhone==me.phone));}

  final List<ExchangeRequest> _exchanges=[];
  List<ExchangeRequest> get exchanges=>List.unmodifiable(_exchanges);
  final List<LeaveRequest> _leaveRequests=[];
  List<LeaveRequest> get leaveRequests=>List.unmodifiable(_leaveRequests);
  final List<PasswordResetRequest> _passwordResetRequests=[];
  List<PasswordResetRequest> get passwordResetRequests=>List.unmodifiable(_passwordResetRequests);
  int _exchangeCounter=0,_leaveCounter=0,_reminderCounter=0;

  LeaveRequest? pendingLeaveForUserOnDate(String d,String phone)=>_leaveRequests.where((r)=>r.includesDate(d)&&r.ownerPhone==phone&&r.status==LeaveRequestStatus.pendingAdmin).firstOrNull;
  LeaveRequest? myPendingLeaveForDate(String d){
    final me=currentUser;if(me==null)return null;
    return _leaveRequests.where((r)=>r.includesDate(d)&&(r.ownerId==me.id||r.ownerPhone==me.phone)&&r.status==LeaveRequestStatus.pendingAdmin).firstOrNull;
  }
  List<AppUser> get pendingUsers=>List.unmodifiable(_users.where((u)=>u.accountStatus==AccountStatus.pending));

  List<PlanningEntry> leaveConflictingEntries(LeaveRequest request)=>_planning.where((e)=>
    (e.ownerId==request.ownerId||e.ownerPhone==request.ownerPhone)&&e.shiftId!='conge'&&request.includesDate(e.dateStr)
  ).toList()..sort((a,b)=>a.dateStr.compareTo(b.dateStr));

  static String normalizePhone(String raw)=>raw.replaceAll(RegExp(r'[\s.\-]'),'');

  Future<String?> login(String rawPhone,String password) async {
    if (backendEnabled) {
      try {
        final backend=SupabaseBackendService.instance;
        final user=await backend.signIn(rawPhone,password);
        if(user.accountStatus!=AccountStatus.active){
          await backend.signOut();
          currentUser=null;
          await LocalStorageService.savePushActiveUserId(null);
          await LocalStorageService.savePushEnabled(false);
          if(user.accountStatus==AccountStatus.pending){
            return 'Votre compte est en attente de validation par un administrateur.';
          }
          return 'Votre compte est suspendu. Contactez un administrateur.';
        }
        _sessionEpoch++;
        currentUser=user;
        await LocalStorageService.savePushActiveUserId(user.id);
        _applyReminderPrefsForCurrentUser();
        final locallyDismissedNotifications = Set<String>.from(_dismissedNotificationKeys);
        await _reloadFromBackend();
        _dismissedNotificationKeys.addAll(locallyDismissedNotifications);
        await _syncMyOfficialRosterIfNeeded();
        _startRealtime();
        if(_notificationsOn){
          if(kIsWeb||defaultTargetPlatform==TargetPlatform.android||defaultTargetPlatform==TargetPlatform.iOS){
            unawaited(PushNotificationService.instance.activateForSignedInUser());
          }else{
            unawaited(NotificationService.instance.requestPermission());
          }
        }
        _activateNativeRemindersForCurrentUser();
        notifyListeners();
        return null;
      } catch(e) {
        return 'Connexion impossible : $e';
      }
    }
    final phone=normalizePhone(rawPhone);final user=_users.where((u)=>u.phone==phone).firstOrNull;
    if(user==null||!PasswordService.verify(password,user.passwordSalt,user.passwordHash)) return 'Numéro ou mot de passe incorrect.';
    if(user.accountStatus!=AccountStatus.active)return user.accountStatus==AccountStatus.pending?'Votre compte est en attente de validation par un administrateur.':'Votre compte est suspendu. Contactez un administrateur.';
    _sessionEpoch++;currentUser=user;_applyReminderPrefsForCurrentUser();unawaited(LocalStorageService.saveSessionPhone(user.phone));if(_notificationsOn)unawaited(NotificationService.instance.requestPermission());unawaited(_activateNativeRemindersForCurrentUser());notifyListeners();return null;
  }

  Future<String?> register({required String nom,required String prenom,required String rawPhone,required String password,
    required String service,required MedicalGrade grade,required String hospital}) async {
    final phone=normalizePhone(rawPhone);
    if(nom.trim().isEmpty||prenom.trim().isEmpty||phone.isEmpty||password.isEmpty)return 'Merci de remplir tous les champs.';
    if(password.length<8)return 'Le mot de passe doit contenir au moins 8 caractères.';
    if (backendEnabled) {
      try {
        final backend=SupabaseBackendService.instance;
        final pending=await backend.signUp(nom:nom,prenom:prenom,rawPhone:rawPhone,password:password,service:service,grade:grade,hospital:hospital);
        try{await backend.triggerPush('account_created',pending.id);}catch(_){}
        await backend.signOut();
        currentUser=null;
        await LocalStorageService.savePushActiveUserId(null);
        await LocalStorageService.savePushEnabled(false);
        notifyListeners();
        return null;
      } catch(e) {
        return 'Création impossible : $e';
      }
    }
    if(_users.any((u)=>u.phone==phone))return 'Un compte existe déjà avec ce numéro. Connectez-vous.';
    final salt=PasswordService.generateSalt();
    final user=AppUser(id:'local-${DateTime.now().microsecondsSinceEpoch}',nom:nom.trim(),prenom:prenom.trim(),phone:phone,passwordHash:PasswordService.hash(password,salt),passwordSalt:salt,
      service:service,grade:grade,hospital:hospital);
    _users.add(user);_rebuildDirectory();currentUser=user;if(_notificationsOn)unawaited(NotificationService.instance.requestPermission());_persist();unawaited(LocalStorageService.saveSessionPhone(user.phone));notifyListeners();return null;
  }

  Future<void> logout() async {
    // Invalidate every reload already in flight before touching the session.
    _sessionEpoch++;
    _stopRealtime();
    await LocalStorageService.savePushActiveUserId(null);
    await LocalStorageService.savePushEnabled(false);
    await NotificationService.instance.cancelAll();
    if(backendEnabled){
      // Must happen while the Supabase JWT still identifies the old account.
      await PushNotificationService.instance.unregisterCurrentDevice();
      await SupabaseBackendService.instance.signOut();
    }
    currentUser=null;
    await LocalStorageService.saveSessionPhone(null);
    notifyListeners();
  }

  bool _isDateInPast(String dateStr){
    final d=DateTime.parse(dateStr);
    final today=DateTime.now();
    final t=DateTime(today.year,today.month,today.day);
    return d.isBefore(t);
  }

  bool dateIsPast(String dateStr)=>_isDateInPast(dateStr);

  bool _guardHasStarted(PlanningEntry entry){
    if(_isDateInPast(entry.dateStr))return true;
    final shift=ShiftCatalog.byId(entry.shiftId);
    if(!shift.hasSchedule)return false;
    final date=DateTime.parse(entry.dateStr);
    final time=shift.start!.split(':').map(int.parse).toList();
    final start=DateTime(date.year,date.month,date.day,time[0],time[1]);
    return !DateTime.now().isBefore(start);
  }
  bool guardHasStarted(PlanningEntry entry)=>_guardHasStarted(entry);

  /// Le médecin construit lui-même son calendrier avec les tuiles.
  /// Le mois reste modifiable tant qu'il n'a pas été soumis/validé.
  Future<String?> placeShift(String dateStr,String shiftId) async {
    final me=currentUser;if(me==null)return 'Session expirée.';
    if(_isDateInPast(dateStr))return 'Une date passée ne peut plus être modifiée.';
    final date=DateTime.parse(dateStr);
    if(date.isAfter(maxPlanningDate)){
      return 'Cette date dépasse l’horizon de planification autorisé.';
    }
    final shift=ShiftCatalog.all.where((s)=>s.id==shiftId).firstOrNull;
    if(shift==null)return 'Type de tuile invalide.';
    if(shift.hasSchedule){
      final parts=shift.start!.split(':').map(int.parse).toList();
      final start=DateTime(date.year,date.month,date.day,parts[0],parts[1]);
      if(!DateTime.now().isBefore(start)){
        return 'Cette garde a déjà commencé et ne peut plus être ajoutée ou modifiée.';
      }
    }
    final status=myPlanningMonth(date)?.status ?? PlanningMonthStatus.draft;
    if(status==PlanningMonthStatus.approved)return 'Ce calendrier est validé définitivement. Utilisez ensuite transfert/échange ou contactez un administrateur.';
    final existing=myEntryForDate(dateStr);
    if(existing?.isDisciplinary==true)return 'Cette garde disciplinaire est verrouillée. Seul un administrateur peut la supprimer.';
    if(existing!=null&&isApprovedLeaveEntry(existing))return 'Ce congé a déjà été approuvé. Seul un administrateur peut le supprimer.';
    if(existing!=null&&_isEntryLocked(existing.id))return 'Cette garde est verrouillée par une demande active.';
    try{
      if(backendEnabled){
        await SupabaseBackendService.instance.saveMyPlanningEntry(dateStr:dateStr,shiftId:shiftId);
        await _reloadFromBackend();
      }else{
        _cancelReminder(me.phone,dateStr);
        if(existing!=null){
          existing.shiftId=shiftId;
        }else{
          _planning.add(PlanningEntry(
            id:'p${++_planningCounter}',dateStr:dateStr,shiftId:shiftId,
            ownerId:me.id,ownerPhone:me.phone,ownerName:me.fullName,
          ));
        }
        _ensureLocalPlanningMonth(me.id,date.year,date.month,PlanningMonthStatus.draft);
        _persist();notifyListeners();
      }
      return null;
    }catch(e){return 'Modification impossible : $e';}
  }

  PlanningMonth _ensureLocalPlanningMonth(String ownerId,int year,int month,PlanningMonthStatus status){
    var record=planningMonthForUser(ownerId,year,month);
    if(record==null){
      record=PlanningMonth(ownerId:ownerId,year:year,month:month,status:status);
      _planningMonths.add(record);
    }else{
      record.status=status;
      if(status==PlanningMonthStatus.draft){record.rejectionReason=null;record.reviewedAt=null;record.reviewedBy=null;}
    }
    return record;
  }

  Future<String?> removeShift(String entryId) async {
    final me=currentUser;if(me==null)return 'Session expirée.';
    final entry=_planning.where((e)=>e.id==entryId).firstOrNull;
    if(entry==null||(entry.ownerId!=me.id&&entry.ownerPhone!=me.phone))return 'Affectation introuvable.';
    if(entry.isDisciplinary)return 'Cette garde disciplinaire ne peut pas être annulée. Seul un administrateur peut la supprimer.';
    if(entry.shiftId!='conge'&&_guardHasStarted(entry)){
      return 'Cette garde a déjà commencé et ne peut plus être supprimée.';
    }
    final date=DateTime.parse(entry.dateStr);
    final status=myPlanningMonth(date)?.status ?? PlanningMonthStatus.draft;
    if(status==PlanningMonthStatus.approved)return 'Un calendrier validé ne peut plus être modifié directement. Seul un administrateur peut supprimer une garde validée.';
    if(isApprovedLeaveEntry(entry))return 'Ce congé a déjà été approuvé. Seul un administrateur peut le supprimer.';
    if(_isEntryLocked(entry.id))return 'Cette garde est verrouillée par une demande active.';
    try{
      if(backendEnabled){
        await SupabaseBackendService.instance.deleteMyPlanningEntry(entry.id);
        await _reloadFromBackend();
      }else{
        _cancelReminder(me.phone,entry.dateStr);
        _planning.removeWhere((e)=>e.id==entry.id);
        _ensureLocalPlanningMonth(me.id,date.year,date.month,PlanningMonthStatus.draft);
        _persist();notifyListeners();
      }
      return null;
    }catch(e){return 'Suppression impossible : $e';}
  }

  Future<String?> submitMyPlanningMonth(DateTime month) async {
    final me=currentUser;if(me==null)return 'Session expirée.';
    final first=DateTime(month.year,month.month,1);
    final now=DateTime.now();
    final currentFirst=DateTime(now.year,now.month,1);
    if(first.isBefore(currentFirst))return 'Un calendrier d’un mois passé ne peut plus être validé.';
    final status=myPlanningMonth(month)?.status ?? PlanningMonthStatus.draft;
    if(status==PlanningMonthStatus.approved)return 'Ce calendrier est déjà validé définitivement.';
    try{
      if(backendEnabled){
        final leaveIds=await SupabaseBackendService.instance.submitMyPlanningMonth(month.year,month.month);
        // Les tuiles Congé deviennent automatiquement des demandes à valider
        // par l'administration au moment où le médecin fige son calendrier.
        for(final id in leaveIds){_firePush('leave_created',id);}
        await _reloadFromBackend();
      }else{
        final r=_ensureLocalPlanningMonth(me.id,month.year,month.month,PlanningMonthStatus.approved);
        r.submittedAt=DateTime.now();r.reviewedAt=null;r.reviewedBy=null;r.rejectionReason=null;
        final prefix='${month.year}-${month.month.toString().padLeft(2,'0')}-';
        final conges=_planning.where((e)=>(e.ownerId==me.id||e.ownerPhone==me.phone)&&e.dateStr.startsWith(prefix)&&e.shiftId=='conge').toList()
          ..sort((a,b)=>a.dateStr.compareTo(b.dateStr));
        var i=0;
        while(i<conges.length){
          if(conges[i].leaveRequestId!=null){i++;continue;}
          final group=<PlanningEntry>[conges[i]];
          var j=i+1;
          while(j<conges.length&&conges[j].leaveRequestId==null){
            final previous=DateTime.parse(group.last.dateStr);
            final current=DateTime.parse(conges[j].dateStr);
            if(current.difference(previous).inDays!=1)break;
            group.add(conges[j]);j++;
          }
          final id='lr${++_leaveCounter}';
          for(final entry in group){entry.leaveRequestId=id;}
          _leaveRequests.add(LeaveRequest(
            id:id,startDateStr:group.first.dateStr,endDateStr:group.last.dateStr,
            ownerId:me.id,ownerPhone:me.phone,ownerName:me.fullName,
          ));
          i=j;
        }
        _persist();
        rescheduleAllReminders();
      }
      return null;
    }catch(e){return 'Validation définitive du calendrier impossible : $e';}
  }

  Future<String?> requestLeave(String dateStr)=>requestLeaveRange(dateStr,dateStr);

  Future<String?> requestLeaveRange(String startDateStr,String endDateStr) async {
    final me=currentUser;if(me==null)return 'Session expirée.';
    if(_isDateInPast(startDateStr))return 'Une demande de congé ne peut pas commencer dans le passé.';
    if(endDateStr.compareTo(startDateStr)<0)return 'La période de congé est invalide.';
    final overlap=_leaveRequests.any((r)=>
      r.ownerPhone==me.phone&&
      (r.status==LeaveRequestStatus.pendingAdmin||r.status==LeaveRequestStatus.approved)&&
      startDateStr.compareTo(r.endDateStr)<=0&&endDateStr.compareTo(r.startDateStr)>=0);
    if(overlap)return 'Une demande de congé existe déjà sur tout ou partie de cette période.';
    final request=LeaveRequest(
      id: backendEnabled ? 'lr${DateTime.now().microsecondsSinceEpoch}' : 'lr${++_leaveCounter}',
      startDateStr:startDateStr,endDateStr:endDateStr,
      ownerId:me.id,ownerPhone:me.phone,ownerName:me.fullName,
    );
    if(backendEnabled){
      try{
        await SupabaseBackendService.instance.createLeaveRequest(request);
        _firePush('leave_created', request.id);
        await _reloadFromBackend();
        return null;
      }catch(e){return 'Demande de congé impossible : $e';}
    }
    _leaveRequests.add(request);_persist();notifyListeners();return null;
  }

  Future<String?> cancelLeave(String id) async {
    final me=currentUser;if(me==null)return 'Session expirée.';
    final r=_leaveRequests.where((x)=>x.id==id).firstOrNull;
    if(r==null||r.ownerPhone!=me.phone||r.status!=LeaveRequestStatus.pendingAdmin)return 'Annulation impossible.';
    if(backendEnabled){
      try{await SupabaseBackendService.instance.cancelLeaveRequest(id);_firePush('leave_cancelled', id);await _reloadFromBackend();return null;}catch(e){return 'Annulation impossible : $e';}
    }
    r.status=LeaveRequestStatus.cancelled;r.reviewedAt=DateTime.now();_persist();notifyListeners();return null;
  }

  Future<String?> reviewLeave(String id,bool approve) async {
    final me=currentUser;if(me==null||me.role!=UserRole.admin)return 'Action réservée à l’administrateur.';
    final r=_leaveRequests.where((x)=>x.id==id).firstOrNull;
    if(r==null||r.status!=LeaveRequestStatus.pendingAdmin)return 'Demande déjà traitée.';
    if(r.ownerId==me.id||r.ownerPhone==me.phone)return 'Un administrateur ne peut pas valider sa propre demande de congé.';
    if(approve){
      final conflicts=leaveConflictingEntries(r);
      if(conflicts.isNotEmpty){
        final dates=conflicts.map((e)=>DateFormat('dd/MM', 'fr_FR').format(DateTime.parse(e.dateStr))).join(', ');
        return 'Impossible d’approuver : une garde doit d’abord être couverte aux dates suivantes : $dates.';
      }
    }
    if(backendEnabled){
      try{await SupabaseBackendService.instance.reviewLeaveRequest(id,approve?'approve':'reject');_firePush('leave_reviewed', id);await _reloadFromBackend();return null;}catch(e){return 'Traitement impossible : $e';}
    }
    final linked=_planning.where((e)=>e.leaveRequestId==r.id&&e.shiftId=='conge').toList();
    if(approve){
      if(linked.isEmpty){
        var d=DateTime.parse(r.startDateStr);
        final end=DateTime.parse(r.endDateStr);
        while(!d.isAfter(end)){
          final dateStr=dateKey(d);
          final existing=_planning.where((e)=>(e.ownerId==r.ownerId||e.ownerPhone==r.ownerPhone)&&e.dateStr==dateStr).firstOrNull;
          if(existing==null){
            _planning.add(PlanningEntry(
              id:'p${++_planningCounter}',dateStr:dateStr,shiftId:'conge',
              ownerId:r.ownerId,ownerPhone:r.ownerPhone,ownerName:r.ownerName,
              leaveRequestId:r.id,
            ));
          }
          d=d.add(const Duration(days:1));
        }
      }
      r.status=LeaveRequestStatus.approved;
    }else{
      // Si la demande provenait d'une tuile Congé du calendrier figé,
      // le refus admin retire uniquement cette tuile. Le mois reste verrouillé.
      _planning.removeWhere((e)=>e.leaveRequestId==r.id&&e.shiftId=='conge');
      r.status=LeaveRequestStatus.rejectedAdmin;
    }
    r.reviewedAt=DateTime.now();_persist();notifyListeners();return null;
  }

  Future<String?> adminReopenPlanningMonth(AppUser doctor,DateTime month,{required String reason}) async {
    final me=currentUser;
    if(me==null||me.role!=UserRole.admin)return 'Action réservée à l’administrateur.';
    final cleanReason=reason.trim();
    if(cleanReason.length<3)return 'Indiquez un motif de dévalidation.';
    final first=DateTime(month.year,month.month,1);
    final now=DateTime.now();
    final currentFirst=DateTime(now.year,now.month,1);
    if(first.isBefore(currentFirst))return 'Un calendrier d’un mois passé ne peut pas être rouvert.';
    final record=planningMonthForUser(doctor.id,month.year,month.month);
    if(record?.status!=PlanningMonthStatus.approved)return 'Ce calendrier n’est pas validé.';
    try{
      if(backendEnabled){
        await SupabaseBackendService.instance.adminReopenPlanningMonth(
          ownerId:doctor.id,year:month.year,month:month.month,reason:cleanReason,
        );
        await _reloadFromBackend();
      }else{
        final prefix='${month.year}-${month.month.toString().padLeft(2,'0')}-';
        final monthEntries=_planning.where((e)=>e.ownerId==doctor.id&&e.dateStr.startsWith(prefix)).toList();
        final entryIds=monthEntries.map((e)=>e.id).toSet();
        for(final request in _exchanges.where((x)=>
          _isActiveRequest(x)&&(entryIds.contains(x.planningEntryId)||(x.targetPlanningEntryId!=null&&entryIds.contains(x.targetPlanningEntryId))))){
          request.status=ExchangeStatus.cancelled;
        }
        final pendingLeaveIds=<String>{};
        for(final entry in monthEntries){
          final leaveId=entry.leaveRequestId;
          if(leaveId==null)continue;
          final leave=_leaveRequests.where((r)=>r.id==leaveId).firstOrNull;
          if(leave?.status==LeaveRequestStatus.pendingAdmin){
            pendingLeaveIds.add(leaveId);
          }
        }
        for(final leaveId in pendingLeaveIds){
          final leave=_leaveRequests.where((r)=>r.id==leaveId).firstOrNull;
          if(leave!=null){leave.status=LeaveRequestStatus.cancelled;leave.reviewedAt=DateTime.now();}
          for(final entry in monthEntries.where((e)=>e.leaveRequestId==leaveId)){entry.leaveRequestId=null;}
        }
        record!
          ..status=PlanningMonthStatus.draft
          ..submittedAt=null
          ..reviewedAt=DateTime.now()
          ..reviewedBy=me.id
          ..rejectionReason=cleanReason;
        _persist();notifyListeners();
      }
      return null;
    }catch(e){return 'Dévalidation impossible : $e';}
  }

  Future<String?> adminDeleteShift(String entryId,{required String reason}) async {
    final me=currentUser;
    if(me==null||me.role!=UserRole.admin)return 'Suppression réservée à l’administrateur.';
    final entry=_planning.where((x)=>x.id==entryId).firstOrNull;
    if(entry==null)return 'Affectation introuvable.';
    if(!canAdminDeleteEntry(entry))return 'Seules les gardes disciplinaires, les gardes validées et les congés validés peuvent être supprimés par l’administrateur.';
    final cleanReason=reason.trim();
    if(cleanReason.length<3)return 'Indiquez un motif de suppression.';
    try{
      if(backendEnabled){
        await SupabaseBackendService.instance.adminDeletePlanning(entryId,cleanReason);
        _firePush('planning_admin_deleted', entryId);
        await _reloadFromBackend();
      }else{
        for(final request in _exchanges.where((x)=>_isActiveRequest(x)&&(x.planningEntryId==entryId||x.targetPlanningEntryId==entryId))){
          request.status=ExchangeStatus.cancelled;
        }
        if(entry.shiftId=='conge'&&entry.leaveRequestId!=null){
          final leaveId=entry.leaveRequestId!;
          _planning.removeWhere((x)=>x.leaveRequestId==leaveId);
          final leave=_leaveRequests.where((r)=>r.id==leaveId).firstOrNull;
          if(leave!=null){leave.status=LeaveRequestStatus.cancelled;leave.reviewedAt=DateTime.now();}
        }else{
          _planning.removeWhere((x)=>x.id==entryId);
        }
        _cancelReminder(entry.ownerPhone,entry.dateStr);
        _persist();notifyListeners();
      }
      return null;
    }catch(e){return 'Suppression impossible : $e';}
  }

  Future<String?> reviewAccount(String profileId,bool approve,{String? hospital,String? service,MedicalGrade? grade}) async {
    final me=currentUser;
    if(me==null||me.role!=UserRole.admin)return 'Action réservée à l’administrateur.';
    if(profileId==me.id)return 'Vous ne pouvez pas modifier votre propre statut.';
    try{
      if(backendEnabled){
        await SupabaseBackendService.instance.reviewAccount(profileId,approve?'approve':'suspend',hospital:hospital,service:service,grade:grade);
        await _reloadFromBackend();
        if (approve) {
          final approvedProfile = _users
              .where((u) => u.id == profileId && u.accountStatus == AccountStatus.active)
              .firstOrNull;
          if (approvedProfile != null) {
            try {
              final changed = await _syncOfficialRosterForProfile(approvedProfile);
              if (changed) await _reloadFromBackend();
            } catch (e) {
              // La validation reste acquise. Si le PDF est momentanément
              // indisponible, le médecin sera synchronisé à sa connexion.
              debugPrint('Synchronisation du nouveau médecin impossible: $e');
            }
          }
        }
      }else{
        return 'La validation des comptes nécessite Supabase.';
      }
      return null;
    }catch(e){return 'Validation du compte impossible : $e';}
  }

  DateTime _guardStart(String date,String shiftId){
    final shift=ShiftCatalog.byId(shiftId);
    final p=date.split('-').map(int.parse).toList(),s=shift.start!.split(':').map(int.parse).toList();
    return DateTime(p[0],p[1],p[2],s[0],s[1]);
  }

  List<ReminderNotification> _appendReminderInstances(String owner,String date,String shiftId){
    final shift=ShiftCatalog.byId(shiftId);if(!shift.hasSchedule)return const <ReminderNotification>[];
    final start=_guardStart(date,shiftId);
    final label='${shift.id.startsWith('urg')?'Urgences':'Service'} · ${shift.label}';
    final added=<ReminderNotification>[];
    for(final delay in _reminderDelays){
      final first=start.subtract(Duration(minutes:delay));
      final repeatLimit=_reminderSoundMode=='alarm'?0:_reminderRepeatCount;
      for(var repeat=0;repeat<=repeatLimit;repeat++){
        final fire=first.add(Duration(minutes:_reminderRepeatMinutes*repeat));
        if(!fire.isBefore(start))continue;
        final suffix=repeat==0?reminderDelayLabel(delay):'répétition $repeat';
        final r=ReminderNotification(
          id:'n${++_reminderCounter}',ownerPhone:owner,dateStr:date,label:'$label · $suffix',fireAt:fire,
          status:fire.isBefore(DateTime.now())?ReminderStatus.sent:ReminderStatus.upcoming,
        );
        _reminders.add(r);added.add(r);
      }
    }
    return added;
  }

  String _guardReminderBody(ReminderNotification reminder,PlanningEntry entry,ShiftType shift){
    final start=_guardStart(entry.dateStr,entry.shiftId);
    final fireDay=DateTime(reminder.fireAt.year,reminder.fireAt.month,reminder.fireAt.day);
    final guardDay=DateTime(start.year,start.month,start.day);
    final days=guardDay.difference(fireDay).inDays;
    late String when;
    if(days<=0){when=start.hour>=17?'ce soir':'aujourd’hui';}
    else if(days==1){when='demain';}
    else{when='dans $days jours';}
    final service=shift.id.startsWith('urg')?'Urgences':'Service';
    return 'Attention : garde $when à ${shift.start} · $service ${shift.label}.';
  }

  Future<void> _scheduleNativeReminder(ReminderNotification r) async{
    final me=currentUser;if(me==null||!_notificationsOn||r.ownerPhone!=me.phone||!r.fireAt.isAfter(DateTime.now()))return;
    final e=_planning.where((e)=>e.ownerPhone==me.phone&&e.dateStr==r.dateStr).firstOrNull;if(e==null||!isPlanningEntryApproved(e))return;
    final sh=ShiftCatalog.byId(e.shiftId);if(!sh.hasSchedule)return;
    await NotificationService.instance.scheduleReminder(
      ownerPhone:me.phone,dateStr:r.dateStr,notificationKey:'${e.id}|${e.shiftId}|${r.fireAt.millisecondsSinceEpoch}',title:'Attention · GardeFlow',
      body:_guardReminderBody(r,e,sh),fireAt:r.fireAt,soundMode:_reminderSoundMode,vibration:_reminderVibration,
    );
  }

  void _scheduleReminder(String owner,String date,String shiftId){
    final added=_appendReminderInstances(owner,date,shiftId);
    if(currentUser?.phone==owner&&_notificationsOn){for(final r in added){unawaited(_scheduleNativeReminder(r));}}
  }
  void _cancelReminder(String owner,String date){
    _reminders.removeWhere((r)=>r.ownerPhone==owner&&r.dateStr==date);
    unawaited(NotificationService.instance.cancelGuardReminders(owner,date));
  }

  Future<void> rescheduleAllReminders() async{
    final me=currentUser;if(me==null)return;
    await NotificationService.instance.cancelAll();
    _reminders.removeWhere((r)=>r.ownerPhone==me.phone);
    for(final e in _planning.where((e)=>e.ownerPhone==me.phone&&isPlanningEntryApproved(e))){_appendReminderInstances(me.phone,e.dateStr,e.shiftId);}
    await _persistNow();
    await _activateNativeRemindersForCurrentUser(cancelExisting:false);
    notifyListeners();
  }

  Future<void> _activateNativeRemindersForCurrentUser({bool cancelExisting=true}) async{
    final me=currentUser;
    if(cancelExisting)await NotificationService.instance.cancelAll();
    if(me==null||!_notificationsOn)return;
    final upcoming=_reminders.where((r)=>r.ownerPhone==me.phone&&r.fireAt.isAfter(DateTime.now())).toList()..sort((a,b)=>a.fireAt.compareTo(b.fireAt));
    final limit=!kIsWeb&&defaultTargetPlatform==TargetPlatform.iOS?56:96;
    for(final r in upcoming.take(limit)){await _scheduleNativeReminder(r);}
  }
  void _refreshReminderStatuses(){for(final r in _reminders){if(r.fireAt.isBefore(DateTime.now()))r.status=ReminderStatus.sent;}}
  int get upcomingRemindersCount{_refreshReminderStatuses();final me=currentUser;if(me==null)return 0;return _reminders.where((r)=>r.ownerPhone==me.phone&&r.status==ReminderStatus.upcoming).length;}
  void clearSentReminders(){final me=currentUser;if(me==null)return;_refreshReminderStatuses();_reminders.removeWhere((r)=>r.ownerPhone==me.phone&&r.status==ReminderStatus.sent);_persist();notifyListeners();}

  bool _isActiveRequest(ExchangeRequest x)=>
      x.status==ExchangeStatus.pendingB||x.status==ExchangeStatus.pendingAdmin;

  bool _isEntryLocked(String entryId)=>_exchanges.any((x)=>
      _isActiveRequest(x)&&(x.planningEntryId==entryId||x.targetPlanningEntryId==entryId));

  List<DirectoryContact> exchangeTargets({bool sameServiceOnly=false}){
    final me=currentUser;if(me==null)return[];

    // Les admins restent des médecins participants au planning : ils peuvent
    // donc recevoir/proposer un transfert ou un échange comme les autres.
    // La restriction d'établissement reste inchangée.
    final result=<DirectoryContact>[];
    final seen=<String>{};
    for(final u in _users){
      if(u.id==me.id||u.phone==me.phone||u.accountStatus!=AccountStatus.active)continue;
      if(BusinessRules.sameHospitalRequired&&u.hospital!=me.hospital)continue;
      if((sameServiceOnly||BusinessRules.sameServiceRequiredForExchange)&&u.service!=me.service)continue;
      if(BusinessRules.sameGradeRequiredForExchange&&u.grade!=me.grade)continue;
      if(!seen.add(u.id))continue;
      result.add(DirectoryContact(
        id:u.id,name:u.fullName,phone:u.phone,hospital:u.hospital,
        service:u.service,gradeLabel:u.gradeLabel,isAdmin:u.role==UserRole.admin,
      ));
    }
    result.sort((a,b)=>a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  List<PlanningEntry> exchangeableEntriesFor(String phone, {String? excludingDate, bool serviceOnly=false}){
    // Une garde du même jour reste échangeable (ex. Jour ↔ Nuit le 26/09).
    // excludingDate est conservé dans la signature pour compatibilité UI, mais
    // n'est plus utilisé pour filtrer les gardes cibles.
    final result=_planning.where((e)=>(e.ownerId==phone||e.ownerPhone==phone)&&!e.isDisciplinary&&ShiftCatalog.byId(e.shiftId).hasSchedule&&(!serviceOnly||e.shiftId.startsWith('service-'))&&isPlanningEntryApproved(e)&&!_isEntryLocked(e.id)&&!_guardHasStarted(e)).toList();
    result.sort((a,b)=>a.dateStr.compareTo(b.dateStr));
    return result;
  }

  Future<String?> createTransferRequest(String date,PlanningEntry entry,DirectoryContact target) async {
    final me=currentUser;if(me==null)return 'Session expirée.';
    if(entry.ownerId!=me.id&&entry.ownerPhone!=me.phone)return 'Cette garde ne vous appartient plus.';
    if(entry.isDisciplinary)return 'Une garde disciplinaire ne peut être ni transférée ni échangée.';
    if(!isPlanningEntryApproved(entry))return 'Votre calendrier doit être validé avant un transfert ou un échange.';
    if(entry.dateStr!=date)return 'La date de la garde est incohérente.';
    if(_guardHasStarted(entry))return 'Une garde commencée ou passée ne peut plus être transférée.';
    if(BusinessRules.sameHospitalRequired&&target.hospital!=me.hospital)return 'Les transferts sont limités au même établissement.';
    if(!isUserPlanningMonthApproved(target.id,date))return 'Le calendrier du destinataire doit aussi être validé pour ce mois.';
    if(_isEntryLocked(entry.id))return 'Une demande est déjà en cours pour cette garde.';
    if(_planning.any((e)=>e.dateStr==date&&(e.ownerId==target.id||e.ownerPhone==target.phone)))return '${target.name} a déjà une affectation ce jour-là.';
    final ex=ExchangeRequest(
      id:backendEnabled?'ex${DateTime.now().microsecondsSinceEpoch}':'ex${++_exchangeCounter}',type:ShiftRequestType.transfer,
      planningEntryId:entry.id,dateStr:date,shiftId:entry.shiftId,
      fromId:me.id,fromPhone:me.phone,fromName:me.fullName,
      toId:target.id,toPhone:target.phone,toName:target.name);
    if(backendEnabled){
      try{await SupabaseBackendService.instance.createRequest(ex);_firePush('exchange_created', ex.id);}catch(e){return 'Envoi impossible : $e';}
    }
    _exchanges.add(ex);_persist();notifyListeners();return null;
  }

  Future<String?> createSwapRequest(String date,PlanningEntry entry,DirectoryContact target,PlanningEntry targetEntry) async {
    final me=currentUser;if(me==null)return 'Session expirée.';
    if(entry.ownerId!=me.id&&entry.ownerPhone!=me.phone)return 'Cette garde ne vous appartient plus.';
    if(entry.isDisciplinary||targetEntry.isDisciplinary)return 'Une garde disciplinaire ne peut être ni transférée ni échangée.';
    if(!isPlanningEntryApproved(entry)||!isPlanningEntryApproved(targetEntry))return 'Les deux calendriers doivent être validés avant un échange.';
    if(_guardHasStarted(entry))return 'Une garde commencée ou passée ne peut plus être échangée.';
    if(_guardHasStarted(targetEntry))return 'La garde choisie est déjà commencée ou passée.';
    if(BusinessRules.sameHospitalRequired&&target.hospital!=me.hospital)return 'Les échanges sont limités au même établissement.';
    final sourceIsService=entry.shiftId.startsWith('service-');
    final targetIsService=targetEntry.shiftId.startsWith('service-');
    if((sourceIsService||targetIsService)&&target.service!=me.service){
      return 'Toute garde de Service ne peut être échangée qu’entre médecins du même service.';
    }
    if(targetEntry.ownerId!=target.id&&targetEntry.ownerPhone!=target.phone)return 'La garde choisie n’appartient plus au médecin destinataire.';
    if(!isUserPlanningMonthApproved(me.id,targetEntry.dateStr)||!isUserPlanningMonthApproved(target.id,entry.dateStr))return 'Les mois de destination des deux médecins doivent aussi être validés.';
    if(entry.id==targetEntry.id)return 'Choisissez deux gardes distinctes.';
    if(_isEntryLocked(entry.id)||_isEntryLocked(targetEntry.id))return 'Une des deux gardes est déjà engagée dans une demande.';
    final targetConflict=_planning.where((e)=>e.dateStr==entry.dateStr&&(e.ownerId==target.id||e.ownerPhone==target.phone)).firstOrNull;
    if(targetConflict!=null&&targetConflict.id!=targetEntry.id)return '${target.name} a déjà une autre affectation le ${entry.dateStr}.';
    final sourceConflict=_planning.where((e)=>e.dateStr==targetEntry.dateStr&&(e.ownerId==me.id||e.ownerPhone==me.phone)).firstOrNull;
    if(sourceConflict!=null&&sourceConflict.id!=entry.id)return 'Vous avez déjà une autre affectation le ${targetEntry.dateStr}.';
    final ex=ExchangeRequest(
      id:backendEnabled?'ex${DateTime.now().microsecondsSinceEpoch}':'ex${++_exchangeCounter}',type:ShiftRequestType.exchange,
      planningEntryId:entry.id,dateStr:entry.dateStr,shiftId:entry.shiftId,
      targetPlanningEntryId:targetEntry.id,targetDateStr:targetEntry.dateStr,targetShiftId:targetEntry.shiftId,
      fromId:me.id,fromPhone:me.phone,fromName:me.fullName,
      toId:target.id,toPhone:target.phone,toName:target.name);
    if(backendEnabled){
      try{await SupabaseBackendService.instance.createRequest(ex);_firePush('exchange_created', ex.id);}catch(e){return 'Envoi impossible : $e';}
    }
    _exchanges.add(ex);_persist();notifyListeners();return null;
  }

  Future<String?> createExchangeRequest(String date,PlanningEntry entry,DirectoryContact target)=>
      createTransferRequest(date,entry,target);

  String? _validateRequestState(ExchangeRequest ex){
    final source=_planning.where((e)=>e.id==ex.planningEntryId).firstOrNull;
    if(source==null||(source.ownerId!=ex.fromId&&source.ownerPhone!=ex.fromPhone))return 'La garde proposée a été modifiée ou supprimée.';
    if(source.isDisciplinary)return 'La garde proposée est disciplinaire et ne peut pas être transférée ou échangée.';
    if(!isPlanningEntryApproved(source))return 'Le calendrier de la garde source n’est pas validé.';
    if(_guardHasStarted(source))return 'La garde proposée est déjà commencée ou passée.';
    if(ex.isTransfer){
      if(!isUserPlanningMonthApproved(ex.toId,ex.dateStr))return 'Le calendrier du destinataire n’est pas validé pour ce mois.';
      final conflict=_planning.where((e)=>e.dateStr==ex.dateStr&&(e.ownerId==ex.toId||e.ownerPhone==ex.toPhone)).firstOrNull;
      if(conflict!=null)return '${ex.toName} a déjà une affectation ce jour-là.';
      return null;
    }
    final targetId=ex.targetPlanningEntryId;
    if(targetId==null)return 'La deuxième garde de l’échange est introuvable.';
    final target=_planning.where((e)=>e.id==targetId).firstOrNull;
    if(target==null||(target.ownerId!=ex.toId&&target.ownerPhone!=ex.toPhone))return 'La garde de ${ex.toName} a été modifiée ou supprimée.';
    if(target.isDisciplinary)return 'La garde de ${ex.toName} est disciplinaire et ne peut pas être échangée.';
    if(!isPlanningEntryApproved(target))return 'Le calendrier de ${ex.toName} n’est pas validé.';
    if(!isUserPlanningMonthApproved(ex.fromId,target.dateStr)||!isUserPlanningMonthApproved(ex.toId,source.dateStr))return 'Les mois de destination ne sont pas tous validés.';
    if(_guardHasStarted(target))return 'La garde de ${ex.toName} est déjà commencée ou passée.';
    final fromUser=_users.where((u)=>u.id==ex.fromId||u.phone==ex.fromPhone).firstOrNull;
    final toUser=_users.where((u)=>u.id==ex.toId||u.phone==ex.toPhone).firstOrNull;
    if(fromUser==null||toUser==null)return 'Un des médecins participant à l’échange est introuvable.';
    if(BusinessRules.sameHospitalRequired&&fromUser.hospital!=toUser.hospital)return 'Les échanges sont limités aux médecins du même établissement.';
    final involvesService=source.shiftId.startsWith('service-')||target.shiftId.startsWith('service-');
    if(involvesService&&fromUser.service!=toUser.service)return 'Toute garde de Service ne peut être échangée qu’entre médecins du même service.';
    final conflictTo=_planning.where((e)=>e.dateStr==source.dateStr&&(e.ownerId==ex.toId||e.ownerPhone==ex.toPhone)).firstOrNull;
    if(conflictTo!=null&&conflictTo.id!=target.id)return '${ex.toName} a déjà une autre affectation le ${source.dateStr}.';
    final conflictFrom=_planning.where((e)=>e.dateStr==target.dateStr&&(e.ownerId==ex.fromId||e.ownerPhone==ex.fromPhone)).firstOrNull;
    if(conflictFrom!=null&&conflictFrom.id!=source.id)return '${ex.fromName} a déjà une autre affectation le ${target.dateStr}.';
    return null;
  }

  bool _isSameServiceExchange(ExchangeRequest ex){
    if(!ex.isServiceExchange)return false;
    final from=_users.where((u)=>u.id==ex.fromId||u.phone==ex.fromPhone).firstOrNull;
    final to=_users.where((u)=>u.id==ex.toId||u.phone==ex.toPhone).firstOrNull;
    return from!=null&&to!=null&&from.service==to.service;
  }

  Future<String?> acceptExchange(String id) async {
    final me=currentUser,ex=_exchanges.where((e)=>e.id==id).firstOrNull;
    if(me==null||ex==null||(ex.toId!=me.id&&ex.toPhone!=me.phone)||ex.status!=ExchangeStatus.pendingB)return 'Cette demande n’est plus disponible.';
    final err=_validateRequestState(ex);if(err!=null)return err;
    if(backendEnabled){
      try{
        await SupabaseBackendService.instance.respondRequest(id,'accept');
        _firePush('exchange_accepted', id);
        await _reloadFromBackend();
        // Pour un échange 100 % Service, l'acceptation du destinataire applique
        // immédiatement l'échange côté serveur : aucune validation admin.
        if(_isSameServiceExchange(ex))rescheduleAllReminders();
        return null;
      }catch(e){return 'Acceptation impossible : $e';}
    }
    if(_isSameServiceExchange(ex)){
      final source=_planning.where((e)=>e.id==ex.planningEntryId).firstOrNull;
      final target=_planning.where((e)=>e.id==ex.targetPlanningEntryId).firstOrNull;
      if(source==null||target==null)return 'Une des deux gardes est introuvable.';
      final sourceDate=source.dateStr;
      final sourceShift=source.shiftId;
      final targetDate=target.dateStr;
      final targetShift=target.shiftId;
      _cancelReminder(ex.fromPhone,sourceDate);
      _cancelReminder(ex.toPhone,targetDate);
      source.dateStr=targetDate;
      source.shiftId=targetShift;
      target.dateStr=sourceDate;
      target.shiftId=sourceShift;
      _scheduleReminder(ex.fromPhone,source.dateStr,source.shiftId);
      _scheduleReminder(ex.toPhone,target.dateStr,target.shiftId);
      ex.status=ExchangeStatus.approved;
    }else{
      ex.status=ExchangeStatus.pendingAdmin;
    }
    _persist();notifyListeners();return null;
  }

  Future<String?> declineExchange(String id) async {
    final me=currentUser,ex=_exchanges.where((e)=>e.id==id).firstOrNull;
    if(me==null||ex==null||(ex.toId!=me.id&&ex.toPhone!=me.phone)||ex.status!=ExchangeStatus.pendingB)return 'Cette demande n’est plus disponible.';
    if(backendEnabled){
      try{await SupabaseBackendService.instance.respondRequest(id,'decline');_firePush('exchange_declined', id);await _reloadFromBackend();return null;}
      catch(e){return 'Refus impossible : $e';}
    }
    _updateExchange(id,ExchangeStatus.declinedB);return null;
  }

  Future<String?> rejectExchange(String id) async {
    final me=currentUser,ex=_exchanges.where((e)=>e.id==id).firstOrNull;
    if(me?.role!=UserRole.admin||ex==null||ex.status!=ExchangeStatus.pendingAdmin)return 'Validation impossible.';
    if(ex.fromId==me!.id||ex.toId==me.id||ex.fromPhone==me.phone||ex.toPhone==me.phone)return 'Un administrateur participant à la demande ne peut pas la valider.';
    if(backendEnabled){
      try{await SupabaseBackendService.instance.reviewRequest(id,'reject');_firePush('exchange_reviewed', id);await _reloadFromBackend();return null;}
      catch(e){return 'Rejet impossible : $e';}
    }
    _updateExchange(id,ExchangeStatus.rejectedAdmin);return null;
  }

  Future<String?> approveExchange(String id) async {
    final me=currentUser,ex=_exchanges.where((e)=>e.id==id).firstOrNull;
    if(me?.role!=UserRole.admin||ex==null||ex.status!=ExchangeStatus.pendingAdmin)return 'Validation impossible.';
    if(ex.fromId==me!.id||ex.toId==me.id||ex.fromPhone==me.phone||ex.toPhone==me.phone)return 'Un administrateur participant à la demande ne peut pas la valider.';
    final err=_validateRequestState(ex);if(err!=null)return err;
    if(backendEnabled){
      try{
        await SupabaseBackendService.instance.reviewRequest(id,'approve');
        _firePush('exchange_reviewed', id);
        await _reloadFromBackend();
        rescheduleAllReminders();
        return null;
      }catch(e){return 'Approbation impossible : $e';}
    }
    final source=_planning.where((e)=>e.id==ex.planningEntryId).first;
    if(ex.isTransfer){
      _cancelReminder(ex.fromPhone,source.dateStr);
      source.ownerId=ex.toId;source.ownerPhone=ex.toPhone;source.ownerName=ex.toName;
      _scheduleReminder(ex.toPhone,source.dateStr,source.shiftId);
    }else{
      final target=_planning.where((e)=>e.id==ex.targetPlanningEntryId).first;
      final sourceDate=source.dateStr;
      final sourceShift=source.shiftId;
      final targetDate=target.dateStr;
      final targetShift=target.shiftId;
      _cancelReminder(ex.fromPhone,sourceDate);
      _cancelReminder(ex.toPhone,targetDate);

      // Chaque médecin conserve sa propre ligne de planning. Pour un échange,
      // on échange la garde elle-même (date + type), pas les propriétaires.
      // Cela rend notamment robuste un échange Jour 16 ↔ Nuit 27.
      source.dateStr=targetDate;
      source.shiftId=targetShift;
      target.dateStr=sourceDate;
      target.shiftId=sourceShift;

      _scheduleReminder(ex.fromPhone,source.dateStr,source.shiftId);
      _scheduleReminder(ex.toPhone,target.dateStr,target.shiftId);
    }
    ex.status=ExchangeStatus.approved;_persist();notifyListeners();return null;
  }

  Future<String?> cancelExchange(String id) async {
    final me=currentUser,ex=_exchanges.where((e)=>e.id==id).firstOrNull;
    if(me==null||ex==null||(ex.fromId!=me.id&&ex.fromPhone!=me.phone)||ex.status!=ExchangeStatus.pendingB)return 'Annulation impossible.';
    if(backendEnabled){
      try{await SupabaseBackendService.instance.cancelRequest(id);_firePush('exchange_cancelled', id);await _reloadFromBackend();return null;}
      catch(e){return 'Annulation impossible : $e';}
    }
    ex.status=ExchangeStatus.cancelled;_persist();notifyListeners();return null;
  }
  void _updateExchange(String id,ExchangeStatus status){
    final ex=_exchanges.where((e)=>e.id==id).firstOrNull;if(ex==null)return;
    ex.status=status;_persist();notifyListeners();
  }
  int exchangeActionableCount(){
    final me=currentUser;if(me==null)return 0;
    return _exchanges.where((e)=>
      (e.status==ExchangeStatus.pendingB&&(e.toId==me.id||e.toPhone==me.phone))||
      (e.status==ExchangeStatus.pendingAdmin&&me.role==UserRole.admin&&e.fromId!=me.id&&e.toId!=me.id&&e.fromPhone!=me.phone&&e.toPhone!=me.phone)).length;
  }
  int leaveActionableCount(){final me=currentUser;if(me==null||me.role!=UserRole.admin)return 0;return _leaveRequests.where((r)=>r.status==LeaveRequestStatus.pendingAdmin&&r.ownerId!=me.id&&r.ownerPhone!=me.phone).length;}
  int get accountActionableCount{final me=currentUser;if(me==null||me.role!=UserRole.admin)return 0;return pendingUsers.length+_passwordResetRequests.length;}
  int get totalBadgeCount=>exchangeActionableCount()+leaveActionableCount()+accountActionableCount;

  final Set<String> _dismissedNotificationKeys=<String>{};
  String _scopedNotificationKey(String key){
    final me=currentUser;
    final owner=me==null?'anonymous':(me.id.isNotEmpty?me.id:me.phone);
    return '$owner::$key';
  }
  bool isNotificationDismissed(String key)=>_dismissedNotificationKeys.contains(_scopedNotificationKey(key));

  void clearReadAndPastNotifications(){
    final me=currentUser;if(me==null)return;
    _refreshReminderStatuses();
    _reminders.removeWhere((r)=>r.ownerPhone==me.phone&&r.status==ReminderStatus.sent);
    for(final e in _exchanges){
      final relevant=me.role==UserRole.admin||e.fromId==me.id||e.toId==me.id||e.fromPhone==me.phone||e.toPhone==me.phone;
      final terminal=e.status==ExchangeStatus.approved||e.status==ExchangeStatus.declinedB||e.status==ExchangeStatus.rejectedAdmin||e.status==ExchangeStatus.cancelled;
      if(relevant&&terminal)_dismissedNotificationKeys.add(_scopedNotificationKey('exchange:${e.id}'));
    }
    for(final r in _leaveRequests){
      final relevant=me.role==UserRole.admin||r.ownerId==me.id||r.ownerPhone==me.phone;
      if(relevant&&r.status!=LeaveRequestStatus.pendingAdmin)_dismissedNotificationKeys.add(_scopedNotificationKey('leave:${r.id}'));
    }
    _persist();notifyListeners();
  }

  Map<String,dynamic> _toJson()=>{
    'users':_users.map((e)=>e.toJson()).toList(),'planning':_planning.map((e)=>e.toJson()).toList(),
    'astreinte':_astreinte.map((e)=>e.toJson()).toList(),'reminders':_reminders.map((e)=>e.toJson()).toList(),
    'manualDirectoryContacts':_manualDirectoryContacts.map((e)=>e.toJson()).toList(),
    'exchanges':_exchanges.map((e)=>e.toJson()).toList(),'leaveRequests':_leaveRequests.map((e)=>e.toJson()).toList(),'planningMonths':_planningMonths.map((e)=>e.toJson()).toList(),'dismissedNotifications':_dismissedNotificationKeys.toList(),'delayMinutes':_delayMinutes,'notificationsOn':_notificationsOn,'reminderPrefsByUser':_reminderPrefsByUser,
    'planningCounter':_planningCounter,'exchangeCounter':_exchangeCounter,'leaveCounter':_leaveCounter,'reminderCounter':_reminderCounter,'appearanceTheme':_appearanceTheme,'darkMode':darkMode,'darkDefaultAppliedV58':true,
  };
  void _restore(Map<String,dynamic> j){
    try{_users.addAll((j['users'] as List? ?? []).map((e)=>AppUser.fromJson(Map<String,dynamic>.from(e))));}catch(_){}
    try{_planning.addAll((j['planning'] as List? ?? []).map((e)=>PlanningEntry.fromJson(Map<String,dynamic>.from(e))));}catch(_){}
    try{_astreinte.addAll((j['astreinte'] as List? ?? []).map((e)=>AstreintePhoto.fromJson(Map<String,dynamic>.from(e))));}catch(_){}
    try{_reminders.addAll((j['reminders'] as List? ?? []).map((e)=>ReminderNotification.fromJson(Map<String,dynamic>.from(e))));}catch(_){}
    try{_manualDirectoryContacts.addAll((j['manualDirectoryContacts'] as List? ?? []).map((e)=>DirectoryContact.fromJson(Map<String,dynamic>.from(e))));}catch(_){}
    try{_exchanges.addAll((j['exchanges'] as List? ?? []).map((e)=>ExchangeRequest.fromJson(Map<String,dynamic>.from(e))));}catch(_){}
    try{_leaveRequests.addAll((j['leaveRequests'] as List? ?? []).map((e)=>LeaveRequest.fromJson(Map<String,dynamic>.from(e))));}catch(_){}
    try{_planningMonths.addAll((j['planningMonths'] as List? ?? []).map((e)=>PlanningMonth.fromJson(Map<String,dynamic>.from(e))));}catch(_){}
    for(final p in _planningMonths){
      if(p.status==PlanningMonthStatus.submitted||p.status==PlanningMonthStatus.rejected){
        p.status=PlanningMonthStatus.draft;p.reviewedAt=null;p.reviewedBy=null;p.rejectionReason=null;
      }
    }
    try{_dismissedNotificationKeys.addAll((j['dismissedNotifications'] as List? ?? []).map((e)=>e.toString()));}catch(_){}
    if(_planningMonths.isEmpty&&_planning.isNotEmpty){
      final seen=<String>{};
      for(final e in _planning){
        final d=DateTime.tryParse(e.dateStr);if(d==null)continue;
        final key='${e.ownerId}-${d.year}-${d.month}';
        if(seen.add(key))_planningMonths.add(PlanningMonth(ownerId:e.ownerId,year:d.year,month:d.month,status:PlanningMonthStatus.approved));
      }
    }
    _delayMinutes=(j['delayMinutes'] as num?)?.toInt()??60;_notificationsOn=j['notificationsOn'] as bool? ?? true;final storedAppearanceTheme=j['appearanceTheme']?.toString();_appearanceTheme=const <String>{'green','red','white','black'}.contains(storedAppearanceTheme)?storedAppearanceTheme!:'green';
    try{
      final raw=Map<String,dynamic>.from(j['reminderPrefsByUser'] as Map? ?? const <String,dynamic>{});
      for(final item in raw.entries){_reminderPrefsByUser[item.key]=Map<String,dynamic>.from(item.value as Map);}
    }catch(_){}
    _planningCounter=(j['planningCounter'] as num?)?.toInt()??_planning.length;_exchangeCounter=(j['exchangeCounter'] as num?)?.toInt()??_exchanges.length;_leaveCounter=(j['leaveCounter'] as num?)?.toInt()??_leaveRequests.length;_reminderCounter=(j['reminderCounter'] as num?)?.toInt()??_reminders.length;
  }
  void _persist()=>unawaited(_persistNow());
  Future<void> _persistNow()=>LocalStorageService.saveState(_toJson());
}

extension _FirstOrNull<T> on Iterable<T>{T? get firstOrNull=>isEmpty?null:first;}
