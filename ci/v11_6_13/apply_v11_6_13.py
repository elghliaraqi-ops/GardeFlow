from pathlib import Path
import shutil


def must_replace(path: str, old: str, new: str, count: int = 1) -> None:
    p = Path(path)
    text = p.read_text()
    if old not in text:
        raise SystemExit(f"V11.6.13: pattern not found in {path}: {old[:180]!r}")
    p.write_text(text.replace(old, new, count))


must_replace('pubspec.yaml', 'version: 11.6.12+172', 'version: 11.6.13+173')

must_replace(
    'lib/services/supabase_backend_service.dart',
    """  Future<void> signOut() => client.auth.signOut();
""",
    """  Future<void> adminDeleteUserAccount({required String userId}) async {
    if (!enabled || client.auth.currentUser == null) {
      throw StateError('Connexion administrateur requise.');
    }
    if (userId.trim().isEmpty) throw ArgumentError('Compte utilisateur invalide.');

    final response = await client.functions.invoke(
      'admin-delete-user',
      body: {'userId': userId.trim()},
    );
    final raw = response.data;
    if (raw is Map && raw['ok'] == true) return;

    final error = raw is Map ? raw['error']?.toString() : null;
    switch (error) {
      case 'forbidden':
        throw StateError('Cette action est réservée aux administrateurs GardeFlow.');
      case 'unauthorized':
        throw StateError('Votre session administrateur a expiré. Reconnectez-vous.');
      case 'user_not_found':
        throw StateError('Ce compte utilisateur est introuvable.');
      case 'cannot_delete_admin':
        throw StateError('Un compte administrateur ne peut pas être supprimé depuis cette fonction.');
      case 'storage_cleanup_failed':
        throw StateError('Les fichiers du compte n’ont pas pu être supprimés. Le compte a été conservé.');
      case 'data_cleanup_failed':
        throw StateError('Les données du compte n’ont pas pu être supprimées complètement. Réessayez.');
      case 'delete_failed':
        throw StateError('Le compte Auth n’a pas pu être supprimé. Réessayez.');
      default:
        throw StateError('Le compte n’a pas pu être supprimé. Réessayez.');
    }
  }

  Future<void> signOut() => client.auth.signOut();
""",
)

must_replace(
    'lib/screens/settings_screen.dart',
    "Text('Réinitialiser un mot de passe', style: Theme.of(context).textTheme.titleMedium)",
    "Text('Gérer les comptes utilisateurs', style: Theme.of(context).textTheme.titleMedium)",
)

must_replace(
    'lib/screens/settings_screen.dart',
    "'Choisissez un médecin puis définissez un nouveau mot de passe pour son compte.'",
    "'Réinitialisez un mot de passe ou supprimez définitivement un compte et ses données.'",
)

must_replace(
    'lib/screens/settings_screen.dart',
    "label: const Text('Gérer les mots de passe')",
    "label: const Text('Gérer les comptes')",
)

screen_source = Path(__file__).with_name('admin_password_reset_screen.dart')
screen_target = Path('lib/screens/admin_password_reset_screen.dart')
screen_target.parent.mkdir(parents=True, exist_ok=True)
shutil.copyfile(screen_source, screen_target)

print('GardeFlow V11.6.13 admin account deletion applied successfully')
