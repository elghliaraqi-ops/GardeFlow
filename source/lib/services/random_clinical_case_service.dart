import 'supabase_backend_service.dart';

/// Cas entièrement fictif, à relire avant toute publication dans Practice.
class RandomClinicalCase {
  final Map<String, dynamic> _data;

  RandomClinicalCase._(this._data);

  factory RandomClinicalCase.fromMap(Map<String, dynamic> payload) {
    final raw = payload['case'];
    if (payload['ok'] != true || raw is! Map) {
      throw const FormatException('Réponse de génération invalide.');
    }
    final data = Map<String, dynamic>.from(raw);
    final age = data['age'];
    final reason = (data['consultation_reason'] ?? '').toString().trim();
    final history = (data['illness_history'] ?? '').toString().trim();
    final exam = (data['clinical_exam'] ?? '').toString().trim();
    final assessment = (data['assessment'] ?? '').toString().trim();
    final plan = (data['plan'] ?? '').toString().trim();
    final sex = (data['sex'] ?? '').toString();
    if (age is! int || age < 1 || age > 105 ||
        !const ['F', 'M', 'Autre', 'Non précisé'].contains(sex) ||
        reason.length < 15 || history.length < 30 ||
        exam.length < 30 || assessment.length < 20 || plan.length < 30) {
      throw const FormatException('Le cas généré est incomplet.');
    }
    return RandomClinicalCase._(data);
  }

  int get age => _data['age'] as int;
  String get sex => _data['sex'] as String;
  String text(String field) => (_data[field] ?? '').toString().trim();
  bool flag(String field) => _data[field] == true;
}

class RandomClinicalCaseService {
  RandomClinicalCaseService._();
  static final instance = RandomClinicalCaseService._();

  Future<RandomClinicalCase> generate() async {
    final backend = SupabaseBackendService.instance;
    if (!backend.enabled || backend.client.auth.currentUser == null) {
      throw StateError('Connectez-vous pour générer un cas clinique.');
    }
    final response = await backend.client.functions.invoke(
      'generate-random-clinical-case',
      body: <String, dynamic>{},
    );
    if (response.status != 200 || response.data is! Map) {
      throw StateError('La génération IA est momentanément indisponible.');
    }
    return RandomClinicalCase.fromMap(
      Map<String, dynamic>.from(response.data as Map),
    );
  }
}
