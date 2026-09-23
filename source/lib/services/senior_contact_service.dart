import 'supabase_backend_service.dart';

extension SeniorOnCallContactService on SupabaseBackendService {
  Future<Map<String, dynamic>> addSeniorOnCallContact({
    required String name,
    required String phone,
    required String hospital,
    required String service,
  }) async {
    if (!enabled || client.auth.currentUser == null) {
      throw StateError('Connexion administrateur requise.');
    }

    final normalized = SupabaseBackendService.authPhone(phone);
    final digits = normalized.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 9) {
      throw ArgumentError('Numéro de téléphone invalide.');
    }

    final result = await client.rpc(
      'add_senior_oncall_contact',
      params: {
        'p_name': name.trim(),
        'p_phone': normalized,
        'p_hospital': hospital,
        'p_service': service.trim(),
      },
    );

    return Map<String, dynamic>.from(result as Map);
  }
}
