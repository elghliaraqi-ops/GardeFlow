from pathlib import Path
import re

ROOT = Path('.')


def read(path):
    return (ROOT / path).read_text(encoding='utf-8')


def write(path, text):
    p = ROOT / path
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding='utf-8')


def require_replace(text, old, new, label, expected=1):
    count = text.count(old)
    if count != expected:
        raise RuntimeError(f'{label}: expected {expected} occurrence(s), found {count}')
    return text.replace(old, new, expected)


# 1) AppUser: persist the account-level appearance preference and provide copyWith.
path = 'source/lib/models/app_user.dart'
text = read(path)
text = require_replace(
    text,
    "  final AccountStatus accountStatus;\n",
    "  final AccountStatus accountStatus;\n  final String appearanceTheme;\n",
    'AppUser field',
)
text = require_replace(
    text,
    "    this.accountStatus = AccountStatus.active,\n  });\n",
    "    this.accountStatus = AccountStatus.active,\n    this.appearanceTheme = 'black',\n  });\n",
    'AppUser constructor',
)
text = require_replace(
    text,
    "  String get fullName => '$prenom $nom';\n",
    "  AppUser copyWith({\n"
    "    String? nom,\n"
    "    String? prenom,\n"
    "    String? phone,\n"
    "    String? passwordHash,\n"
    "    String? passwordSalt,\n"
    "    String? service,\n"
    "    MedicalGrade? grade,\n"
    "    String? hospital,\n"
    "    int? promotionNumber,\n"
    "    bool clearPromotionNumber = false,\n"
    "    UserRole? role,\n"
    "    AccountStatus? accountStatus,\n"
    "    String? appearanceTheme,\n"
    "  }) {\n"
    "    return AppUser(\n"
    "      id: id,\n"
    "      nom: nom ?? this.nom,\n"
    "      prenom: prenom ?? this.prenom,\n"
    "      phone: phone ?? this.phone,\n"
    "      passwordHash: passwordHash ?? this.passwordHash,\n"
    "      passwordSalt: passwordSalt ?? this.passwordSalt,\n"
    "      service: service ?? this.service,\n"
    "      grade: grade ?? this.grade,\n"
    "      hospital: hospital ?? this.hospital,\n"
    "      promotionNumber:\n"
    "          clearPromotionNumber ? null : (promotionNumber ?? this.promotionNumber),\n"
    "      role: role ?? this.role,\n"
    "      accountStatus: accountStatus ?? this.accountStatus,\n"
    "      appearanceTheme: appearanceTheme ?? this.appearanceTheme,\n"
    "    );\n"
    "  }\n\n"
    "  String get fullName => '$prenom $nom';\n",
    'AppUser copyWith insertion',
)
text = require_replace(
    text,
    "        'accountStatus': accountStatus.name,\n      };\n",
    "        'accountStatus': accountStatus.name,\n        'appearanceTheme': appearanceTheme,\n      };\n",
    'AppUser toJson',
)
factory_anchor = (
    "    final grade = rawGrade == 'senior' || legacyFonction == 'senior'\n"
    "        ? MedicalGrade.senior\n"
    "        : MedicalGrade.junior;\n"
    "    return AppUser(\n"
)
factory_replacement = (
    "    final grade = rawGrade == 'senior' || legacyFonction == 'senior'\n"
    "        ? MedicalGrade.senior\n"
    "        : MedicalGrade.junior;\n"
    "    final rawAppearance =\n"
    "        (json['appearanceTheme'] as String?) ??\n"
    "        (json['appearance_theme'] as String?);\n"
    "    const allowedAppearance = <String>{'green', 'red', 'white', 'black'};\n"
    "    final appearanceTheme =\n"
    "        allowedAppearance.contains(rawAppearance) ? rawAppearance! : 'black';\n"
    "    return AppUser(\n"
)
text = require_replace(
    text,
    factory_anchor,
    factory_replacement,
    'AppUser fromJson normalization',
)
text = require_replace(
    text,
    "      accountStatus: AccountStatus.values.byName((json['accountStatus'] as String?) ?? 'active'),\n",
    "      accountStatus: AccountStatus.values.byName((json['accountStatus'] as String?) ?? 'active'),\n      appearanceTheme: appearanceTheme,\n",
    'AppUser fromJson value',
)
write(path, text)

# 2) Global visual defaults: true black is now the default/fallback.
path = 'source/lib/theme/app_theme.dart'
text = read(path)
text = require_replace(
    text,
    "  static String _appearanceTheme = 'green';\n",
    "  static String _appearanceTheme = 'black';\n",
    'AppColors default',
)
text = require_replace(
    text,
    "    _appearanceTheme = allowed.contains(value) ? value : 'green';\n",
    "    _appearanceTheme = allowed.contains(value) ? value : 'black';\n",
    'AppColors fallback',
)
write(path, text)

# 3) Supabase service: read/write appearance_theme as an account preference.
path = 'source/lib/services/supabase_backend_service.dart'
text = read(path)
needle = "  Future<AppUser> fetchMyProfile() async {\n    final uid = client.auth.currentUser?.id;\n    if (uid == null) throw StateError('Session Supabase absente.');\n    final row = await client.from('profiles').select().eq('id', uid).single();\n    return _profileToUser(Map<String, dynamic>.from(row));\n  }\n"
replacement = needle + "\n  Future<void> setMyAppearanceTheme(String value) async {\n    const allowed = <String>{'green', 'red', 'white', 'black'};\n    if (!allowed.contains(value)) {\n      throw ArgumentError('Thème d’apparence invalide.');\n    }\n    if (client.auth.currentUser == null) {\n      throw StateError('Session Supabase absente.');\n    }\n    await client.rpc(\n      'set_my_appearance_theme',\n      params: {'p_theme': value},\n    );\n  }\n"
text = require_replace(text, needle, replacement, 'fetchMyProfile extension')
text = require_replace(
    text,
    "            'id,nom,prenom,phone,role,service,medical_grade,hospital,account_status,promotion_number',\n",
    "            'id,nom,prenom,phone,role,service,medical_grade,hospital,account_status,promotion_number,appearance_theme',\n",
    'visible profiles select',
)
text = require_replace(
    text,
    "      promotionNumber: (j['promotion_number'] as num?)?.toInt(),\n      role: UserRole.values.byName((j['role'] as String?) ?? 'medecin'),\n",
    "      promotionNumber: (j['promotion_number'] as num?)?.toInt(),\n      appearanceTheme: const <String>{\n        'green',\n        'red',\n        'white',\n        'black',\n      }.contains(j['appearance_theme']?.toString())\n          ? j['appearance_theme'].toString()\n          : 'black',\n      role: UserRole.values.byName((j['role'] as String?) ?? 'medecin'),\n",
    '_profileToUser mapping',
)
write(path, text)

# 4) AppState: black fallback + account-first persistence/synchronisation.
path = 'source/lib/state/app_state.dart'
text = read(path)
text = require_replace(
    text,
    "  String _appearanceTheme = 'green';\n",
    "  String _appearanceTheme = 'black';\n",
    'AppState default',
)
old_setter = "  Future<void> setAppearanceTheme(String value) async {\n    const allowed = <String>{'green', 'red', 'white', 'black'};\n    final next = allowed.contains(value) ? value : 'green';\n    if (_appearanceTheme == next) return;\n    _appearanceTheme = next;\n    await _persistNow();\n    notifyListeners();\n  }\n"
new_setter = "  Future<void> setAppearanceTheme(String value) async {\n    const allowed = <String>{'green', 'red', 'white', 'black'};\n    final next = allowed.contains(value) ? value : 'black';\n    if (_appearanceTheme == next && currentUser?.appearanceTheme == next) return;\n\n    // When signed in, write the preference to the account first so a failed\n    // network update cannot pretend that the choice is synchronised.\n    if (backendEnabled && currentUser != null) {\n      await SupabaseBackendService.instance.setMyAppearanceTheme(next);\n    }\n\n    _appearanceTheme = next;\n    final me = currentUser;\n    if (me != null) {\n      final updated = me.copyWith(appearanceTheme: next);\n      currentUser = updated;\n      final index = _users.indexWhere((u) => u.id == updated.id);\n      if (index >= 0) _users[index] = updated;\n    }\n    await _persistNow();\n    notifyListeners();\n  }\n"
text = require_replace(text, old_setter, new_setter, 'AppState setter')
text = require_replace(
    text,
    "          state.currentUser = profile;\n          await LocalStorageService.savePushActiveUserId(profile.id);\n",
    "          state.currentUser = profile;\n          state._appearanceTheme = profile.appearanceTheme;\n          await LocalStorageService.savePushActiveUserId(profile.id);\n",
    'startup profile theme',
)
text = require_replace(
    text,
    "        if (state.currentUser != null) state._sessionEpoch++;\n        state._applyReminderPrefsForCurrentUser();\n",
    "        if (state.currentUser != null) {\n          state._sessionEpoch++;\n          state._appearanceTheme = state.currentUser!.appearanceTheme;\n        }\n        state._applyReminderPrefsForCurrentUser();\n",
    'local session theme',
)
pattern = re.compile(r'(?m)^(\s*)currentUser = user;\n')
text, count = pattern.subn(r'\1currentUser = user;\n\1_appearanceTheme = user.appearanceTheme;\n', text)
if count < 2:
    raise RuntimeError(f'currentUser=user assignments: expected >= 2, found {count}')
text = require_replace(
    text,
    "      currentUser = refreshedMe;\n",
    "      currentUser = refreshedMe;\n      _appearanceTheme = refreshedMe.appearanceTheme;\n",
    'realtime profile theme',
)
text = require_replace(
    text,
    "    }.contains(storedAppearanceTheme)\n        ? storedAppearanceTheme!\n        : 'green';\n",
    "    }.contains(storedAppearanceTheme)\n        ? storedAppearanceTheme!\n        : 'black';\n",
    'local restore fallback',
)
logout_start = text.find('  Future<void> logout() async {')
if logout_start >= 0:
    next_future = text.find('\n  Future<', logout_start + 20)
    if next_future < 0:
        next_future = len(text)
    block = text[logout_start:next_future]
    if "    currentUser = null;\n" in block and "_appearanceTheme = 'black';" not in block:
        block = block.replace(
            "    currentUser = null;\n",
            "    currentUser = null;\n    _appearanceTheme = 'black';\n",
            1,
        )
        text = text[:logout_start] + block + text[next_future:]
write(path, text)

# 5) Settings copy/order: black first and clear account-sync explanation.
path = 'source/lib/screens/application_settings_screen.dart'
text = read(path)
text = require_replace(
    text,
    "                        'Choisissez l’apparence générale de GardeFlow. Le vert reste le thème par défaut.',\n",
    "                        'Le noir est le thème par défaut. Votre choix est enregistré sur votre compte et vous suit sur Web, Android et vos autres appareils.',\n",
    'settings explanatory copy',
)
old_choices = """                        SizedBox(
                          width: itemWidth,
                          child: choice(
                            label: 'Vert',
                            subtitle: 'Par défaut',
                            value: 'green',
                            swatch: const Color(0xFF138A55),
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: choice(
                            label: 'Rouge',
                            subtitle: 'Rouge profond',
                            value: 'red',
                            swatch: const Color(0xFFD94A43),
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: choice(
                            label: 'Blanc',
                            subtitle: 'Ancien mode clair',
                            value: 'white',
                            swatch: Colors.white,
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: choice(
                            label: 'Noir',
                            subtitle: 'Mode sombre',
                            value: 'black',
                            swatch: const Color(0xFF101311),
                          ),
                        ),
"""
new_choices = """                        SizedBox(
                          width: itemWidth,
                          child: choice(
                            label: 'Noir',
                            subtitle: 'Par défaut · sombre',
                            value: 'black',
                            swatch: const Color(0xFF101311),
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: choice(
                            label: 'Vert',
                            subtitle: 'Vert clinique',
                            value: 'green',
                            swatch: const Color(0xFF138A55),
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: choice(
                            label: 'Rouge',
                            subtitle: 'Rouge profond',
                            value: 'red',
                            swatch: const Color(0xFFD94A43),
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: choice(
                            label: 'Blanc',
                            subtitle: 'Mode clair',
                            value: 'white',
                            swatch: Colors.white,
                          ),
                        ),
"""
text = require_replace(text, old_choices, new_choices, 'settings choices')
text = require_replace(
    text,
    "        onTap: () => appState.setAppearanceTheme(value),\n",
    "        onTap: () async {\n          try {\n            await appState.setAppearanceTheme(value);\n          } catch (_) {\n            if (!context.mounted) return;\n            ScaffoldMessenger.of(context).showSnackBar(\n              const SnackBar(\n                content: Text(\n                  'Impossible de synchroniser le thème avec votre compte. Réessayez.',\n                ),\n              ),\n            );\n          }\n        },\n",
    'settings account sync error handling',
)
write(path, text)

# 6) Track the production DB migration in-repo.
migration = """-- GardeFlow V12 — account-linked appearance theme.
-- Black is the default for every account; choices are constrained server-side.

alter table public.profiles
  add column if not exists appearance_theme text;

update public.profiles
set appearance_theme = 'black'
where appearance_theme is null
   or appearance_theme not in ('green', 'red', 'white', 'black');

alter table public.profiles
  alter column appearance_theme set default 'black',
  alter column appearance_theme set not null;

alter table public.profiles
  drop constraint if exists profiles_appearance_theme_check;

alter table public.profiles
  add constraint profiles_appearance_theme_check
  check (appearance_theme in ('green', 'red', 'white', 'black'));

create or replace function public.set_my_appearance_theme(p_theme text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_theme text := lower(trim(coalesce(p_theme, '')));
  v_status text;
begin
  if auth.uid() is null then
    raise exception 'unauthorized';
  end if;

  if v_theme not in ('green', 'red', 'white', 'black') then
    raise exception 'invalid_appearance_theme';
  end if;

  select account_status
    into v_status
  from public.profiles
  where id = auth.uid();

  if not found then
    raise exception 'profile_not_found';
  end if;

  if v_status <> 'active' then
    raise exception 'inactive_account';
  end if;

  update public.profiles
  set appearance_theme = v_theme
  where id = auth.uid();

  return v_theme;
end;
$$;

revoke all on function public.set_my_appearance_theme(text) from public;
grant execute on function public.set_my_appearance_theme(text) to authenticated;
"""
write('supabase/migrations/20261001_account_linked_appearance_theme.sql', migration)

print('Account-linked theme patch applied successfully.')
