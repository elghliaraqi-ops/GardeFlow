alter table public.profiles
  add column if not exists avatar_key text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and conname = 'profiles_avatar_key_check'
  ) then
    alter table public.profiles
      add constraint profiles_avatar_key_check
      check (
        avatar_key is null
        or avatar_key in (
          'gamer_doctor_m_01',
          'gamer_doctor_f_01',
          'gamer_doctor_hijab_01',
          'gamer_doctor_f_02',
          'gamer_doctor_m_02',
          'gamer_doctor_m_03'
        )
      );
  end if;
end
$$;

create or replace function public.normalize_profile_avatar()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.medical_grade is distinct from 'junior' then
    new.avatar_key := null;
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_normalize_avatar on public.profiles;
create trigger profiles_normalize_avatar
before insert or update of medical_grade, avatar_key
on public.profiles
for each row
execute function public.normalize_profile_avatar();

create or replace function public.profile_avatar_keys()
returns table(profile_id uuid, avatar_key text)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.avatar_key
  from public.profiles p
  where auth.uid() is not null
    and public.current_account_active()
    and p.account_status = 'active'
    and p.medical_grade = 'junior';
$$;

revoke all on function public.profile_avatar_keys() from public, anon;
grant execute on function public.profile_avatar_keys() to authenticated;

create or replace function public.set_my_profile_avatar(p_avatar_key text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_grade text;
  v_status text;
begin
  if v_uid is null then
    raise exception 'unauthorized';
  end if;

  select medical_grade, account_status
    into v_grade, v_status
  from public.profiles
  where id = v_uid;

  if not found or v_status <> 'active' then
    raise exception 'inactive_account';
  end if;

  if p_avatar_key is not null and btrim(p_avatar_key) = '' then
    p_avatar_key := null;
  end if;

  if p_avatar_key is not null and p_avatar_key not in (
    'gamer_doctor_m_01',
    'gamer_doctor_f_01',
    'gamer_doctor_hijab_01',
    'gamer_doctor_f_02',
    'gamer_doctor_m_02',
    'gamer_doctor_m_03'
  ) then
    raise exception 'invalid_avatar';
  end if;

  if p_avatar_key is not null and v_grade <> 'junior' then
    raise exception 'junior_only';
  end if;

  update public.profiles
  set avatar_key = p_avatar_key,
      updated_at = now()
  where id = v_uid;
end;
$$;

revoke all on function public.set_my_profile_avatar(text) from public, anon;
grant execute on function public.set_my_profile_avatar(text) to authenticated;
