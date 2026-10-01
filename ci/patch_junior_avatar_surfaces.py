from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text(encoding='utf-8')
    if new in text:
        print(f'{label}: already applied')
        return
    if old not in text:
        raise SystemExit(f'{label}: source block not found in {path}')
    path.write_text(text.replace(old, new, 1), encoding='utf-8')
    print(f'{label}: applied')


home = ROOT / 'source/lib/screens/home_screen.dart'
home_text = home.read_text(encoding='utf-8')
if "import '../widgets/profile_avatar.dart';" not in home_text:
    home_text = home_text.replace(
        "import '../theme/widgets.dart';\n",
        "import '../theme/widgets.dart';\nimport '../widgets/profile_avatar.dart';\n",
        1,
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
print('home avatar: applied')

admin = ROOT / 'source/lib/screens/admin_screen.dart'
admin_text = admin.read_text(encoding='utf-8')
if "import '../widgets/profile_avatar.dart';" not in admin_text:
    admin_text = admin_text.replace(
        "import '../theme/widgets.dart';\n",
        "import '../theme/widgets.dart';\nimport '../widgets/profile_avatar.dart';\n",
        1,
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
print('admin doctor avatar: applied')

print('Remaining CircleAvatar occurrences:')
for path in sorted((ROOT / 'source/lib').rglob('*.dart')):
    text = path.read_text(encoding='utf-8')
    count = text.count('CircleAvatar(')
    if count:
        print(f'  {path.relative_to(ROOT)}: {count}')
