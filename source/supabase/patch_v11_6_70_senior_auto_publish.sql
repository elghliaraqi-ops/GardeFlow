-- GardeFlow V11.6.70
-- Suppression de la double validation des astreintes séniors.
-- Toute donnée structurée créée depuis l'import admin est publiée immédiatement
-- et synchronisée vers l'annuaire via les triggers existants.

alter table public.senior_oncall_assignments
  alter column validation_status set default 'validated';

update public.senior_oncall_assignments
set
  validation_status = 'validated',
  validated_at = coalesce(validated_at, now())
where validation_status <> 'validated';

create or replace function public.senior_oncall_prepare_phone()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.senior_phone := public.normalize_ma_phone(new.senior_phone);

  -- Les lignes proviennent d'un import réservé aux administrateurs :
  -- aucune seconde validation manuelle n'est nécessaire.
  new.validation_status := 'validated';
  new.validated_at := coalesce(new.validated_at, now());
  new.validated_by := coalesce(new.validated_by, auth.uid());
  new.updated_at := now();

  return new;
end;
$$;

create or replace function public.senior_oncall_roster(
  p_from date,
  p_to date
)
returns table(
  duty_date date,
  senior_name text,
  senior_phone text,
  service text,
  hospital text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    s.duty_date,
    s.senior_name,
    s.senior_phone,
    s.service,
    s.hospital
  from public.senior_oncall_assignments s
  where auth.uid() is not null
    and public.current_account_active()
    and p_from is not null
    and p_to is not null
    and p_from <= p_to
    and s.duty_date between p_from and p_to
  order by s.duty_date, s.hospital, s.service, s.senior_name;
$$;

revoke all on function public.senior_oncall_roster(date,date)
  from public, anon;
grant execute on function public.senior_oncall_roster(date,date)
  to authenticated;
