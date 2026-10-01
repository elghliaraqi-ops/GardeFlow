-- GardeFlow V12 — account-linked appearance theme.
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
