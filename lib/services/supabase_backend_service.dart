import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/backend_config.dart';
import '../models/app_user.dart';
import '../models/audit_event.dart';
import '../models/exchange_request.dart';
import '../models/leave_request.dart';
import '../models/planning_entry.dart';
import '../models/planning_month.dart';
import '../models/shared_resource.dart';

class SupabaseBackendService {
  SupabaseBackendService._();
  static final instance = SupabaseBackendService._();

  SupabaseClient get client => Supabase.instance.client;
  bool get enabled => BackendConfig.enabled;

  static String authPhone(String raw) {
    var p = raw.replaceAll(RegExp(r'[\s.\-()]'), '');
    if (p.startsWith('00')) p = '+${p.substring(2)}';
    if (p.startsWith('+')) return p;
    if (p.startsWith('0') && p.length >= 10) return '+212${p.substring(1)}';
    if (p.startsWith('212')) return '+$p';
    return p;
  }

  static String technicalEmail(String rawPhone) {
    final phone = authPhone(rawPhone);
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) throw ArgumentError('Numéro de téléphone invalide.');
    final uri = Uri.tryParse(BackendConfig.supabaseUrl);
    final host = uri?.host.trim() ?? '';
    if (host.isEmpty) throw StateError('SUPABASE_URL invalide ou manquante.');
    return '$digits@$host';
  }

  Future<void> initialize() async {
    if (!enabled) return;
    await Supabase.initialize(
      url: BackendConfig.supabaseUrl,
      anonKey: BackendConfig.supabasePublishableKey,
    );
  }

  Future<AppUser> signIn(String rawPhone, String password) async {
    final email = technicalEmail(rawPhone);
    final res = await client.auth.signInWithPassword(email: email, password: password);
    if (res.user == null) throw StateError('Connexion impossible.');
    return fetchMyProfile();
  }

  Future<AppUser> signUp({
    required String nom,
    required String prenom,
    required String rawPhone,
    required String password,
    required String service,
    required MedicalGrade grade,
    required String hospital,
  }) async {
    final phone = authPhone(rawPhone);
    final email = technicalEmail(phone);
    final res = await client.auth.signUp(
      email: email,
      password: password,
      data: {
        'nom': nom.trim(),
        'prenom': prenom.trim(),
        'phone': phone,
        'service': service,
        'medical_grade': grade.name,
        'fonction': grade.name,
        'hospital': hospital,
      },
    );
    if (res.user == null) throw StateError('Création du compte impossible.');
    if (res.session == null) {
      throw StateError(
        'Le compte a été créé mais Supabase attend une confirmation email. '
        'Désactivez « Confirm email » dans Authentication > Providers > Email.',
      );
    }
    return fetchMyProfile();
  }

  Future<void> signOut() => client.auth.signOut();

  Future<AppUser> fetchMyProfile() async {
    final uid = client.auth.currentUser?.id;
    if (uid == null) throw StateError('Session Supabase absente.');
    final row = await client.from('profiles').select().eq('id', uid).single();
    return _profileToUser(Map<String, dynamic>.from(row));
  }

  Future<List<AppUser>> fetchVisibleProfiles() async {
    final rows = await client.from('profiles').select().order('prenom').order('nom');
    return (rows as List).map((e) => _profileToUser(Map<String, dynamic>.from(e))).toList();
  }

  AppUser _profileToUser(Map<String, dynamic> j) {
    final rawGrade = (j['medical_grade'] as String?) ?? (j['fonction'] as String?) ?? 'junior';
    final grade = rawGrade == 'senior' ? MedicalGrade.senior : MedicalGrade.junior;
    final rawStatus = (j['account_status'] as String?) ?? 'active';
    return AppUser(
      id: j['id'] as String,
      nom: j['nom'] as String,
      prenom: j['prenom'] as String,
      phone: j['phone'] as String,
      passwordHash: '',
      passwordSalt: '',
      service: j['service'] as String,
      grade: grade,
      hospital: j['hospital'] as String,
      role: UserRole.values.byName((j['role'] as String?) ?? 'medecin'),
      accountStatus: AccountStatus.values.byName(rawStatus),
    );
  }

  Future<List<PlanningEntry>> fetchPlanning() async {
    final rows = await client
        .from('planning_entries')
        .select()
        .isFilter('deleted_at', null)
        .order('date_str');
    return (rows as List).map((raw) {
      final j = Map<String, dynamic>.from(raw);
      return PlanningEntry(
        id: j['id'] as String,
        dateStr: j['date_str'].toString(),
        shiftId: j['shift_id'] as String,
        ownerId: (j['owner_id'] as String?) ?? '',
        ownerPhone: j['owner_phone'] as String,
        ownerName: j['owner_name'] as String,
        leaveRequestId: j['leave_request_id'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
    }).toList();
  }

  /// Vue réseau dédiée aux gardes de service des médecins Juniors.
  /// Le RPC Supabase ne renvoie que les calendriers validés et uniquement
  /// les informations nécessaires à cette page.
  Future<List<Map<String, dynamic>>> fetchJuniorOnCallRoster({
    required DateTime from,
    required DateTime to,
  }) async {
    String date(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final rows = await client.rpc('junior_oncall_roster', params: {
      'p_from': date(from),
      'p_to': date(to),
    });
    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<List<PlanningMonth>> fetchPlanningMonths() async {
    final rows = await client
        .from('planning_months')
        .select()
        .order('year')
        .order('month');
    return (rows as List).map((raw) {
      final j = Map<String, dynamic>.from(raw);
      return PlanningMonth(
        ownerId: j['owner_id'] as String,
        year: (j['year'] as num).toInt(),
        month: (j['month'] as num).toInt(),
        status: PlanningMonthStatus.values.byName((j['status'] as String?) ?? 'draft'),
        submittedAt: j['submitted_at'] == null ? null : DateTime.parse(j['submitted_at'] as String),
        reviewedAt: j['reviewed_at'] == null ? null : DateTime.parse(j['reviewed_at'] as String),
        reviewedBy: j['reviewed_by'] as String?,
        rejectionReason: j['rejection_reason'] as String?,
      );
    }).toList();
  }

  Future<List<ExchangeRequest>> fetchExchanges() async {
    final rows = await client.from('exchange_requests').select().order('created_at');
    return (rows as List).map((raw) {
      final j = Map<String, dynamic>.from(raw);
      return ExchangeRequest(
        id: j['id'] as String,
        type: ShiftRequestType.values.byName(j['type'] as String),
        planningEntryId: j['planning_entry_id'] as String,
        dateStr: j['date_str'].toString(),
        shiftId: j['shift_id'] as String,
        targetPlanningEntryId: j['target_planning_entry_id'] as String?,
        targetDateStr: j['target_date_str']?.toString(),
        targetShiftId: j['target_shift_id'] as String?,
        fromId: (j['from_id'] as String?) ?? '',
        fromPhone: j['from_phone'] as String,
        fromName: j['from_name'] as String,
        toId: (j['to_id'] as String?) ?? '',
        toPhone: j['to_phone'] as String,
        toName: j['to_name'] as String,
        status: ExchangeStatus.values.byName(j['status'] as String),
        createdAt: DateTime.parse(j['created_at'] as String),
      );
    }).toList();
  }

  Future<List<LeaveRequest>> fetchLeaveRequests() async {
    final rows = await client.from('leave_requests').select().order('created_at');
    return (rows as List).map((raw) {
      final j = Map<String, dynamic>.from(raw);
      final legacyDate = j['date_str']?.toString();
      return LeaveRequest(
        id: j['id'] as String,
        startDateStr: j['start_date']?.toString() ?? legacyDate ?? '',
        endDateStr: j['end_date']?.toString() ?? legacyDate ?? '',
        ownerId: (j['owner_id'] as String?) ?? '',
        ownerPhone: j['owner_phone'] as String,
        ownerName: j['owner_name'] as String,
        status: LeaveRequestStatus.values.byName(j['status'] as String),
        createdAt: DateTime.parse(j['created_at'] as String),
        reviewedAt: j['reviewed_at'] == null ? null : DateTime.parse(j['reviewed_at'] as String),
      );
    }).toList();
  }

  Future<List<AuditEvent>> fetchAudit({int limit = 200}) async {
    final rows = await client
        .from('audit_log')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List).map((raw) {
      final j = Map<String, dynamic>.from(raw);
      return AuditEvent(
        id: (j['id'] as num).toInt(),
        action: j['action'] as String,
        entityType: j['entity_type'] as String,
        entityId: j['entity_id'] as String,
        actorName: (j['actor_name'] as String?) ?? 'Système',
        subjectName: j['subject_name'] as String?,
        reason: j['reason'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
    }).toList();
  }

  Future<String> saveMyPlanningEntry({
    required String dateStr,
    required String shiftId,
  }) async {
    final result = await client.rpc('save_my_planning_entry', params: {
      'p_date': dateStr,
      'p_shift_id': shiftId,
    });
    return result.toString();
  }

  Future<void> deleteMyPlanningEntry(String entryId) async {
    await client.rpc('delete_my_planning_entry', params: {'p_entry_id': entryId});
  }

  Future<List<String>> submitMyPlanningMonth(int year, int month) async {
    final result = await client.rpc('submit_my_planning_month', params: {
      'p_year': year,
      'p_month': month,
    });
    if (result == null) return const <String>[];
    if (result is List) return result.map((e) => e.toString()).toList();
    return <String>[result.toString()];
  }

  Future<void> adminReopenPlanningMonth({
    required String ownerId,
    required int year,
    required int month,
    required String reason,
  }) async {
    await client.rpc('admin_reopen_planning_month', params: {
      'p_owner_id': ownerId,
      'p_year': year,
      'p_month': month,
      'p_reason': reason,
    });
  }

  Future<void> createLeaveRequest(LeaveRequest request) async {
    await client.rpc('create_leave_request', params: {
      'p_request_id': request.id,
      'p_start_date': request.startDateStr,
      'p_end_date': request.endDateStr,
    });
  }

  Future<void> reviewLeaveRequest(String id, String action) async {
    await client.rpc('review_leave_request', params: {
      'p_request_id': id,
      'p_action': action,
    });
  }

  Future<void> cancelLeaveRequest(String id) async {
    await client.rpc('cancel_leave_request', params: {'p_request_id': id});
  }

  Future<void> adminDeletePlanning(String id, String reason) async {
    await client.rpc('admin_delete_planning', params: {
      'p_entry_id': id,
      'p_reason': reason,
    });
  }

  Future<void> reviewAccount(
    String profileId,
    String action, {
    String? hospital,
    String? service,
    MedicalGrade? grade,
  }) async {
    await client.rpc('review_profile_account', params: {
      'p_profile_id': profileId,
      'p_action': action,
      'p_hospital': hospital,
      'p_service': service,
      'p_medical_grade': grade?.name,
    });
  }

  Future<void> registerPushToken(String token, {required String platform}) async {
    await client.rpc('register_push_token', params: {
      'p_token': token,
      'p_platform': platform,
    });
  }

  Future<void> unregisterPushToken(String token) async {
    await client.rpc('unregister_push_token', params: {'p_token': token});
  }

  static const String sharedBucket = 'gardeflow-shared';

  Future<List<SharedResource>> fetchSharedResources({required String kind}) async {
    final rows = await client
        .from('shared_resources')
        .select()
        .eq('kind', kind)
        .order('updated_at', ascending: false);
    return (rows as List)
        .map((e) => SharedResource.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<SharedResource>> fetchAstreintePhotos() =>
      fetchSharedResources(kind: 'astreinte_photo');

  Future<List<SharedResource>> fetchOfficialPlanningPdfs() =>
      fetchSharedResources(kind: 'official_pdf');

  Future<Uint8List> downloadSharedResource(String storagePath) async {
    return client.storage.from(sharedBucket).download(storagePath);
  }

  Future<String> signedSharedResourceUrl(String storagePath, {int expiresIn = 3600}) async {
    return client.storage.from(sharedBucket).createSignedUrl(storagePath, expiresIn);
  }

  Future<void> uploadAstreintePhoto({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final uid = client.auth.currentUser?.id;
    if (uid == null) throw StateError('Session Supabase absente.');
    final ext = _safeExtension(fileName, fallback: _extensionForMime(mimeType, fallback: 'jpg'));
    final path = 'astreinte/${uid}_${DateTime.now().microsecondsSinceEpoch}.$ext';
    await client.storage.from(sharedBucket).uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(contentType: mimeType, upsert: false),
    );
    try {
      await client.from('shared_resources').insert({
        'kind': 'astreinte_photo',
        'storage_path': path,
        'display_name': fileName,
        'mime_type': mimeType,
        'uploaded_by': uid,
      });
    } catch (_) {
      await client.storage.from(sharedBucket).remove([path]);
      rethrow;
    }
  }

  Future<SharedResource> uploadOfficialPlanningPdf({
    required String slot,
    required Uint8List bytes,
    required String fileName,
  }) async {
    final uid = client.auth.currentUser?.id;
    if (uid == null) throw StateError('Session Supabase absente.');
    final path = 'official/$slot.pdf';
    await client.storage.from(sharedBucket).uploadBinary(
      path,
      bytes,
      fileOptions: const FileOptions(contentType: 'application/pdf', upsert: true),
    );
    await client.from('shared_resources').upsert({
      'kind': 'official_pdf',
      'slot': slot,
      'storage_path': path,
      'display_name': fileName,
      'mime_type': 'application/pdf',
      'uploaded_by': uid,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'kind,slot');
    final row = await client
        .from('shared_resources')
        .select()
        .eq('kind', 'official_pdf')
        .eq('slot', slot)
        .single();
    return SharedResource.fromJson(Map<String, dynamic>.from(row));
  }

  Future<bool> officialRosterImportIsCurrent(SharedResource resource) async {
    final result = await client.rpc('official_roster_import_is_current', params: {
      'p_resource_id': resource.id,
      'p_resource_updated_at': resource.updatedAt.toUtc().toIso8601String(),
    });
    return result == true;
  }

  Future<Map<String, dynamic>> importOfficialEmergencyRoster({
    required SharedResource resource,
    required List<Map<String, dynamic>> assignments,
    required List<Map<String, dynamic>> unmatchedCells,
  }) async {
    final result = await client.rpc('import_official_emergency_roster', params: {
      'p_resource_id': resource.id,
      'p_resource_updated_at': resource.updatedAt.toUtc().toIso8601String(),
      'p_assignments': assignments,
      'p_unmatched_cells': unmatchedCells,
    });
    return Map<String, dynamic>.from(result as Map);
  }

  Future<void> deleteSharedResource(SharedResource resource) async {
    await client.storage.from(sharedBucket).remove([resource.storagePath]);
    await client.from('shared_resources').delete().eq('id', resource.id);
  }

  String _safeExtension(String fileName, {required String fallback}) {
    final clean = fileName.trim();
    final dot = clean.lastIndexOf('.');
    if (dot <= 0 || dot == clean.length - 1) return fallback;
    final ext = clean.substring(dot + 1).toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return ext.isEmpty || ext.length > 5 ? fallback : ext;
  }

  String _extensionForMime(String mimeType, {required String fallback}) {
    switch (mimeType.toLowerCase()) {
      case 'image/png': return 'png';
      case 'image/webp': return 'webp';
      case 'image/jpeg':
      case 'image/jpg': return 'jpg';
      default: return fallback;
    }
  }

  Future<void> triggerPush(String kind, String resourceId) async {
    final response = await client.functions.invoke(
      'send-push',
      body: {'kind': kind, 'resourceId': resourceId},
    );
    final data = response.data;
    if (data is Map && (data['failed'] as num? ?? 0) > 0) {
      throw StateError('Certains appareils n’ont pas reçu la notification push. Consulter send-push.');
    }
  }

  Future<void> createRequest(ExchangeRequest e) async {
    await client.from('exchange_requests').insert({
      'id': e.id,
      'type': e.type.name,
      'planning_entry_id': e.planningEntryId,
      'date_str': e.dateStr,
      'shift_id': e.shiftId,
      'target_planning_entry_id': e.targetPlanningEntryId,
      'target_date_str': e.targetDateStr,
      'target_shift_id': e.targetShiftId,
      'from_id': e.fromId,
      'from_phone': e.fromPhone,
      'from_name': e.fromName,
      'to_id': e.toId,
      'to_phone': e.toPhone,
      'to_name': e.toName,
      'status': e.status.name,
      'created_at': e.createdAt.toIso8601String(),
    });
  }

  Future<void> respondRequest(String id, String action) async {
    await client.rpc('respond_shift_request', params: {'p_request_id': id, 'p_action': action});
  }

  Future<void> reviewRequest(String id, String action) async {
    await client.rpc('review_shift_request', params: {'p_request_id': id, 'p_action': action});
  }

  Future<void> cancelRequest(String id) async {
    await client.rpc('cancel_shift_request', params: {'p_request_id': id});
  }
}
