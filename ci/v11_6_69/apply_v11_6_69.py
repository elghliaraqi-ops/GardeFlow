from pathlib import Path

def replace_once(path, old, new, label):
    p=Path(path)
    s=p.read_text()
    if old not in s:
        raise SystemExit(f'V11.6.69: {label} anchor missing in {path}')
    p.write_text(s.replace(old,new,1))
    print(f'V11.6.69: {label} applied')

replace_once('pubspec.yaml','version: 11.6.68+228','version: 11.6.69+229','version bump')

Path('lib/models/password_reset_request.dart').write_text('''class PasswordResetRequest {
  final String id;
  final String profileId;
  final DateTime requestedAt;
  final String fullName;
  final String phone;
  final String hospital;
  final String service;
  final String gradeLabel;

  const PasswordResetRequest({
    required this.id,
    required this.profileId,
    required this.requestedAt,
    required this.fullName,
    required this.phone,
    required this.hospital,
    required this.service,
    required this.gradeLabel,
  });

  factory PasswordResetRequest.fromJson(Map<String, dynamic> json) {
    return PasswordResetRequest(
      id: json['request_id'].toString(),
      profileId: json['profile_id'].toString(),
      requestedAt: DateTime.parse(json['requested_at'].toString()),
      fullName: (json['full_name'] as String?)?.trim() ?? '',
      phone: (json['phone'] as String?) ?? '',
      hospital: (json['hospital'] as String?) ?? '',
      service: (json['service'] as String?) ?? '',
      gradeLabel: (json['grade_label'] as String?) ?? 'Médecin',
    );
  }
}
''')
print('V11.6.69: password reset request model created')

replace_once(
  'lib/services/supabase_backend_service.dart',
  "import '../models/planning_month.dart';\nimport '../models/shared_resource.dart';",
  "import '../models/planning_month.dart';\nimport '../models/password_reset_request.dart';\nimport '../models/shared_resource.dart';",
  'backend password reset model import',
)

replace_once(
  'lib/services/supabase_backend_service.dart',
  """  Future<List<AppUser>> fetchVisibleProfiles() async {
    final rows = await client.from('profiles').select().order('prenom').order('nom');
    return (rows as List).map((e) => _profileToUser(Map<String, dynamic>.from(e))).toList();
  }

  Future<List<DirectoryContact>> fetchManualDirectoryContacts() async {""",
  """  Future<List<AppUser>> fetchVisibleProfiles() async {
    final rows = await client
        .from('profiles')
        .select('id,nom,prenom,phone,role,service,medical_grade,hospital,account_status')
        .order('prenom')
        .order('nom');
    return (rows as List).map((e) => _profileToUser(Map<String, dynamic>.from(e))).toList();
  }

  Future<List<PasswordResetRequest>> fetchPasswordResetRequests() async {
    final rows = await client.rpc('admin_password_reset_requests');
    return (rows as List)
        .map((raw) => PasswordResetRequest.fromJson(Map<String, dynamic>.from(raw as Map)))
        .toList(growable: false);
  }

  Future<List<DirectoryContact>> fetchManualDirectoryContacts() async {""",
  'backend admin password reset requests',
)

replace_once(
  'lib/services/supabase_backend_service.dart',
  ".from('planning_entries')\n        .select()\n        .isFilter('deleted_at', null)",
  ".from('planning_entries')\n        .select('id,date_str,shift_id,owner_id,owner_phone,owner_name,leave_request_id,is_disciplinary,created_at')\n        .isFilter('deleted_at', null)",
  'planning selected columns',
)
replace_once(
  'lib/services/supabase_backend_service.dart',
  ".from('planning_months')\n        .select()\n        .order('year')",
  ".from('planning_months')\n        .select('owner_id,year,month,status,submitted_at,reviewed_at,reviewed_by,rejection_reason')\n        .order('year')",
  'planning months selected columns',
)
replace_once(
  'lib/services/supabase_backend_service.dart',
  "final rows = await client.from('exchange_requests').select().order('created_at');",
  "final rows = await client.from('exchange_requests').select('id,type,planning_entry_id,date_str,shift_id,target_planning_entry_id,target_date_str,target_shift_id,from_id,from_phone,from_name,to_id,to_phone,to_name,status,created_at').order('created_at');",
  'exchange selected columns',
)
replace_once(
  'lib/services/supabase_backend_service.dart',
  "final rows = await client.from('leave_requests').select().order('created_at');",
  "final rows = await client.from('leave_requests').select('id,start_date,end_date,date_str,owner_id,owner_phone,owner_name,status,created_at,reviewed_at').order('created_at');",
  'leave selected columns',
)

replace_once(
  'lib/state/app_state.dart',
  "import '../models/planning_month.dart';\nimport '../models/reminder_notification.dart';",
  "import '../models/planning_month.dart';\nimport '../models/password_reset_request.dart';\nimport '../models/reminder_notification.dart';",
  'app state password reset import',
)

replace_once(
  'lib/state/app_state.dart',
  """  StreamSubscription? _profileRealtime;
  StreamSubscription? _directoryRealtime;
  int _sessionEpoch = 0;""",
  """  StreamSubscription? _profileRealtime;
  StreamSubscription? _directoryRealtime;
  StreamSubscription? _passwordResetRealtime;
  Timer? _realtimeReloadTimer;
  bool _realtimeNeedsOfficialSync = false;
  int _sessionEpoch = 0;""",
  'realtime debounce fields',
)

replace_once(
  'lib/state/app_state.dart',
  """    final backend = SupabaseBackendService.instance;
    final profiles = await backend.fetchVisibleProfiles();
    final planning = await backend.fetchPlanning();
    final planningMonths = await backend.fetchPlanningMonths();
    final exchanges = await backend.fetchExchanges();
    final leaves = await backend.fetchLeaveRequests();
    List<DirectoryContact> manualDirectoryContacts = const [];
    try {
      manualDirectoryContacts = await backend.fetchManualDirectoryContacts();
    } catch (e) {
      debugPrint('Annuaire manuel indisponible: $e');
    }""",
  """    final backend = SupabaseBackendService.instance;

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
    }""",
  'parallel backend reload',
)

replace_once(
  'lib/state/app_state.dart',
  """    _leaveRequests
      ..clear()
      ..addAll(leaves);
    _manualDirectoryContacts""",
  """    _leaveRequests
      ..clear()
      ..addAll(leaves);
    _passwordResetRequests
      ..clear()
      ..addAll(passwordResetRequests);
    _manualDirectoryContacts""",
  'store password reset requests',
)

replace_once(
  'lib/state/app_state.dart',
  """  void _startRealtime() {
    if (!backendEnabled || currentUser == null) return;
    _planningRealtime?.cancel();
    _planningMonthRealtime?.cancel();
    _exchangeRealtime?.cancel();
    _leaveRealtime?.cancel();
    _profileRealtime?.cancel();
    _directoryRealtime?.cancel();
    final client=SupabaseBackendService.instance.client;
    _planningRealtime=client.from('planning_entries').stream(primaryKey:['id']).listen((_)=>unawaited(_reloadFromBackend()));
    _planningMonthRealtime=client.from('planning_months').stream(primaryKey:['owner_id','year','month']).listen((_)=>unawaited(_reloadFromBackend()));
    _exchangeRealtime=client.from('exchange_requests').stream(primaryKey:['id']).listen((_)=>unawaited(_reloadFromBackend()));
    _leaveRealtime=client.from('leave_requests').stream(primaryKey:['id']).listen((_)=>unawaited(_reloadFromBackend()));
    _profileRealtime=client.from('profiles').stream(primaryKey:['id']).listen((_)=>unawaited(_reloadAndSyncMyOfficialRoster()));
    _directoryRealtime=client.from('directory_contacts').stream(primaryKey:['id']).listen((_)=>unawaited(_reloadFromBackend()), onError: (Object e)=>debugPrint('Realtime annuaire indisponible: $e'));
  }

  void _stopRealtime(){_planningRealtime?.cancel();_planningMonthRealtime?.cancel();_exchangeRealtime?.cancel();_leaveRealtime?.cancel();_profileRealtime?.cancel();_directoryRealtime?.cancel();_planningRealtime=null;_planningMonthRealtime=null;_exchangeRealtime=null;_leaveRealtime=null;_profileRealtime=null;_directoryRealtime=null;}""",
  """  void _scheduleRealtimeReload({bool syncOfficialRoster = false}) {
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
  }""",
  'debounced realtime reloads',
)

replace_once(
  'lib/state/app_state.dart',
  """  final List<LeaveRequest> _leaveRequests=[];
  List<LeaveRequest> get leaveRequests=>List.unmodifiable(_leaveRequests);
  int _exchangeCounter=0,_leaveCounter=0,_reminderCounter=0;""",
  """  final List<LeaveRequest> _leaveRequests=[];
  List<LeaveRequest> get leaveRequests=>List.unmodifiable(_leaveRequests);
  final List<PasswordResetRequest> _passwordResetRequests=[];
  List<PasswordResetRequest> get passwordResetRequests=>List.unmodifiable(_passwordResetRequests);
  int _exchangeCounter=0,_leaveCounter=0,_reminderCounter=0;""",
  'password reset request state list',
)

replace_once(
  'lib/state/app_state.dart',
  "int get accountActionableCount{final me=currentUser;if(me==null||me.role!=UserRole.admin)return 0;return pendingUsers.length;}",
  "int get accountActionableCount{final me=currentUser;if(me==null||me.role!=UserRole.admin)return 0;return pendingUsers.length+_passwordResetRequests.length;}",
  'account badge includes password resets',
)

replace_once(
  'lib/services/push_notification_service.dart',
  "import '../screens/admin_screen.dart';\nimport '../screens/notifications_screen.dart';",
  "import '../screens/notifications_screen.dart';",
  'remove admin screen push import',
)
replace_once(
  'lib/services/push_notification_service.dart',
  """    final page = kind == 'account_created' && _isAdmin
        ? const AdminScreen()
        : NotificationsScreen(initialIndex: kind.startsWith('exchange_') ? 1 : kind.startsWith('leave_') ? 2 : 0);
    huimNavigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => page));""",
  """    final isAccountNotification =
        kind == 'account_created' || kind == 'password_reset_request';
    final initialIndex = kind.startsWith('exchange_')
        ? 1
        : kind.startsWith('leave_')
            ? 2
            : (isAccountNotification && _isAdmin ? 3 : 0);
    huimNavigatorKey.currentState!.push(
      MaterialPageRoute(
        builder: (_) => NotificationsScreen(initialIndex: initialIndex),
      ),
    );""",
  'account push navigation',
)

replace_once(
  'lib/screens/admin_password_reset_screen.dart',
  """class AdminPasswordResetScreen extends StatefulWidget {
  const AdminPasswordResetScreen({super.key});""",
  """class AdminPasswordResetScreen extends StatefulWidget {
  final String? initialUserId;
  const AdminPasswordResetScreen({super.key, this.initialUserId});""",
  'admin reset initial user parameter',
)
replace_once(
  'lib/screens/admin_password_reset_screen.dart',
  """  String? _error;
  String _query = '';""",
  """  String? _error;
  String _query = '';
  bool _openedInitialUser = false;""",
  'admin reset initial state flag',
)
replace_once(
  'lib/screens/admin_password_reset_screen.dart',
  """      setState(() {
        _profiles = doctors;
        _loading = false;
        _error = null;
      });
    } catch (e) {""",
  """      setState(() {
        _profiles = doctors;
        _loading = false;
        _error = null;
      });
      final initialUserId = widget.initialUserId;
      if (!_openedInitialUser && initialUserId != null) {
        final initialProfile = doctors.where((p) => p.id == initialUserId).firstOrNull;
        if (initialProfile != null) {
          _openedInitialUser = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _resetFor(initialProfile);
          });
        }
      }
    } catch (e) {""",
  'auto open requested password reset',
)

replace_once(
  'lib/screens/notifications_screen.dart',
  """import '../models/leave_request.dart';
import '../models/reminder_notification.dart';""",
  """import '../models/leave_request.dart';
import '../models/password_reset_request.dart';
import '../models/reminder_notification.dart';""",
  'notifications password reset model import',
)
replace_once(
  'lib/screens/notifications_screen.dart',
  """import '../state/app_state.dart';
import '../theme/app_theme.dart';""",
  """import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'admin_password_reset_screen.dart';""",
  'notifications admin reset screen import',
)

insert_method="""
  Future<void> _openPasswordReset(
    BuildContext context,
    AppState appState,
    PasswordResetRequest request,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminPasswordResetScreen(
          initialUserId: request.profileId,
        ),
      ),
    );
    if (context.mounted) {
      await appState.refreshBackend();
    }
  }

"""
anchor="""  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final me = appState.currentUser;
"""
p=Path('lib/screens/notifications_screen.dart')
s=p.read_text()
accounts_pos=s.index('class _AccountsTab')
pos=s.index(anchor,accounts_pos)
s=s[:pos]+insert_method+s[pos:]
p.write_text(s)
print('V11.6.69: password reset action inserted in accounts tab')

replace_once(
  'lib/screens/notifications_screen.dart',
  """    final pending = appState.pendingUsers.toList()
      ..sort(
        (a, b) =>
            a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
      );

    if (pending.isEmpty) {
      return const _EmptyState(
        icon: Icons.verified_user_outlined,
        message: 'Aucun compte en attente de validation.',
      );
    }""",
  """    final resetRequests = appState.passwordResetRequests.toList()
      ..sort((a, b) => b.requestedAt.compareTo(a.requestedAt));
    final pending = appState.pendingUsers.toList()
      ..sort(
        (a, b) =>
            a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
      );

    if (pending.isEmpty && resetRequests.isEmpty) {
      return const _EmptyState(
        icon: Icons.verified_user_outlined,
        message: 'Aucune action de compte en attente.',
      );
    }""",
  'accounts include password reset requests',
)

replace_once(
  'lib/screens/notifications_screen.dart',
  """        itemCount: pending.length,
        separatorBuilder: (_, __) => const SizedBox(height: 11),
        itemBuilder: (context, index) {
          final user = pending[index];
          return AppCard(""",
  """        itemCount: resetRequests.length + pending.length,
        separatorBuilder: (_, __) => const SizedBox(height: 11),
        itemBuilder: (context, index) {
          if (index < resetRequests.length) {
            final request = resetRequests[index];
            return AppCard(
              padding: EdgeInsets.all(AppSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 43,
                        height: 43,
                        decoration: BoxDecoration(
                          color: AppColors.warning.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.lock_reset_rounded,
                          color: AppColors.warning,
                          size: 23,
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Mot de passe oublié',
                              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: AppColors.warning,
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              request.fullName,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            SizedBox(height: 3),
                            Text(
                              '${request.gradeLabel} · ${request.service}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            SizedBox(height: 2),
                            Text(
                              request.hospital,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            SizedBox(height: 2),
                            Text(
                              request.phone,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Demandé le ${DateFormat('dd/MM/yyyy · HH:mm').format(request.requestedAt.toLocal())}',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.inkFaint,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: AppSpace.md),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () =>
                          _openPasswordReset(context, appState, request),
                      icon: Icon(Icons.lock_reset_rounded, size: 18),
                      label: Text('Réinitialiser le mot de passe'),
                    ),
                  ),
                ],
              ),
            );
          }

          final user = pending[index - resetRequests.length];
          return AppCard(""",
  'render password reset cards',
)


# Stable device identity prevents FCM token accumulation across rotations.
replace_once(
  'lib/services/local_storage_service.dart',
  "import 'dart:convert';",
  "import 'dart:convert';\nimport 'dart:math';",
  'local storage random import',
)
replace_once(
  'lib/services/local_storage_service.dart',
  "  static const _sessionKey = 'huim6_session_phone_v5';",
  "  static const _sessionKey = 'huim6_session_phone_v5';\n  static const _pushDeviceKey = 'gardeflow_push_device_id_v1';",
  'push device storage key',
)
replace_once(
  'lib/services/local_storage_service.dart',
  """  static Future<void> saveSessionPhone(String? phone) async {
    final prefs = await SharedPreferences.getInstance();
    if (phone == null) {
      await prefs.remove(_sessionKey);
    } else {
      await prefs.setString(_sessionKey, phone);
    }
  }
}""",
  """  static Future<void> saveSessionPhone(String? phone) async {
    final prefs = await SharedPreferences.getInstance();
    if (phone == null) {
      await prefs.remove(_sessionKey);
    } else {
      await prefs.setString(_sessionKey, phone);
    }
  }

  static Future<String> loadOrCreatePushDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_pushDeviceKey)?.trim();
    if (existing != null && existing.isNotEmpty) return existing;
    final random = Random.secure();
    final id = 'gf-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
        '${random.nextInt(0x7fffffff).toRadixString(36)}';
    await prefs.setString(_pushDeviceKey, id);
    return id;
  }
}""",
  'persistent push device id',
)

replace_once(
  'lib/services/supabase_backend_service.dart',
  """  Future<void> registerPushToken(String token, {required String platform}) async {
    await client.rpc('register_push_token', params: {
      'p_token': token,
      'p_platform': platform,
    });
  }

  Future<void> unregisterPushToken(String token) async {""",
  """  Future<void> registerPushToken(String token, {required String platform}) async {
    await client.rpc('register_push_token', params: {
      'p_token': token,
      'p_platform': platform,
    });
  }

  Future<void> registerPushDevice(
    String token, {
    required String platform,
    required String deviceId,
  }) async {
    await client.rpc('register_push_device', params: {
      'p_token': token,
      'p_platform': platform,
      'p_device_id': deviceId,
    });
  }

  Future<void> unregisterPushToken(String token) async {""",
  'backend register push device',
)

replace_once(
  'lib/services/push_notification_service.dart',
  "import 'notification_service.dart';\nimport 'supabase_backend_service.dart';",
  "import 'local_storage_service.dart';\nimport 'notification_service.dart';\nimport 'supabase_backend_service.dart';",
  'push local storage import',
)
replace_once(
  'lib/services/push_notification_service.dart',
  """      final userId = backend.client.auth.currentUser?.id;
      if (userId == null) return;
      final settings = await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);""",
  """      final userId = backend.client.auth.currentUser?.id;
      if (userId == null) return;
      final deviceId = await LocalStorageService.loadOrCreatePushDeviceId();
      final settings = await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);""",
  'load stable push device id',
)
replace_once(
  'lib/services/push_notification_service.dart',
  "await backend.registerPushToken(token, platform: _platform);\n      _registeredToken = token;",
  "await backend.registerPushDevice(token, platform: _platform, deviceId: deviceId);\n      _registeredToken = token;",
  'register current push device',
)
replace_once(
  'lib/services/push_notification_service.dart',
  "await backend.registerPushToken(token, platform: _platform);\n          if (previousToken != null && previousToken.isNotEmpty && previousToken != token) {",
  "await backend.registerPushDevice(token, platform: _platform, deviceId: deviceId);\n          if (previousToken != null && previousToken.isNotEmpty && previousToken != token) {",
  'rotate current push device token',
)

checks={
 'pubspec.yaml':['version: 11.6.69+229'],
 'lib/models/password_reset_request.dart':['class PasswordResetRequest'],
 'lib/state/app_state.dart':['passwordResetRequests','_scheduleRealtimeReload','_passwordResetRealtime'],
 'lib/services/supabase_backend_service.dart':['fetchPasswordResetRequests','admin_password_reset_requests'],
 'lib/screens/notifications_screen.dart':['Mot de passe oublié','Réinitialiser le mot de passe','AdminPasswordResetScreen'],
 'lib/screens/admin_password_reset_screen.dart':['initialUserId','_openedInitialUser'],
 'lib/services/push_notification_service.dart':['password_reset_request','initialIndex','registerPushDevice'],
 'lib/services/local_storage_service.dart':['loadOrCreatePushDeviceId','gardeflow_push_device_id_v1'],
}
for file_name,needles in checks.items():
    text=Path(file_name).read_text()
    for needle in needles:
        if needle not in text:
            raise SystemExit(f'V11.6.69 validation failed: {needle!r} missing in {file_name}')
print('GardeFlow V11.6.69 notifications/accounts + realtime/performance patch applied')
