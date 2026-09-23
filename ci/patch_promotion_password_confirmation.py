from pathlib import Path
import re


def sub_once(text: str, pattern: str, replacement: str, label: str) -> str:
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f"expected one replacement for {label}, got {count}")
    return updated


# admin_screen.dart
p = Path('source/lib/screens/admin_screen.dart')
s = p.read_text()

card = """            _PromotionManagementCard(
              currentPromotion: appState.currentFirstYearPromotion,
              onAdd: () => _confirmAddPromotion(context, appState),
            ),
"""
if card not in s:
    raise SystemExit('promotion card not found')
s = s.replace(card, '', 1)

bottom_anchor = """            ] else
              const _EmptyAdminView(),
          ],
"""
bottom_replacement = """            ] else
              const _EmptyAdminView(),
            const SizedBox(height: 18),
""" + card + """            const SizedBox(height: 12),
          ],
"""
if bottom_anchor not in s:
    raise SystemExit('admin bottom anchor not found')
s = s.replace(bottom_anchor, bottom_replacement, 1)

new_confirm = r'''  Future<void> _confirmAddPromotion(
    BuildContext context,
    AppState appState,
  ) async {
    if (_adminActionOpen) return;
    final current = appState.currentFirstYearPromotion;
    final next = current + 1;
    final passwordController = TextEditingController();
    var obscurePassword = true;
    String? passwordError;

    final password = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Ajouter la Promo $next ?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'La Promo $next deviendra immédiatement la nouvelle 1re année. '
                  'La Promo $current passera en 2e année et pourra échanger/transférer '
                  'avec les promotions plus anciennes. Cette action ne modifie pas les '
                  'promotions déjà attribuées aux comptes existants.',
                ),
                const SizedBox(height: 18),
                const Text(
                  'Confirmez votre mot de passe administrateur pour continuer.',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: passwordController,
                  autofocus: true,
                  obscureText: obscurePassword,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'Mot de passe administrateur',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    errorText: passwordError,
                    suffixIcon: IconButton(
                      tooltip: obscurePassword
                          ? 'Afficher le mot de passe'
                          : 'Masquer le mot de passe',
                      onPressed: () => setDialogState(
                        () => obscurePassword = !obscurePassword,
                      ),
                      icon: Icon(
                        obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  onSubmitted: (_) {
                    final value = passwordController.text;
                    if (value.isEmpty) {
                      setDialogState(
                        () => passwordError = 'Saisissez votre mot de passe.',
                      );
                      return;
                    }
                    Navigator.pop(dialogContext, value);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            FilledButton.icon(
              onPressed: () {
                final value = passwordController.text;
                if (value.isEmpty) {
                  setDialogState(
                    () => passwordError = 'Saisissez votre mot de passe.',
                  );
                  return;
                }
                Navigator.pop(dialogContext, value);
              },
              icon: const Icon(Icons.verified_user_outlined, size: 18),
              label: Text('Confirmer et ajouter Promo $next'),
            ),
          ],
        ),
      ),
    );
    passwordController.dispose();
    if (password == null || !context.mounted) return;

    _adminActionOpen = true;
    try {
      final error = await appState.adminAddPromotion(password: password);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error ??
                'Promo ${appState.currentFirstYearPromotion} ajoutée : elle devient la 1re année.',
          ),
        ),
      );
    } finally {
      _adminActionOpen = false;
    }
  }

'''
s = sub_once(
    s,
    r"  Future<void> _confirmAddPromotion\(.*?\n  Future<void> _showPendingAccounts",
    new_confirm + "  Future<void> _showPendingAccounts",
    'admin password confirmation',
)
p.write_text(s)


# supabase_backend_service.dart
p = Path('source/lib/services/supabase_backend_service.dart')
s = p.read_text()
verify_method = r'''  Future<void> verifyCurrentPassword({
    required String rawPhone,
    required String password,
  }) async {
    if (!enabled) {
      throw StateError('La confirmation du mot de passe nécessite le serveur.');
    }
    final current = client.auth.currentUser;
    if (current == null) {
      throw StateError('Votre session administrateur a expiré. Reconnectez-vous.');
    }
    if (password.isEmpty) {
      throw StateError('Saisissez votre mot de passe administrateur.');
    }

    try {
      final result = await client.auth.signInWithPassword(
        email: technicalEmail(rawPhone),
        password: password,
      );
      final verified = result.user;
      if (verified == null || verified.id != current.id) {
        if (verified != null && verified.id != current.id) {
          await client.auth.signOut();
        }
        throw StateError('La confirmation du compte administrateur a échoué.');
      }
    } on AuthException {
      throw StateError('Mot de passe administrateur incorrect.');
    }
  }

'''
anchor = "  Future<int> adminAddInternshipPromotion() async {"
if anchor not in s:
    raise SystemExit('adminAddInternshipPromotion anchor not found')
s = s.replace(anchor, verify_method + anchor, 1)
p.write_text(s)


# app_state.dart
p = Path('source/lib/state/app_state.dart')
s = p.read_text()
new_state_method = r'''  Future<String?> adminAddPromotion({required String password}) async {
    final me = currentUser;
    if (me == null || me.role != UserRole.admin) {
      return 'Cette action est réservée aux administrateurs.';
    }
    if (password.isEmpty) {
      return 'Saisissez votre mot de passe administrateur.';
    }
    if (!backendEnabled) {
      return 'La confirmation du mot de passe nécessite une connexion au serveur.';
    }
    try {
      final backend = SupabaseBackendService.instance;
      await backend.verifyCurrentPassword(
        rawPhone: me.phone,
        password: password,
      );
      _currentFirstYearPromotion =
          await backend.adminAddInternshipPromotion();
      await _persistNow();
      notifyListeners();
      return null;
    } catch (e) {
      final text = e.toString();
      return text.startsWith('Bad state: ')
          ? text.substring('Bad state: '.length)
          : text.startsWith('StateError: ')
              ? text.substring('StateError: '.length)
              : text;
    }
  }

'''
s = sub_once(
    s,
    r"  Future<String\?> adminAddPromotion\(\) async \{.*?\n  bool promotionExchangeBlocked",
    new_state_method + "  bool promotionExchangeBlocked",
    'state password-gated promotion add',
)
p.write_text(s)

print('Promotion password confirmation patch applied.')
