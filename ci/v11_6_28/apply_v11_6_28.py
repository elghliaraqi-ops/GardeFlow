from pathlib import Path

EXPECTED = "version: 11.6.27+187"
TARGET = "version: 11.6.28+188"

pubspec = Path("pubspec.yaml")
pub = pubspec.read_text()
if EXPECTED not in pub:
    raise SystemExit("V11.6.28: base version mismatch")
pubspec.write_text(pub.replace(EXPECTED, TARGET, 1))

def replace_class(source: str, class_name: str, replacement: str) -> str:
    marker = f"class {class_name} "
    start = source.find(marker)
    if start < 0:
        raise SystemExit(f"V11.6.28: class {class_name} not found")
    brace = source.find("{", start)
    if brace < 0:
        raise SystemExit(f"V11.6.28: opening brace missing for {class_name}")
    depth = 0
    end = None
    for i in range(brace, len(source)):
        if source[i] == "{":
            depth += 1
        elif source[i] == "}":
            depth -= 1
            if depth == 0:
                end = i + 1
                break
    if end is None:
        raise SystemExit(f"V11.6.28: closing brace missing for {class_name}")
    return source[:start] + replacement.rstrip() + source[end:]

# ---------------------------------------------------------------------------
# Shared title: true logo + page title only. Remove the "GardeFlow" subtitle
# from all secondary AppBars that use GardeFlowTitle.
# ---------------------------------------------------------------------------
widgets = Path("lib/theme/widgets.dart")
w = widgets.read_text()

title_class = r"""class GardeFlowTitle extends StatelessWidget {
  final String section;
  const GardeFlowTitle(this.section, {super.key});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const GardeFlowLogo(size: 34),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              section,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                  ),
            ),
          ),
        ],
      );
}
"""
w = replace_class(w, "GardeFlowTitle", title_class)
widgets.write_text(w)

# ---------------------------------------------------------------------------
# Main tabs: replace generic "GardeFlow" header by the current page title.
# Keep the logo, notification bell and account access.
# ---------------------------------------------------------------------------
home = Path("lib/screens/home_screen.dart")
h = home.read_text()

old_call = """            _GlobalTopBar(
              appState: appState,
              onNotifications: () => Navigator.push("""
new_call = """            _GlobalTopBar(
              title: const ['Accueil', 'Planning', 'Annuaire', 'Astreintes'][_tab],
              appState: appState,
              onNotifications: () => Navigator.push("""
if old_call not in h:
    raise SystemExit("V11.6.28: _GlobalTopBar call anchor missing")
h = h.replace(old_call, new_call, 1)

global_bar = r"""class _GlobalTopBar extends StatelessWidget {
  final String title;
  final AppState appState;
  final VoidCallback onNotifications;
  final VoidCallback onAccount;

  const _GlobalTopBar({
    required this.title,
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
    final initial =
        rawInitial.isEmpty ? 'D' : rawInitial.substring(0, 1).toUpperCase();

    return Container(
      height: 58,
      padding: const EdgeInsets.fromLTRB(16, 7, 13, 6),
      decoration: BoxDecoration(
        color: AppColors.paper,
        border: Border(
          bottom: BorderSide(color: AppColors.line.withOpacity(0.55)),
        ),
      ),
      child: Row(
        children: [
          const GardeFlowLogo(size: 38),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'SpaceGrotesk',
                fontSize: 20,
                fontWeight: FontWeight.w900,
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
                borderRadius: BorderRadius.circular(13),
                child: InkWell(
                  onTap: onNotifications,
                  borderRadius: BorderRadius.circular(13),
                  child: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.line),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.notifications_none_rounded,
                      color: AppColors.ink,
                      size: 21,
                    ),
                  ),
                ),
              ),
              if (badge > 0)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    constraints:
                        const BoxConstraints(minWidth: 18, minHeight: 18),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.danger,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppColors.paper, width: 2),
                    ),
                    child: Text(
                      badge > 99 ? '99+' : '¤badge',
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
          const SizedBox(width: 9),
          Tooltip(
            message: 'Mon compte',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onAccount,
                customBorder: const CircleBorder(),
                child: Container(
                  width: 40,
                  height: 40,
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
                        color: AppColors.brand.withOpacity(0.16),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Text(
                    initial,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'SpaceGrotesk',
                      fontSize: 15,
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
"""
global_bar = global_bar.replace("¤", "$")
h = replace_class(h, "_GlobalTopBar", global_bar)
home.write_text(h)

# ---------------------------------------------------------------------------
# Directory embedded in Home: remove the second logo/title row.
# Keep the admin add-contact action temporarily visible until its dedicated
# floating-button correction in the next step.
# ---------------------------------------------------------------------------
directory = Path("lib/screens/directory_screen.dart")
d = directory.read_text()
old_dir_header = """        if (widget.embedded)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Row(
              children: [
                const GardeFlowLogo(size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Annuaire', style: Theme.of(context).textTheme.titleLarge),
                      Text('Contacts et extensions internes', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                if (isAdmin)
                  SoftIconButton(
                    icon: Icons.person_add_alt_1_rounded,
                    tooltip: 'Ajouter un contact',
                    onTap: () => _openContactEditor(context, appState),
                  ),
              ],
            ),
          ),"""
new_dir_header = """        if (widget.embedded && isAdmin)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Align(
              alignment: Alignment.centerRight,
              child: SoftIconButton(
                icon: Icons.person_add_alt_1_rounded,
                tooltip: 'Ajouter un contact',
                onTap: () => _openContactEditor(context, appState),
              ),
            ),
          ),"""
if old_dir_header not in d:
    raise SystemExit("V11.6.28: embedded directory header anchor missing")
d = d.replace(old_dir_header, new_dir_header, 1)
directory.write_text(d)

# ---------------------------------------------------------------------------
# Profile: AppBar itself becomes the only profile header. Move Settings action
# into that AppBar and remove the inner "Mon profil" logo/title row.
# ---------------------------------------------------------------------------
profile = Path("lib/screens/profile_screen.dart")
p = profile.read_text()

old_profile_appbar = """    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(title: const GardeFlowTitle('Profil')),
      body: content,
    );"""
new_profile_appbar = """    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: const GardeFlowTitle('Mon profil'),
        actions: [
          IconButton(
            tooltip: 'Réglages',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: content,
    );"""
if old_profile_appbar not in p:
    raise SystemExit("V11.6.28: profile appbar anchor missing")
p = p.replace(old_profile_appbar, new_profile_appbar, 1)

old_profile_header = """        Row(
          children: [
            const GardeFlowLogo(size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Mon profil', style: Theme.of(context).textTheme.titleLarge),
                  Text('Compte, accès et préférences', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            SoftIconButton(
              icon: Icons.settings_outlined,
              tooltip: 'Réglages',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
            ),
          ],
        ),
        const SizedBox(height: 18),"""
if old_profile_header not in p:
    raise SystemExit("V11.6.28: profile duplicate header anchor missing")
p = p.replace(old_profile_header, "", 1)
p = p.replace(
    "padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),",
    "padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),",
    1,
)
profile.write_text(p)

# ---------------------------------------------------------------------------
# Notifications has a custom header rather than GardeFlowTitle.
# Remove its extra "GardeFlow" subtitle and compact the toolbar.
# ---------------------------------------------------------------------------
notifications = Path("lib/screens/notifications_screen.dart")
n = notifications.read_text()
n = n.replace("toolbarHeight: 76,", "toolbarHeight: 64,", 1)

old_notif_text = """              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Notifications',
                      style: TextStyle(
                        fontFamily: 'SpaceGrotesk',
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        color: AppColors.ink,
                        letterSpacing: -0.35,
                      ),
                    ),
                    SizedBox(height: 1),
                    Text(
                      'GardeFlow',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),"""
new_notif_text = """              const Expanded(
                child: Text(
                  'Notifications',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'SpaceGrotesk',
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                    letterSpacing: -0.35,
                  ),
                ),
              ),"""
if old_notif_text not in n:
    raise SystemExit("V11.6.28: notifications title anchor missing")
n = n.replace(old_notif_text, new_notif_text, 1)
notifications.write_text(n)

print("GardeFlow V11.6.28: en-têtes uniques logo + titre, doublons GardeFlow supprimés")
