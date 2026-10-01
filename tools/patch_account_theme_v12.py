from pathlib import Path
import re

ROOT = Path('.')


def read(path):
    return (ROOT / path).read_text(encoding='utf-8')


def write(path, text):
    p = ROOT / path
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding='utf-8')


def replace_exact(path, old, new, expected=1):
    text = read(path)
    count = text.count(old)
    if count != expected:
        raise RuntimeError(f'{path}: expected {expected} occurrence(s), found {count} for {old[:80]!r}')
    write(path, text.replace(old, new))


# 1) AppUser: persist the account-level appearance preference and provide copyWith.
path = 'source/lib/models/app_user.dart'
text = read(path)
text = text.replace(
    "  final AccountStatus accountStatus;\n",
    "  final AccountStatus accountStatus;\n  final String appearanceTheme;\n",
    1,
)
text = text.replace(
    "    this.accountStatus = AccountStatus.active,\n  });\n",
    "    this.accountStatus = AccountStatus.active,\n    this.appearanceTheme = 'black',\n  });\n",
    1,
)
text = text.replace(
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
    1,
)
text = text.replace(
    "        'accountStatus': accountStatus.name,\n      };\n",
    "        'accountStatus': accountStatus.name,\n        'appearanceTheme': appearanceTheme,\n      };\n",
    1,
)
text = text.replace(
    "    return AppUser(\n",
    "    final rawAppearance =\n"
    "        (json['appearanceTheme'] as String?) ??\n"
    "        (json['appearance_theme'] as String?);\n"
    "    const allowedAppearance = <String>{'green', 'red', 'white', 'black'};\n"
    "    final appearanceTheme =\n"
    "        allowedAppearance.contains(rawAppearance) ? rawAppearance! : 'black';\n"
    "    return AppUser(\n",
    1,
)
text = text.replace(
    "      accountStatus: AccountStatus.values.byName((json['accountStatus'] as String?) ?? 'active'),\n",
    "      accountStatus: AccountStatus.values.byName((json['accountStatus'] as String?) ?? 'active'),\n      appearanceTheme: appearanceTheme,\n",
    1,
)
write(path, text)

# 2) Global visual defaults: true black is now the default/fallback.
replace_exact(
    'source/lib/theme/app_theme.dart',
    "  static String _appearanceTheme = 'green';\n",
    "  static String _appearanceTheme = 'black';\n",
)
replace_exact(
    'source/lib/theme/app_theme.dart',
    "    _appearanceTheme = allowed.contains(value) ? value : 'green';\n",
    "    _appearanceTheme = allowed.contains(value) ? value : 'black';\n",
)

# 3) Supabase service: read/write appearance_theme as an account preference.
path = 'source/lib/services/supabase_backend_service.dart'
text = read(path)
needle = "  Future<AppUser> fetchMyProfile() async {\n    final uid = client.auth.currentUser?.id;\n    if (uid == null) throw StateError('Session Supabase absente.');\n    final row = await client.from('profiles').select().eq('id', uid).single();\n    return _profileToUser(Map<String, dynamic>.from(row));\n  }\n"
if needle not in text:
    raise RuntimeError('fetchMyProfile block not found')
replacement = needle + "\n  Future<void> setMyAppearanceTheme(String value) async {\n    const allowed = <String>{'green', 'red', 'white', 'black'};\n    if (!allowed.contains(value)) {\n      throw ArgumentError('Thème d’apparence invalide.');\n    }\n    if (client.auth.currentUser == null) {\n      throw StateError('Session Supabase absente.');\n    }\n    await client.rpc(\n      'set_my_appearance_theme',\n      params: {'p_theme': value},\n    );\n  }\n"
text = text.replace(needle, replacement, 1)
old_select = "            'id,nom,prenom,phone,role,service,medical_grade,hospital,account_status,promotion_number',\n"
new_select = "            'id,nom,prenom,phone,role,service,medical_grade,hospital,account_status,promotion_number,appearance_theme',\n"
if old_select not in text:
    raise RuntimeError('fetchVisibleProfiles select not found')
text = text.replace(old_select, new_select, 1)
old_map = "      promotionNumber: (j['promotion_number'] as num?)?.toInt(),\n      role: UserRole.values.byName((j['role'] as String?) ?? 'medecin'),\n"
new_map = "      promotionNumber: (j['promotion_number'] as num?)?.toInt(),\n      appearanceTheme: const <String>{\n        'green',\n        'red',\n        'white',\n        'black',\n      }.contains(j['appearance_theme']?.toString())\n          ? j['appearance_theme'].toString()\n          : 'black',\n      role: UserRole.values.byName((j['role'] as String?) ?? 'medecin'),\n"
if old_map not in text:
    raise RuntimeError('_profileToUser mapping anchor not found')
text = text.replace(old_map, new_map, 1)
write(path, text)

# 4) AppState: black fallback + account-first persistence/synchronisation.
path = 'source/lib/state/app_state.dart'
text = read(path)
text = text.replace("  String _appearanceTheme = 'green';\n", "  String _appearanceTheme = 'black';\n", 1)
old_setter = "  Future<void> setAppearanceTheme(String value) async {\n    const allowed = <String>{'green', 'red', 'white', 'black'};\n    final next = allowed.contains(value) ? value : 'green';\n    if (_appearanceTheme == next) return;\n    _appearanceTheme = next;\n    await _persistNow();\n    notifyListeners();\n  }\n"
new_setter = "  Future<void> setAppearanceTheme(String value) async {\n    const allowed = <String>{'green', 'red', 'white', 'black'};\n    final next = allowed.contains(value) ? value : 'black';\n    if (_appearanceTheme == next && currentUser?.appearanceTheme == next) return;\n\n    // When signed in, write the preference to the account first so a failed\n    // network update cannot pretend that the choice is synchronised.\n    if (backendEnabled && currentUser != null) {\n      await SupabaseBackendService.instance.setMyAppearanceTheme(next);\n    }\n\n    _appearanceTheme = next;\n    final me = currentUser;\n    if (me != null) {\n      final updated = me.copyWith(appearanceTheme: next);\n      currentUser = updated;\n      final index = _users.indexWhere((u) => u.id == updated.id);\n      if (index >= 0) _users[index] = updated;\n    }\n    await _persistNow();\n    notifyListeners();\n  }\n"
if old_setter not in text:
    raise RuntimeError('setAppearanceTheme block not found')
text = text.replace(old_setter, new_setter, 1)

# Backend-restored session: server preference wins.
old = "          state.currentUser = profile;\n          await LocalStorageService.savePushActiveUserId(profile.id);\n"
new = "          state.currentUser = profile;\n          state._appearanceTheme = profile.appearanceTheme;\n          await LocalStorageService.savePushActiveUserId(profile.id);\n"
if old not in text:
    raise RuntimeError('startup profile assignment not found')
text = text.replace(old, new, 1)

# Local restored session: keep that account's persisted preference.
old = "        if (state.currentUser != null) state._sessionEpoch++;\n        state._applyReminderPrefsForCurrentUser();\n"
new = "        if (state.currentUser != null) {\n          state._sessionEpoch++;\n          state._appearanceTheme = state.currentUser!.appearanceTheme;\n        }\n        state._applyReminderPrefsForCurrentUser();\n"
if old not in text:
    raise RuntimeError('local session theme anchor not found')
text = text.replace(old, new, 1)

# Every login/signup assignment adopts the account theme immediately.
pattern = re.compile(r'(?m)^(\s*)currentUser = user;\n')
text, count = pattern.subn(r'\1currentUser = user;\n\1_appearanceTheme = user.appearanceTheme;\n', text)
if count < 2:
    raise RuntimeError(f'expected at least 2 currentUser=user assignments, found {count}')

# Backend realtime/profile refresh can also change the theme from another device.
old = "      currentUser = refreshedMe;\n"
new = "      currentUser = refreshedMe;\n      _appearanceTheme = refreshedMe.appearanceTheme;\n"
if old not in text:
    raise RuntimeError('refreshedMe assignment not found')
text = text.replace(old, new, 1)

# Old local states without an appearance choice migrate to black.
old = "    }.contains(storedAppearanceTheme)\n        ? storedAppearanceTheme!\n        : 'green';\n"
new = "    }.contains(storedAppearanceTheme)\n        ? storedAppearanceTheme!\n        : 'black';\n"
if old not in text:
    raise RuntimeError('restore appearance fallback not found')
text = text.replace(old, new, 1)

# Logging out should not leave the previous account's visual preference on auth screens.
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
text = text.replace(
    "                        'Choisissez l’apparence générale de GardeFlow. Le vert reste le thème par défaut.',\n",
    "                        'Le noir est le thème par défaut. Votre choix est enregistré sur votre compte et vous suit sur Web, Android et vos autres appareils.',\n",
    1,
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
if old_choices not in text:
    raise RuntimeError('settings choices block not found')
text = text.replace(old_choices, new_choices, 1)

# Surface server sync failures instead of silently presenting them as saved.
old_on_tap = "        onTap: () => appState.setAppearanceTheme(value),\n"
new_on_tap = "        onTap: () async {\n          try {\n            await appState.setAppearanceTheme(value);\n          } catch (_) {\n            if (!context.mounted) return;\n            ScaffoldMessenger.of(context).showSnackBar(\n              const SnackBar(\n                content: Text(\n                  'Impossible de synchroniser le thème avec votre compte. Réessayez.',\n                ),\n              ),\n            );\n          }\n        },\n"
if old_on_tap not in text:
    raise RuntimeError('settings onTap anchor not found')
text = text.replace(old_on_tap, new_on_tap, 1)
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
