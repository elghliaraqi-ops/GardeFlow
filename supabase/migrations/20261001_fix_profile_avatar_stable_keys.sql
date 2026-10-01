-- Keep avatar identity stable independently from artwork filenames.
-- The Flutter client persists avatar_1 .. avatar_6; Supabase must accept
-- and return the same keys.

alter table public.profiles
  drop constraint if exists profiles_avatar_key_check;

-- Preserve any selections written by the original avatar implementation.
update public.profiles
set avatar_key = case avatar_key
  when 'gamer_doctor_m_01' then 'avatar_1'
  when 'gamer_doctor_f_01' then 'avatar_2'
  when 'gamer_doctor_hijab_01' then 'avatar_3'
  when 'gamer_doctor_f_02' then 'avatar_4'
  when 'gamer_doctor_m_02' then 'avatar_5'
  when 'gamer_doctor_m_03' then 'avatar_6'
  else avatar_key
end
where avatar_key in (
  'gamer_doctor_m_01',
  'gamer_doctor_f_01',
  'gamer_doctor_hijab_01',
  'gamer_doctor_f_02',
  'gamer_doctor_m_02',
  'gamer_doctor_m_03'
);

alter table public.profiles
  add constraint profiles_avatar_key_check
  check (
    avatar_key is null or avatar_key in (
      'avatar_1',
      'avatar_2',
      'avatar_3',
      'avatar_4',
      'avatar_5',
      'avatar_6'
    )
  );

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
    'avatar_1',
    'avatar_2',
    'avatar_3',
    'avatar_4',
    'avatar_5',
    'avatar_6'
  ) then
    raise exception 'invalid_avatar';
  end if;

  if p_avatar_key is not null and v_grade <> 'junior' then
    raise exception 'junior_only';
  end if;

  update public.profiles
  set avatar_key = p_avatar_key
  where id = v_uid;
end;
$$;

revoke all on function public.set_my_profile_avatar(text) from public;
grant execute on function public.set_my_profile_avatar(text) to authenticated;
