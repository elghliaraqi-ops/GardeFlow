-- GardeFlow v11.6.70
-- Dynamic internship promotion policy.
-- The highest active junior promotion is the first-year cohort.
-- First-year doctors may transfer/exchange only with their own cohort.
-- Older cohorts may transfer/exchange among themselves.

create table if not exists public.internship_promotion_config (
  id smallint primary key default 1 check (id = 1),
  current_first_year_promotion smallint not null check (current_first_year_promotion > 0),
  updated_at timestamptz not null default now()
);

insert into public.internship_promotion_config(id, current_first_year_promotion)
values (
  1,
  coalesce((
    select max(promotion_number)::smallint
    from public.profiles
    where medical_grade = 'junior'
      and account_status = 'active'
      and promotion_number is not null
  ), 7)
)
on conflict (id) do update
set current_first_year_promotion = greatest(
      public.internship_promotion_config.current_first_year_promotion,
      excluded.current_first_year_promotion
    ),
    updated_at = now();

alter table public.internship_promotion_config enable row level security;
revoke all on public.internship_promotion_config from anon;
grant select on public.internship_promotion_config to authenticated;
drop policy if exists internship_promotion_config_read on public.internship_promotion_config;
create policy internship_promotion_config_read
on public.internship_promotion_config
for select
to authenticated
using (true);

create or replace function public.sync_current_first_year_promotion()
returns trigger
language plpgsql
security definer
set search_path = 'public', 'pg_temp'
as $$
begin
  if new.medical_grade = 'junior'
     and new.account_status = 'active'
     and new.promotion_number is not null then
    update public.internship_promotion_config
    set current_first_year_promotion = greatest(current_first_year_promotion, new.promotion_number),
        updated_at = now()
    where id = 1;
  end if;
  return new;
end;
$$;
revoke all on function public.sync_current_first_year_promotion() from public, anon, authenticated;

drop trigger if exists profiles_sync_current_first_year_promotion on public.profiles;
create trigger profiles_sync_current_first_year_promotion
after insert or update of promotion_number, medical_grade, account_status
on public.profiles
for each row
execute function public.sync_current_first_year_promotion();

create or replace function public.sync_profile_promotion()
returns trigger
language plpgsql
set search_path = 'public', 'pg_temp'
as $$
begin
  if coalesce(new.medical_grade, new.fonction, 'junior') = 'senior' then
    new.promotion_number := null;
    return new;
  end if;

  -- Historical PDF mapping only fills missing promotion values.
  -- It never overwrites an explicitly selected promotion.
  if new.promotion_number is null then
    new.promotion_number := public.infer_intern_promotion(new.nom, new.prenom);
  end if;
  return new;
end;
$$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  g text;
  v_promotion smallint;
  v_raw_promotion text;
begin
  g := coalesce(new.raw_user_meta_data->>'medical_grade', new.raw_user_meta_data->>'fonction', 'junior');
  if g not in ('junior','senior') then g := 'junior'; end if;

  if g = 'senior' then
    v_promotion := null;
  else
    v_promotion := null;
    v_raw_promotion := nullif(trim(coalesce(new.raw_user_meta_data->>'promotion_number','')), '');
    if v_raw_promotion ~ '^[0-9]{1,3}$' then
      v_promotion := v_raw_promotion::smallint;
      if v_promotion < 1 or v_promotion > 999 then
        v_promotion := null;
      end if;
    end if;
    v_promotion := coalesce(
      v_promotion,
      public.infer_intern_promotion(
        coalesce(new.raw_user_meta_data->>'nom',''),
        coalesce(new.raw_user_meta_data->>'prenom','')
      )
    );
  end if;

  insert into public.profiles(
    id,phone,nom,prenom,service,fonction,medical_grade,hospital,role,account_status,promotion_number
  ) values (
    new.id,
    coalesce(new.phone,new.raw_user_meta_data->>'phone'),
    coalesce(new.raw_user_meta_data->>'nom',''),
    coalesce(new.raw_user_meta_data->>'prenom',''),
    coalesce(new.raw_user_meta_data->>'service',''),
    g,
    g,
    coalesce(new.raw_user_meta_data->>'hospital',''),
    'medecin',
    'pending',
    v_promotion
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create or replace function public.enforce_exchange_promotion_scope()
returns trigger
language plpgsql
security definer
set search_path = 'public', 'pg_temp'
as $$
declare
  p_from smallint;
  p_to smallint;
  p_first_year smallint;
begin
  select promotion_number into p_from from public.profiles where id = new.from_id;
  select promotion_number into p_to from public.profiles where id = new.to_id;
  select current_first_year_promotion into p_first_year
  from public.internship_promotion_config
  where id = 1;

  if p_first_year is not null
     and p_from is not null
     and p_to is not null
     and p_from <> p_to
     and (p_from = p_first_year or p_to = p_first_year) then
    raise exception 'La promotion de première année (Promo %) ne peut transférer ou échanger des gardes qu’avec la même promotion', p_first_year;
  end if;

  return new;
end;
$$;
revoke all on function public.enforce_exchange_promotion_scope() from public, anon, authenticated;
