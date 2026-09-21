class BackendConfig {
  // Configuration HUIM6 par défaut.
  // La publishable key Supabase est prévue pour être embarquée côté client.
  // Ne jamais placer ici une service_role key ou une clé secrète.
  static const String _defaultSupabaseUrl =
      'https://bqmtkdzlqfvfocxlffac.supabase.co';
  static const String _defaultSupabasePublishableKey =
      'sb_publishable_yKp0lrABt3tymcY4vDW7LA_H1AV3MiC';

  // Les --dart-define restent disponibles comme override facultatif.
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: _defaultSupabaseUrl,
  );

  static const String supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: _defaultSupabasePublishableKey,
  );

  static bool get enabled =>
      supabaseUrl.trim().isNotEmpty && supabasePublishableKey.trim().isNotEmpty;
}
