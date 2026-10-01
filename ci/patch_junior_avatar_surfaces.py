from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def add_import(text: str, anchor: str, new_import: str, label: str) -> str:
    if new_import in text:
        return text
    if anchor not in text:
        raise SystemExit(f'{label}: import anchor not found')
    return text.replace(anchor, anchor + new_import, 1)


# Accueil : l'avatar courant remplace l'initiale du médecin connecté.
home = ROOT / 'source/lib/screens/home_screen.dart'
home_text = home.read_text(encoding='utf-8')
home_text = add_import(
    home_text,
    "import '../theme/widgets.dart';\n",
    "import '../widgets/profile_avatar.dart';\n",
    'home',
)
home_text = home_text.replace(
    """    final badge = appState.totalBadgeCount;\n    final rawInitial = user.nom.trim();\n    final initial =\n        rawInitial.isEmpty ? 'D' : rawInitial.substring(0, 1).toUpperCase();\n""",
    """    final badge = appState.totalBadgeCount;\n""",
    1,
)
old_home_avatar = """                  child: Text(\n                    initial,\n                    style: TextStyle(\n                      color: Colors.white,\n                      fontFamily: 'SpaceGrotesk',\n                      fontSize: 15,\n                      fontWeight: FontWeight.w900,\n                    ),\n                  ),\n"""
new_home_avatar = """                  child: ProfileAvatar(\n                    profileId: user.id,\n                    initials: user.initials,\n                    isJunior: user.grade == MedicalGrade.junior,\n                    radius: 18,\n                    backgroundColor: Colors.transparent,\n                    foregroundColor: Colors.white,\n                  ),\n"""
if new_home_avatar not in home_text:
    if old_home_avatar not in home_text:
        raise SystemExit('home avatar block not found')
    home_text = home_text.replace(old_home_avatar, new_home_avatar, 1)
home.write_text(home_text, encoding='utf-8')
print('home avatar: ready')

# Vue administrateur : avatar du médecin sélectionné.
admin = ROOT / 'source/lib/screens/admin_screen.dart'
admin_text = admin.read_text(encoding='utf-8')
admin_text = add_import(
    admin_text,
    "import '../theme/widgets.dart';\n",
    "import '../widgets/profile_avatar.dart';\n",
    'admin',
)
avatar_pattern = re.compile(
    r"""\s*CircleAvatar\(\s*radius:\s*21,\s*backgroundColor:\s*AppColors\.paperAlt,\s*child:\s*Text\(\s*_initials\(doctor\.fullName\),\s*style:\s*TextStyle\(\s*fontSize:\s*12,\s*fontWeight:\s*FontWeight\.w800,\s*color:\s*AppColors\.ink,\s*\),\s*\),\s*\),""",
    re.MULTILINE,
)
admin_avatar = """
            ProfileAvatar(
              profileId: doctor.id,
              initials: doctor.initials,
              isJunior: doctor.grade == MedicalGrade.junior,
              radius: 21,
              backgroundColor: AppColors.paperAlt,
              foregroundColor: AppColors.ink,
            ),"""
if admin_avatar.strip() not in admin_text:
    admin_text, count = avatar_pattern.subn(admin_avatar, admin_text, count=1)
    if count != 1:
        raise SystemExit(f'admin doctor avatar block replacement count={count}')
admin.write_text(admin_text, encoding='utf-8')
print('admin doctor avatar: ready')

# Gestion des comptes : avatar à gauche de chaque médecin.
accounts = ROOT / 'source/lib/screens/admin_password_reset_screen.dart'
accounts_text = accounts.read_text(encoding='utf-8')
accounts_text = add_import(
    accounts_text,
    "import '../theme/widgets.dart';\n",
    "import '../widgets/profile_avatar.dart';\n",
    'accounts',
)
old_accounts_avatar = """                              leading: CircleAvatar(\n                                backgroundColor: AppColors.paperAlt,\n                                child: Text(\n                                  profile.fullName.isEmpty\n                                      ? '?'\n                                      : profile.fullName\n                                            .trim()[0]\n                                            .toUpperCase(),\n                                  style: TextStyle(\n                                    fontWeight: FontWeight.w800,\n                                    color: AppColors.ink,\n                                  ),\n                                ),\n                              ),\n"""
new_accounts_avatar = """                              leading: ProfileAvatar(\n                                profileId: profile.id,\n                                initials: profile.initials,\n                                isJunior: profile.grade == MedicalGrade.junior,\n                                radius: 20,\n                                backgroundColor: AppColors.paperAlt,\n                                foregroundColor: AppColors.ink,\n                              ),\n"""
if new_accounts_avatar not in accounts_text:
    if old_accounts_avatar not in accounts_text:
        raise SystemExit('account list avatar block not found')
    accounts_text = accounts_text.replace(
        old_accounts_avatar,
        new_accounts_avatar,
        1,
    )
accounts.write_text(accounts_text, encoding='utf-8')
print('account list avatars: ready')

# Fil d'annonces : avatar de l'auteur de l'annonce.
announcements = ROOT / 'source/lib/screens/announcements_screen.dart'
ann_text = announcements.read_text(encoding='utf-8')
ann_text = add_import(
    ann_text,
    "import '../theme/widgets.dart';\n",
    "import '../widgets/profile_avatar.dart';\n",
    'announcements',
)
old_announcement_avatar = """              CircleAvatar(\n                radius: 21,\n                backgroundColor: AppColors.brandSoft,\n                child: Text(\n                  announcement.authorName.trim().isEmpty\n                      ? '?'\n                      : announcement.authorName.trim()[0].toUpperCase(),\n                  style: TextStyle(\n                    color: AppColors.brand,\n                    fontWeight: FontWeight.w900,\n                  ),\n                ),\n              ),\n"""
new_announcement_avatar = """              ProfileAvatar(\n                profileId: announcement.authorId,\n                initials: announcement.authorName.trim().isEmpty\n                    ? '?'\n                    : announcement.authorName.trim()[0].toUpperCase(),\n                isJunior: true,\n                radius: 21,\n                backgroundColor: AppColors.brandSoft,\n                foregroundColor: AppColors.brand,\n              ),\n"""
if new_announcement_avatar not in ann_text:
    if old_announcement_avatar not in ann_text:
        raise SystemExit('announcement avatar block not found')
    ann_text = ann_text.replace(
        old_announcement_avatar,
        new_announcement_avatar,
        1,
    )
announcements.write_text(ann_text, encoding='utf-8')
print('announcement avatars: ready')

# Classement Practice : avatar du médecin classé.
practice = ROOT / 'source/lib/screens/practice_screen.dart'
practice_text = practice.read_text(encoding='utf-8')
practice_text = add_import(
    practice_text,
    "import '../state/app_state.dart';\n",
    "import '../widgets/profile_avatar.dart';\n",
    'practice',
)
practice_pattern = re.compile(
    r"""CircleAvatar\(\s*radius:\s*17,\s*backgroundColor:\s*PracticeColors\.background,\s*child:\s*Text\(\s*_initials\(entry\.displayName\),\s*style:\s*const TextStyle\(\s*color:\s*PracticeColors\.accent,\s*fontSize:\s*10,\s*fontWeight:\s*FontWeight\.w900,\s*\),\s*\),\s*\)""",
    re.MULTILINE,
)
practice_avatar = """ProfileAvatar(
          profileId: entry.userId,
          initials: _initials(entry.displayName),
          isJunior: true,
          radius: 17,
          backgroundColor: PracticeColors.background,
          foregroundColor: PracticeColors.accent,
        )"""
if practice_avatar.strip() not in practice_text:
    practice_text, count = practice_pattern.subn(practice_avatar, practice_text, count=1)
    if count != 1:
        raise SystemExit(f'practice rank avatar replacement count={count}')
practice.write_text(practice_text, encoding='utf-8')
print('practice rank avatars: ready')

print('Remaining CircleAvatar occurrences:')
for path in sorted((ROOT / 'source/lib').rglob('*.dart')):
    text = path.read_text(encoding='utf-8')
    count = text.count('CircleAvatar(')
    if count:
        print(f'  {path.relative_to(ROOT)}: {count}')
