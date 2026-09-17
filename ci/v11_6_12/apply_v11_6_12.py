from pathlib import Path
import shutil


def must_replace(path: str, old: str, new: str, count: int = 1) -> None:
    p = Path(path)
    text = p.read_text()
    if old not in text:
        raise SystemExit(f"V11.6.12: pattern not found in {path}: {old[:180]!r}")
    p.write_text(text.replace(old, new, count))


must_replace('pubspec.yaml', 'version: 11.6.11+171', 'version: 11.6.12+172')

# Forgot-password is now a simple admin notification request: no code and no
# password is changed from the unauthenticated screen.
must_replace(
    'lib/services/supabase_backend_service.dart',
    """  Future<void> requestPasswordResetCode(String rawPhone) async {
    if (!enabled) {
      throw StateError('La récupération du mot de passe nécessite une connexion au serveur.');
    }
    final phone = authPhone(rawPhone);
    if (phone.trim().isEmpty) throw ArgumentError('Numéro de téléphone invalide.');

    final response = await client.functions.invoke(
      'password-reset',
      body: {'action': 'request', 'phone': phone},
    );
    final raw = response.data;
    if (raw is Map && raw['ok'] == true) return;
    throw StateError('Le service de récupération est momentanément indisponible.');
  }
""",
    """  Future<void> requestPasswordResetHelp(String rawPhone) async {
    if (!enabled) {
      throw StateError('La récupération du mot de passe nécessite une connexion au serveur.');
    }
    final phone = authPhone(rawPhone);
    if (phone.trim().isEmpty) throw ArgumentError('Numéro de téléphone invalide.');

    final response = await client.functions.invoke(
      'password-reset',
      body: {'action': 'request', 'phone': phone},
    );
    final raw = response.data;
    if (raw is Map && raw['ok'] == true) return;
    throw StateError('La demande n’a pas pu être envoyée à l’administrateur. Réessayez.');
  }
""",
)

must_replace(
    'lib/services/supabase_backend_service.dart',
    """  Future<void> signOut() => client.auth.signOut();
""",
    """  Future<void> adminResetUserPassword({
    required String userId,
    required String newPassword,
  }) async {
    if (!enabled || client.auth.currentUser == null) {
      throw StateError('Connexion administrateur requise.');
    }
    if (userId.trim().isEmpty) throw ArgumentError('Compte utilisateur invalide.');
    if (newPassword.length < 8 || newPassword.length > 72) {
      throw ArgumentError('Le mot de passe doit contenir entre 8 et 72 caractères.');
    }

    final response = await client.functions.invoke(
      'admin-reset-user-password',
      body: {
        'userId': userId.trim(),
        'newPassword': newPassword,
      },
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
        throw StateError('Ce compte médecin est introuvable ou inactif.');
      case 'invalid_password':
        throw StateError('Le nouveau mot de passe ne respecte pas les critères requis.');
      default:
        throw StateError('Le mot de passe n’a pas pu être modifié. Réessayez.');
    }
  }

  Future<void> signOut() => client.auth.signOut();
""",
)

must_replace(
    'lib/screens/settings_screen.dart',
    """import '../data/hospitals.dart';
""",
    """import '../data/hospitals.dart';
import '../models/app_user.dart';
""",
)

must_replace(
    'lib/screens/settings_screen.dart',
    """import 'auth_screen.dart';
""",
    """import 'admin_password_reset_screen.dart';
import 'auth_screen.dart';
""",
)

must_replace(
    'lib/screens/settings_screen.dart',
    """          const SizedBox(height: AppSpace.xl),

          const SectionLabel('Rappels de garde'),
""",
    """          const SizedBox(height: AppSpace.xl),

          if (user?.role == UserRole.admin) ...[
            const SectionLabel('Administration des comptes'),
            AppCard(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.paperAlt,
                          borderRadius: AppRadius.smR,
                        ),
                        child: const Icon(Icons.admin_panel_settings_rounded, color: AppColors.brand),
                      ),
                      const SizedBox(width: AppSpace.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Réinitialiser un mot de passe', style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 3),
                            Text(
                              'Choisissez un médecin puis définissez un nouveau mot de passe pour son compte.',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkSoft),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.md),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AdminPasswordResetScreen()),
                      ),
                      icon: const Icon(Icons.lock_reset_rounded),
                      label: const Text('Gérer les mots de passe'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.xl),
          ],

          const SectionLabel('Rappels de garde'),
""",
)

admin_source = Path(__file__).with_name('admin_password_reset_screen.dart')
admin_target = Path('lib/screens/admin_password_reset_screen.dart')
admin_target.parent.mkdir(parents=True, exist_ok=True)
shutil.copyfile(admin_source, admin_target)

forgot_source = Path(__file__).with_name('forgot_password_screen.dart')
forgot_target = Path('lib/screens/forgot_password_screen.dart')
shutil.copyfile(forgot_source, forgot_target)

print('GardeFlow V11.6.12 admin-mediated password reset applied successfully')
