alter table public.profiles
  add column if not exists avatar_key text;

alter table public.profiles
  drop constraint if exists profiles_avatar_key_valid;

alter table public.profiles
  add constraint profiles_avatar_key_valid
  check (
    avatar_key is null
    or avatar_key in (
      'gamer_doctor_f_01',
      'gamer_doctor_m_01',
      'gamer_doctor_hijab_01',
      'gamer_doctor_f_02',
      'gamer_doctor_m_03',
      'gamer_doctor_m_02'
    )
  );

create or replace function public.enforce_junior_profile_avatar()
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

drop trigger if exists profiles_enforce_junior_avatar on public.profiles;
create trigger profiles_enforce_junior_avatar
before insert or update of medical_grade, avatar_key
on public.profiles
for each row
execute function public.enforce_junior_profile_avatar();

create or replace function public.profile_avatar_keys()
returns table(profile_id uuid, avatar_key text)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.avatar_key
  from public.profiles p
  where p.account_status = 'active'
    and p.medical_grade = 'junior';
$$;

revoke all on function public.profile_avatar_keys() from public, anon;
grant execute on function public.profile_avatar_keys() to authenticated;

create or replace function public.set_my_profile_avatar(p_avatar_key text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_avatar_key text := nullif(btrim(coalesce(p_avatar_key, '')), '');
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  if v_avatar_key is not null
    and v_avatar_key not in (
      'gamer_doctor_f_01',
      'gamer_doctor_m_01',
      'gamer_doctor_hijab_01',
      'gamer_doctor_f_02',
      'gamer_doctor_m_03',
      'gamer_doctor_m_02'
    ) then
    raise exception 'invalid_avatar' using errcode = '22023';
  end if;

  update public.profiles
  set avatar_key = v_avatar_key,
      updated_at = now()
  where id = auth.uid()
    and account_status = 'active'
    and medical_grade = 'junior';

  if not found then
    raise exception 'avatar_reserved_to_juniors' using errcode = '42501';
  end if;

  return v_avatar_key;
end;
$$;

revoke all on function public.set_my_profile_avatar(text) from public, anon;
grant execute on function public.set_my_profile_avatar(text) to authenticated;
