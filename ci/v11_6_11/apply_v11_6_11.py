from pathlib import Path
import shutil


def must_replace(path: str, old: str, new: str, count: int = 1) -> None:
    p = Path(path)
    text = p.read_text()
    if old not in text:
        raise SystemExit(f"V11.6.11: pattern not found in {path}: {old[:180]!r}")
    p.write_text(text.replace(old, new, count))


must_replace('pubspec.yaml', 'version: 11.6.10+170', 'version: 11.6.11+171')

must_replace(
    'lib/services/supabase_backend_service.dart',
    """  Future<void> signOut() => client.auth.signOut();
""",
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

  Future<void> confirmPasswordReset({
    required String rawPhone,
    required String code,
    required String newPassword,
  }) async {
    if (!enabled) {
      throw StateError('La récupération du mot de passe nécessite une connexion au serveur.');
    }
    final phone = authPhone(rawPhone);
    if (phone.trim().isEmpty) throw ArgumentError('Numéro de téléphone invalide.');

    final response = await client.functions.invoke(
      'password-reset',
      body: {
        'action': 'confirm',
        'phone': phone,
        'code': code.trim(),
        'newPassword': newPassword,
      },
    );
    final raw = response.data;
    if (raw is Map && raw['ok'] == true) return;

    final error = raw is Map ? raw['error']?.toString() : null;
    switch (error) {
      case 'invalid_code':
        throw StateError('Le code saisi est incorrect.');
      case 'expired_code':
        throw StateError('Ce code a expiré. Demandez un nouveau code.');
      case 'too_many_attempts':
        throw StateError('Trop de tentatives. Demandez un nouveau code.');
      case 'invalid_input':
        throw StateError('Vérifiez le code et le nouveau mot de passe.');
      default:
        throw StateError('Le mot de passe n’a pas pu être modifié. Réessayez.');
    }
  }

  Future<void> signOut() => client.auth.signOut();
""",
)

must_replace(
    'lib/screens/auth_screen.dart',
    """import 'home_screen.dart';
""",
    """import 'forgot_password_screen.dart';
import 'home_screen.dart';
""",
)

must_replace(
    'lib/screens/auth_screen.dart',
    """  void _showPasswordHelp() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Pour réinitialiser votre mot de passe, contactez un administrateur GardeFlow.'),
      ),
    );
  }
""",
    """  Future<void> _showPasswordHelp() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ForgotPasswordScreen(initialPhone: _loginPhoneCtrl.text),
      ),
    );
    if (!mounted || changed != true) return;
    setState(() {
      _error = null;
      _info = 'Mot de passe modifié. Vous pouvez maintenant vous connecter avec votre nouveau mot de passe.';
    });
  }
""",
)

source = Path(__file__).with_name('forgot_password_screen.dart')
target = Path('lib/screens/forgot_password_screen.dart')
target.parent.mkdir(parents=True, exist_ok=True)
shutil.copyfile(source, target)

print('GardeFlow V11.6.11 forgot-password flow applied successfully')
