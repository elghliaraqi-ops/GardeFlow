from pathlib import Path

EXPECTED = "version: 11.6.20+180"
TARGET = "version: 11.6.21+181"

pubspec = Path("pubspec.yaml")
pub = pubspec.read_text()
if EXPECTED not in pub:
    raise SystemExit("V11.6.21: base version mismatch")
pubspec.write_text(pub.replace(EXPECTED, TARGET, 1))

home = Path("lib/screens/home_screen.dart")
text = home.read_text()

def replace_class(source: str, class_name: str, replacement: str) -> str:
    marker = f"class {class_name} "
    start = source.find(marker)
    if start < 0:
        raise SystemExit(f"V11.6.21: {class_name} not found")
    brace = source.find("{", start)
    if brace < 0:
        raise SystemExit(f"V11.6.21: opening brace missing for {class_name}")
    depth = 0
    end = None
    for i in range(brace, len(source)):
        ch = source[i]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                end = i + 1
                break
    if end is None:
        raise SystemExit(f"V11.6.21: closing brace missing for {class_name}")
    return source[:start] + replacement.rstrip() + source[end:]

home_state = r"""class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final me = appState.currentUser;

    if (me != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && appState.currentUser != null) {
          PushNotificationService.instance.navigationReady(
            isAdmin: appState.currentUser!.role == UserRole.admin,
          );
        }
      });
    }

    if (me == null) {
      return const Scaffold(
        backgroundColor: AppColors.paper,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.paper,
      extendBody: false,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _GlobalTopBar(
              appState: appState,
              onNotifications: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              ),
              onAccount: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: [
                  _DashboardView(
                    appState: appState,
                    onOpenPlanning: () => setState(() => _tab = 1),
                    onOpenDirectory: () => setState(() => _tab = 2),
                    onOpenProfile: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ProfileScreen()),
                    ),
                  ),
                  _PlanningView(appState: appState),
                  const DirectoryScreen(embedded: true),
                  const _AstreintesHubView(),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        height: 72,
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Accueil',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month_rounded),
            label: 'Planning',
          ),
          NavigationDestination(
            icon: Icon(Icons.badge_outlined),
            selectedIcon: Icon(Icons.badge_rounded),
            label: 'Annuaire',
          ),
          NavigationDestination(
            icon: Icon(Icons.medical_services_outlined),
            selectedIcon: Icon(Icons.medical_services_rounded),
            label: 'Astreintes',
          ),
        ],
      ),
    );
  }

  Future<void> _showQuickAdd(BuildContext context, AppState appState) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _QuickAddGuardSheet(appState: appState),
    );
    if (!mounted || result != true) return;
    setState(() => _tab = 1);
  }
}

class _GlobalTopBar extends StatelessWidget {
  final AppState appState;
  final VoidCallback onNotifications;
  final VoidCallback onAccount;

  const _GlobalTopBar({
    required this.appState,
    required this.onNotifications,
    required this.onAccount,
  });

  @override
  Widget build(BuildContext context) {
    final user = appState.currentUser;
    if (user == null) return const SizedBox.shrink();

    final badge = appState.totalBadgeCount;
    final rawInitial = user.nom.trim();
    final initial = rawInitial.isEmpty ? 'D' : rawInitial.substring(0, 1).toUpperCase();

    return Container(
      height: 62,
      padding: const EdgeInsets.fromLTRB(18, 8, 14, 6),
      decoration: BoxDecoration(
        color: AppColors.paper,
        border: Border(
          bottom: BorderSide(color: AppColors.line.withOpacity(0.55)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.brand,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AppColors.brand.withOpacity(0.18),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: const Icon(
              Icons.add_rounded,
              size: 25,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'GardeFlow',
              style: TextStyle(
                fontFamily: 'SpaceGrotesk',
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
                letterSpacing: -0.35,
              ),
            ),
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              Material(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  onTap: onNotifications,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.line),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.notifications_none_rounded,
                      color: AppColors.ink,
                      size: 22,
                    ),
                  ),
                ),
              ),
              if (badge > 0)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.danger,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppColors.paper, width: 2),
                    ),
                    child: Text(
                      badge > 99 ? '99+' : '$badge',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 10),
          Tooltip(
            message: 'Mon compte',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onAccount,
                customBorder: const CircleBorder(),
                child: Container(
                  width: 43,
                  height: 43,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.brandDark, AppColors.brand],
                    ),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.brand.withOpacity(0.18),
                        blurRadius: 12,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Text(
                    initial,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'SpaceGrotesk',
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AstreintesHubView extends StatelessWidget {
  const _AstreintesHubView();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.paper,
      child: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 30),
        children: [
          Text(
            'Astreintes',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontFamily: 'SpaceGrotesk',
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  color: AppColors.ink,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Retrouvez les astreintes séniors et juniors avec la logique habituelle.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.inkSoft,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                ),
          ),
          const SizedBox(height: 22),
          _AstreinteFeatureCard(
            eyebrow: 'SÉNIORS',
            title: 'Astreintes séniors',
            description:
                'Photos des tableaux d’astreinte classées par établissement, avec consultation et zoom.',
            icon: Icons.photo_library_rounded,
            accent: AppColors.brand,
            trailingLabel: 'Photos par établissement',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AstreinteScreen()),
            ),
          ),
          const SizedBox(height: 16),
          _AstreinteFeatureCard(
            eyebrow: 'JUNIORS',
            title: 'Astreintes juniors',
            description:
                'Calendrier par jour avec le médecin junior de garde de service pour chaque date.',
            icon: Icons.calendar_view_week_rounded,
            accent: AppColors.service24h,
            trailingLabel: 'Calendrier des gardes',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const JuniorOnCallScreen()),
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.line),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 20,
                  color: AppColors.brand,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Les photos déjà enregistrées et les données existantes sont conservées. Cette page ne change que l’accès et la présentation.',
                    style: TextStyle(
                      color: AppColors.inkSoft,
                      fontSize: 12,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AstreinteFeatureCard extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String description;
  final IconData icon;
  final Color accent;
  final String trailingLabel;
  final VoidCallback onTap;

  const _AstreinteFeatureCard({
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.icon,
    required this.accent,
    required this.trailingLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(26),
        child: Ink(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: AppColors.line),
            boxShadow: [
              BoxShadow(
                color: AppColors.navy.withOpacity(0.06),
                blurRadius: 20,
                offset: const Offset(0, 9),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(icon, color: accent, size: 27),
                  ),
                  const Spacer(),
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.paper,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: const Icon(
                      Icons.arrow_forward_rounded,
                      size: 20,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                eyebrow,
                style: TextStyle(
                  color: accent,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'SpaceGrotesk',
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                  letterSpacing: -0.35,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                description,
                style: const TextStyle(
                  color: AppColors.inkSoft,
                  fontSize: 13,
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(
                    Icons.touch_app_outlined,
                    size: 16,
                    color: accent,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      trailingLabel,
                      style: TextStyle(
                        color: accent,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
"""

text = replace_class(text, "_HomeScreenState", home_state)

old_planning_bell = """              SoftIconButton(
                icon: Icons.notifications_none_rounded,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                ),
                tooltip: 'Notifications',
              ),"""
if old_planning_bell in text:
    text = text.replace(old_planning_bell, "              const SizedBox(width: 4),", 1)
else:
    print("V11.6.21 warning: planning notification button not found; global top bar still active")

home.write_text(text)

print("GardeFlow V11.6.21: onglet Astreintes + notifications et compte globaux")
