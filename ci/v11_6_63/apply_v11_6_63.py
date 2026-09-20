from pathlib import Path

EXPECTED = "version: 11.6.62+222"
TARGET = "version: 11.6.63+223"


def replace_once(path: str, old: str, new: str, label: str) -> None:
    p = Path(path)
    text = p.read_text()
    if old not in text:
        if new in text:
            return
        raise SystemExit(f"V11.6.63: {label} anchor missing in {path}")
    p.write_text(text.replace(old, new, 1))


pubspec = Path("pubspec.yaml")
pub = pubspec.read_text()
if EXPECTED not in pub:
    if TARGET not in pub:
        raise SystemExit("V11.6.63: base version mismatch")
else:
    pubspec.write_text(pub.replace(EXPECTED, TARGET, 1))

# ---------------------------------------------------------------------------
# 1) Login: "Créer un compte" must remain high-contrast in dark mode.
# ---------------------------------------------------------------------------
replace_once(
    "lib/screens/auth_screen.dart",
    """            style: OutlinedButton.styleFrom(
              foregroundColor: _loginGreenDark,
              backgroundColor: Colors.white.withOpacity(0.28),
              side: const BorderSide(color: _loginGreen, width: 1.4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
            child: const Text('Créer un compte', style: TextStyle(fontWeight: FontWeight.w800)),
""",
    """            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.isDarkMode ? Colors.white : _loginGreenDark,
              backgroundColor: AppColors.isDarkMode
                  ? AppColors.brand.withOpacity(0.18)
                  : Colors.white.withOpacity(0.28),
              side: BorderSide(
                color: AppColors.isDarkMode ? AppColors.brand : _loginGreen,
                width: 1.4,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
            child: const Text('Créer un compte', style: TextStyle(fontWeight: FontWeight.w800)),
""",
    "dark login create-account button",
)

# Registration title/back link use the same legacy dark green; make those adaptive too.
replace_once(
    "lib/screens/auth_screen.dart",
    """            color: _loginGreenDark,
          ),
        ),
        SizedBox(height: 6),
""",
    """            color: AppColors.isDarkMode ? AppColors.brand : _loginGreenDark,
          ),
        ),
        SizedBox(height: 6),
""",
    "register title dark contrast",
)
replace_once(
    "lib/screens/auth_screen.dart",
    """          style: TextButton.styleFrom(foregroundColor: _loginGreenDark),
          child: const Text('Déjà inscrit ? Se connecter'),
""",
    """          style: TextButton.styleFrom(
            foregroundColor: AppColors.isDarkMode ? AppColors.brand : _loginGreenDark,
          ),
          child: const Text('Déjà inscrit ? Se connecter'),
""",
    "register back-link dark contrast",
)

# ---------------------------------------------------------------------------
# 2) Notifications: badge already counts pending accounts, so admins must have
#    a matching "Comptes" section inside the bell screen.
# ---------------------------------------------------------------------------
replace_once(
    "lib/screens/notifications_screen.dart",
    """  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: initialIndex < 0 ? 0 : (initialIndex > 2 ? 2 : initialIndex),
      child: Scaffold(
""",
    """  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isAdmin = appState.currentUser?.role == UserRole.admin;
    final accountCount = isAdmin ? appState.accountActionableCount : 0;
    final tabCount = isAdmin ? 4 : 3;
    var resolvedIndex =
        initialIndex < 0 ? 0 : (initialIndex >= tabCount ? tabCount - 1 : initialIndex);

    // If the bell badge is only an account approval, open that section directly.
    if (isAdmin &&
        initialIndex == 0 &&
        accountCount > 0 &&
        appState.exchangeActionableCount() == 0 &&
        appState.leaveActionableCount() == 0) {
      resolvedIndex = 3;
    }

    return DefaultTabController(
      length: tabCount,
      initialIndex: resolvedIndex,
      child: Scaffold(
""",
    "dynamic notification tabs",
)

replace_once(
    "lib/screens/notifications_screen.dart",
    """              child: TabBar(
                dividerColor: Colors.transparent,
""",
    """              child: TabBar(
                isScrollable: isAdmin,
                dividerColor: Colors.transparent,
""",
    "scrollable admin notification tabs",
)

replace_once(
    "lib/screens/notifications_screen.dart",
    """                  Tab(text: 'Congés'),
                ],
""",
    """                  Tab(text: 'Congés'),
                  if (isAdmin)
                    Tab(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          accountCount > 0 ? 'Comptes ($accountCount)' : 'Comptes',
                        ),
                      ),
                    ),
                ],
""",
    "accounts notification tab",
)

replace_once(
    "lib/screens/notifications_screen.dart",
    """            _RemindersTab(),
            _ExchangesTab(),
            _LeavesTab(),
          ],
""",
    """            _RemindersTab(),
            _ExchangesTab(),
            _LeavesTab(),
            if (isAdmin) const _AccountsTab(),
          ],
""",
    "accounts notification view",
)

accounts_class = r'''
class _AccountsTab extends StatelessWidget {
  const _AccountsTab();

  Future<void> _reviewAccount(
    BuildContext context,
    AppState appState,
    AppUser user,
    bool approve,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(approve ? 'Valider ce compte ?' : 'Refuser ce compte ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              user.fullName,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text(
              '${user.gradeLabel} · ${user.service}',
              style: TextStyle(color: AppColors.inkSoft),
            ),
            const SizedBox(height: 3),
            Text(
              user.hospital,
              style: TextStyle(color: AppColors.inkSoft, fontSize: 12),
            ),
            const SizedBox(height: 3),
            Text(
              user.phone,
              style: TextStyle(color: AppColors.inkSoft, fontSize: 12),
            ),
            const SizedBox(height: 14),
            Text(
              approve
                  ? 'Après validation, ce médecin pourra se connecter à GardeFlow.'
                  : 'Le compte sera refusé / suspendu et ne pourra pas se connecter.',
              style: TextStyle(
                color: AppColors.inkSoft,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: approve ? AppColors.brand : AppColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: Icon(
              approve ? Icons.verified_user_outlined : Icons.block_outlined,
              size: 18,
            ),
            label: Text(approve ? 'Valider le compte' : 'Refuser'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final error = await appState.reviewAccount(user.id, approve);
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error ??
              (approve
                  ? 'Compte validé.'
                  : 'Compte refusé / suspendu.'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final me = appState.currentUser;

    if (me == null || me.role != UserRole.admin) {
      return const _EmptyState(
        icon: Icons.admin_panel_settings_outlined,
        message: 'La validation des comptes est réservée aux administrateurs.',
      );
    }

    final pending = appState.pendingUsers.toList()
      ..sort(
        (a, b) =>
            a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
      );

    if (pending.isEmpty) {
      return const _EmptyState(
        icon: Icons.verified_user_outlined,
        message: 'Aucun compte en attente de validation.',
      );
    }

    return RefreshIndicator(
      onRefresh: appState.refreshBackend,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpace.lg),
        itemCount: pending.length,
        separatorBuilder: (_, __) => const SizedBox(height: 11),
        itemBuilder: (context, index) {
          final user = pending[index];
          return AppCard(
            padding: const EdgeInsets.all(AppSpace.md),
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
                        color: AppColors.brandSoft,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.person_add_alt_1_rounded,
                        color: AppColors.brand,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.fullName,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${user.gradeLabel} · ${user.service}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            user.hospital,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            user.phone,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.md),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            _reviewAccount(context, appState, user, false),
                        icon: const Icon(Icons.block_outlined, size: 18),
                        label: const Text('Refuser'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          side: BorderSide(
                            color: AppColors.danger.withOpacity(0.55),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () =>
                            _reviewAccount(context, appState, user, true),
                        icon: const Icon(
                          Icons.verified_user_outlined,
                          size: 18,
                        ),
                        label: const Text('Valider'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

'''

notifications = Path("lib/screens/notifications_screen.dart")
nt = notifications.read_text()
anchor = "class _RemindersTab extends StatelessWidget {"
if accounts_class.strip() not in nt:
    if anchor not in nt:
        raise SystemExit("V11.6.63: reminders class anchor missing")
    nt = nt.replace(anchor, accounts_class + anchor, 1)
notifications.write_text(nt)

# Guardrails.
auth_text = Path("lib/screens/auth_screen.dart").read_text()
notif_text = notifications.read_text()
checks = [
    (auth_text, "foregroundColor: AppColors.isDarkMode ? Colors.white : _loginGreenDark"),
    (auth_text, "AppColors.brand.withOpacity(0.18)"),
    (notif_text, "final tabCount = isAdmin ? 4 : 3;"),
    (notif_text, "accountCount > 0 ? 'Comptes ($accountCount)' : 'Comptes'"),
    (notif_text, "if (isAdmin) const _AccountsTab()"),
    (notif_text, "class _AccountsTab extends StatelessWidget"),
    (notif_text, "appState.reviewAccount(user.id, approve)"),
    (notif_text, "Aucun compte en attente de validation."),
]
for haystack, needle in checks:
    if needle not in haystack:
        raise SystemExit(f"V11.6.63: missing {needle!r}")

if TARGET not in pubspec.read_text():
    raise SystemExit("V11.6.63: version bump missing")

print("GardeFlow V11.6.63: dark login account button + account approvals inside notification bell")
